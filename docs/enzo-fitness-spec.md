

## Strava API Endpoints

All requests are authenticated with `Authorization: Bearer {accessToken}`.

### 1. Fetch Activity List
```
GET https://www.strava.com/api/v3/athlete/activities
```
Query params:
- `before` — Unix timestamp (end bound)
- `after` — Unix timestamp (start bound = 3 years ago from today)
- `page` — integer, 1-indexed
- `per_page` — 100 (max allowed)

Fields to extract per activity:
- `id` (Int)
- `start_date` (ISO8601 string)
- `moving_time` (Int, seconds)
- `average_heartrate` (Double?, optional)
- `average_watts` (Double?, optional)
- `device_watts` (Bool — only trust `average_watts` if this is `true`)
- `sport_type` (String — filter criteria, see below)

**Fetch strategy:** paginate until either 300 activities collected or `start_date` of last activity exceeds 3 years ago, whichever comes first.

**Sport type filter — include only:**
- `Ride`
- `VirtualRide`
- `GravelRide`
- `MountainBikeRide`
- `EBikeRide`

Exclude all other sport types (Run, Swim, Walk, Hike, etc.).

### 2. Fetch Starred Segments
```
GET https://www.strava.com/api/v3/segments/starred
```
No params required. Fields to extract:
- `id` (Int)
- `name` (String)
- `distance` (Double, meters)
- `average_grade` (Double, percent)

### 3. Fetch Segment Efforts
```
GET https://www.strava.com/api/v3/segments/{segment_id}/all_efforts
```
Query params:
- `athlete_id` — current authenticated athlete's id (from `/athlete`)
- `start_date_local` — ISO8601, 3 years ago
- `end_date_local` — ISO8601, today
- `per_page` — 200
- `page` — paginate until exhausted

Fields to extract per effort:
- `id` (Int)
- `elapsed_time` (Int, seconds)
- `start_date` (ISO8601 string)
- `average_heartrate` (Double?, optional)
- `average_watts` (Double?, optional)

Fetch efforts for every starred segment.

---


## SwiftData Models

```swift
@Model class Activity {
    @Attribute(.unique) var stravaId: Int
    var date: Date
    var movingTime: Int          // seconds
    var avgHeartRate: Double?
    var avgWatts: Double?        // only populated if device_watts == true
    var tss: Double              // computed on ingest, stored
}

@Model class DailyFitness {
    @Attribute(.unique) var date: Date
    var ctl: Double
    var atl: Double
    var tsb: Double
}

@Model class StarredSegment {
    @Attribute(.unique) var segmentId: Int
    var name: String
    var distance: Double         // meters
    var avgGrade: Double         // percent
}

@Model class SegmentEffort {
    @Attribute(.unique) var stravaEffortId: Int
    var segmentId: Int
    var effortDate: Date
    var elapsedTime: Double      // seconds
    var ctlOnDay: Double         // joined from DailyFitness at effortDate - 1 day
    var tsbOnDay: Double         // joined from DailyFitness at effortDate - 1 day
}

@Model class SegmentModel {
    @Attribute(.unique) var segmentId: Int
    var beta0: Double
    var beta1: Double            // coefficient on CTL (expected: negative)
    var beta2: Double            // coefficient on TSB (expected: negative)
    var sigmaResid: Double
    var prTime: Double           // seconds — all-time best elapsed_time
    var prCTL: Double            // CTL on the day the PR was set (for naive fallback)
    var nEfforts: Int
    var ctlMin: Double           // training data range bounds (extrapolation guard)
    var ctlMax: Double
    var tsbMin: Double
    var tsbMax: Double
    var isValid: Bool            // false if wrong-sign β₁ or n < 8
    var fittedAt: Date
}
```

---

## Algorithm: LTHR Estimation

Run once per sync before computing TSS. Stored in `UserDefaults` as `lthr: Double?`.

1. Collect all `Activity` records where `20 * 60 <= movingTime <= 90 * 60` AND `avgHeartRate != nil`
2. If count < 10: set `lthr = nil`. Activities without a valid LTHR will receive `tss = 0` (rest-day equivalent — they contribute decay but no load, which is conservative and acceptable)
3. Otherwise: sort `avgHeartRate` values ascending, take the value at the 95th percentile index

---

## Algorithm: TSS Per Activity

Computed on ingest for each activity. Stored on the `Activity` model.

**Priority 1 — Power (if `avgWatts` present AND user has set FTP in UserDefaults):**
```
tss = (movingTime / 3600.0) × (avgWatts / FTP)² × 100
```

**Priority 2 — Heart rate (if `avgHeartRate` present AND `lthr` is set):**
```
tss = (movingTime / 3600.0) × (avgHeartRate / lthr)² × 100
```

**Fallback:**
```
tss = 0
```

Cap TSS at 400 per activity. Values above this indicate sensor error or data corruption.

---

## Algorithm: Daily Fitness Timeline

After all activities have TSS values, build or extend the `DailyFitness` table.

**Initialize** (first build only):
```
CTL = 0.0
ATL = 0.0
```

**Iterate over every calendar day** from date of oldest activity to today (no gaps):

```
tss_today = sum of tss for all Activity records on this date (0.0 if no rides)

// TSB = readiness going INTO the day, so use prior-day values before updating
tsb = CTL_yesterday - ATL_yesterday

// Update CTL and ATL with today's load
CTL = CTL_yesterday + (tss_today - CTL_yesterday) / 42.0
ATL = ATL_yesterday + (tss_today - ATL_yesterday) / 7.0

store DailyFitness(date: today, ctl: CTL, atl: ATL, tsb: tsb)
```

Rest days produce a row with `tss = 0`. CTL and ATL decay naturally — do not skip these days.

**On incremental sync:** extend the timeline forward from `lastSyncDate`. If any backdated activity is added (unusual but possible via manual Strava entry), rebuild from the earliest affected date forward.

---

## Algorithm: Effort-to-Fitness Join

For each `SegmentEffort`, look up `DailyFitness` for `effortDate - 1 day`:

```
joinDate = Calendar.current.date(byAdding: .day, value: -1, to: effort.effortDate)
ctlOnDay = DailyFitness[joinDate]?.ctl ?? 0.0
tsbOnDay = DailyFitness[joinDate]?.tsb ?? 0.0
```

Store `ctlOnDay` and `tsbOnDay` on the `SegmentEffort` record.

---

## Algorithm: Per-Segment OLS Regression

Refit for any segment after new efforts are added, or weekly at minimum.

For each `StarredSegment` with `segmentId = s`:

**1. Collect efforts:**
```
efforts = all SegmentEffort where segmentId == s
n = efforts.count
```

**2. Minimum sample check:**
If `n < 8`: store `SegmentModel(segmentId: s, isValid: false, nEfforts: n, prTime: min(elapsedTime), prCTL: ctlOnDay for PR effort)`. Skip regression.

**3. Build matrices:**
```
X = n×3 matrix: each row = [1.0, effort.ctlOnDay, effort.tsbOnDay]
y = n×1 vector: each row = effort.elapsedTime
```

**4. Solve via normal equations** (use Accelerate/LAPACK or equivalent):
```
β = (XᵀX)⁻¹ Xᵀy     →    [beta0, beta1, beta2]
```

Guard against singular `XᵀX` (e.g., all efforts at identical CTL). If matrix is degenerate, set `isValid = false`.

**5. Compute residual standard deviation:**
```
residuals = y - X·β
σ = sqrt( sum(residuals²) / (n - 3) )
```

**6. Wrong-sign guard:**
If `beta1 > 0` (higher fitness predicts slower time — implausible, indicates confounding): set `isValid = false`.

**7. Store SegmentModel:**
```swift
SegmentModel(
    segmentId: s,
    beta0: β[0], beta1: β[1], beta2: β[2],
    sigmaResid: σ,
    prTime: min(efforts.map { $0.elapsedTime }),
    prCTL: ctlOnDay for the effort with minimum elapsedTime,
    nEfforts: n,
    ctlMin: efforts.map { $0.ctlOnDay }.min(),
    ctlMax: efforts.map { $0.ctlOnDay }.max(),
    tsbMin: efforts.map { $0.tsbOnDay }.min(),
    tsbMax: efforts.map { $0.tsbOnDay }.max(),
    isValid: true,
    fittedAt: Date()
)
```

---

## Algorithm: PR Probability Prediction

Called at display time with today's `DailyFitness` values.

```swift
struct PredictionResult {
    let probability: Double        // 0.0–1.0
    let predictedTime: Double      // seconds (ŷ)
    let lowerBound: Double         // ŷ - σ (faster end of 1σ interval)
    let upperBound: Double         // ŷ + σ (slower end)
    let prTime: Double             // seconds
    let isValid: Bool              // false → use naive fallback
    let isExtrapolating: Bool      // true → show warning alongside result
    let nEfforts: Int
    let naiveFallback: String      // always populated regardless of isValid
}
```

**Extrapolation check:**
```
ctlExtrapolating = ctlToday > model.ctlMax * 1.1 || ctlToday < model.ctlMin * 0.9
tsbExtrapolating = tsbToday > model.tsbMax + 20 || tsbToday < model.tsbMin - 20
isExtrapolating = ctlExtrapolating || tsbExtrapolating
```

**Prediction:**
```
ŷ = beta0 + beta1 × ctlToday + beta2 × tsbToday
z = (prTime - ŷ) / sigmaResid
probability = 0.5 × (1.0 + erf(z / sqrt(2.0)))    // Darwin erf(), no external dependency
lowerBound = ŷ - sigmaResid
upperBound = ŷ + sigmaResid
```

**Naive fallback string** (always compute, used when `isValid == false`):
```
"PR set when CTL was \(Int(model.prCTL)). Your current CTL is \(Int(ctlToday))."
```

Interpretation for UI layer:
- `isValid == false` → show only `naiveFallback`, hide probability
- `isValid == true && isExtrapolating == true` → show probability with a "limited confidence" warning (current fitness is outside historical range)
- `isValid == true && isExtrapolating == false` → show probability normally

---

## Sync Strategy

### Initial Backfill (one-time, first launch after feature install)
1. Fetch athlete profile (`GET /athlete`), store `athleteId` in `UserDefaults`
2. Fetch activities: 3 years lookback, max 300 rides, filtered by sport type
3. Estimate LTHR
4. Compute TSS for all activities
5. Build DailyFitness timeline from oldest activity to today
6. Fetch starred segments
7. Fetch all segment efforts for each starred segment (3-year window)
8. Join efforts to fitness timeline
9. Fit regression models for all segments
10. Set `lastSyncDate = Date()` in `UserDefaults`

Display a progress indicator during backfill. Estimated time: 1–3 minutes depending on history volume and rate limit headroom.

### Incremental Sync (on every app launch)
1. Fetch new activities since `lastSyncDate`
2. Compute TSS for new activities
3. Extend DailyFitness timeline forward
4. Refresh starred segments list (handle newly starred or unstarred segments)
5. Fetch new segment efforts since `lastSyncDate` for all current starred segments
6. Join new efforts to fitness timeline
7. Refit models for segments with new efforts
8. Update `lastSyncDate`

### Background Sync
Register `BGAppRefreshTask` with identifier `com.enzo.fitness.sync`. On grant, run incremental sync. This is opportunistic — do not rely on it for correctness.

---

## FTP Storage

FTP is user-entered (Strava's API only exposes current FTP, not historical). Store as `Double?` in `UserDefaults` under key `athleteFTP`. If not set, power-based TSS is skipped for all activities. A settings UI entry point for FTP is outside this spec's scope but the storage key must be in place so the algorithm layer can read it.

---

## Error Handling

| Condition | Behavior |
|---|---|
| 429 Too Many Requests | Back off until next 15-min window, retry automatically via RateLimiter |
| Token refresh failure | Surface authentication error to user, halt sync gracefully |
| Segment effort fetch failure | Log error, continue with remaining segments |
| LTHR unavailable (< 10 qualifying rides) | Set `tss = 0` for HR-only activities, show one-time warning that fitness scoring is limited |
| Degenerate regression matrix | Set `isValid = false` for that segment |
| TSS > 400 | Clamp to 400, log anomaly |


