# Migration: Supabase → SwiftData (Local Storage)

## Overview

Replace Supabase (remote PostgreSQL via REST) with SwiftData (on-device SQLite) for all derived data persistence. All Supabase data is either re-derivable from Strava or small enough to store locally. The computation logic, Strava integration, and UI are unchanged — only the I/O layer swaps.

**Why:** Removes RLS debt, xcconfig complexity, network latency on app launch, and the `supabase_user_id` UUID indirection. All data is single-user and on-device; Supabase's multi-user isolation provides no value here. SwiftData's CloudKit backend is available if cross-device sync becomes a future requirement.

**Scope:** Medium. Pure I/O layer swap. No business logic changes.

---

## Architecture Before vs After

### Before
```
AppState.loadContext()
  → SupabaseService.fetchFitnessSnapshots() → HTTP GET → Supabase REST API
  → SupabaseService.fetchSegmentScores()    → HTTP GET → Supabase REST API
  → SupabaseService.fetchActiveGoal()       → HTTP GET → Supabase REST API

SyncService.syncPhase1()
  → SupabaseService.upsertFitnessSnapshot() → HTTP POST → Supabase REST API

SyncService.syncPhase2()
  → SupabaseService.upsertSegmentScore()    → HTTP POST → Supabase REST API

AppState.setGoal()
  → SupabaseService.saveGoal()              → HTTP POST → Supabase REST API
```

### After
```
AppState.loadContext()
  → ModelContext.fetch(FitnessSnapshotModel.self)  → SwiftData (on-device SQLite)
  → ModelContext.fetch(SegmentScoreModel.self)      → SwiftData
  → ModelContext.fetch(GoalModel.self)              → SwiftData

SyncService.syncPhase1()
  → ModelContext.insert/update FitnessSnapshotModel → SwiftData

SyncService.syncPhase2()
  → ModelContext.insert/update SegmentScoreModel    → SwiftData

AppState.setGoal()
  → ModelContext.insert GoalModel                   → SwiftData
```

---

## Data Model Mapping

### Supabase `fitness_snapshots` → `FitnessSnapshotModel`
```swift
@Model
final class FitnessSnapshotModel {
    @Attribute(.unique) var month: Date        // first of month, replaces "YYYY-MM-01" string
    var fitnessValue: Double                   // 0.0–1.0
    var fitnessLabel: String                   // Epic / Strong / Building / Baseline / Recovering
    var trendDirection: String                 // up / flat / down
    var hoursRidden: Double
    var activityCount: Int
    var avgEfficiency: Double

    init(month: Date, fitnessValue: Double, fitnessLabel: String,
         trendDirection: String, hoursRidden: Double,
         activityCount: Int, avgEfficiency: Double) { ... }
}
```
**Dropped:** `id` (UUID), `user_id` (UUID) — single-user device, no foreign key needed.

### Supabase `segment_scores` → `SegmentScoreModel`
```swift
@Model
final class SegmentScoreModel {
    @Attribute(.unique) var stravaSegmentId: Int       // was Int64; SwiftData supports Int
    var segmentName: String
    var prSeconds: Int
    var prAchievedAt: Date
    var fitnessValueAtPr: Double
    var currentFitnessValue: Double
    var trendDirection: String
    var lastEffortSeconds: Int
    var lastEffortDate: Date
    var strikeScore: Double
    var strikeLabel: String
    var distanceMeters: Double
    var elevationDeltaMeters: Double

    init(...) { ... }
}
```
**Dropped:** `id` (UUID), `user_id` (UUID).

### Supabase `goals` → `GoalModel`
```swift
@Model
final class GoalModel {
    var rawDescription: String
    var claudeInterpretation: String?
    var goalType: String                       // "segment_pr"
    var targetSegmentId: Int?
    var targetSegmentName: String
    var targetDate: Date?
    var targetValue: Double?
    var requiredFitnessLabel: String
    var requiredFitnessValue: Double
    var isActive: Bool
    var createdAt: Date

    init(...) { ... }
}
```
**Dropped:** `id` (UUID), `user_id` (UUID).

### Supabase `users` table → **Eliminated**
User identity is `strava_athlete_id` (Int64) in Keychain. Display name can be stored in a single `UserDefaults` key. No model class needed.

---

## Keychain Changes

### Remove
- `supabase_user_id` — no longer needed; remove `KeychainHelper.supabaseUserId` constant and all call sites

### Keep unchanged
- `strava_access_token`
- `strava_refresh_token`
- `strava_token_expiry`
- `strava_athlete_id`

---

## Files to Delete

| File | Reason |
|---|---|
| `EnzoApp/Services/SupabaseService.swift` | Replaced by SwiftData ModelContext |
| `EnzoAppTests/SupabaseServiceTests.swift` | Tests for deleted service |

---

## Files to Create

### `EnzoApp/Models/SwiftDataModels.swift`
Contains `FitnessSnapshotModel`, `SegmentScoreModel`, and `GoalModel` as `@Model` classes (schema above). Also defines the shared `ModelContainer`:

```swift
import SwiftData

extension ModelContainer {
    static var enzo: ModelContainer = {
        let schema = Schema([
            FitnessSnapshotModel.self,
            SegmentScoreModel.self,
            GoalModel.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}
```

### `EnzoAppTests/SwiftDataModelsTests.swift`
Unit tests for model init, field round-trips, and uniqueness constraints (using in-memory `ModelContainer`).

---

## Files to Modify

### `EnzoApp/EnzoAppApp.swift`
**Change:** Inject `ModelContainer` into SwiftUI environment.

```swift
// Before
WindowGroup { RootView() }
  .environment(appState)

// After
WindowGroup { RootView() }
  .environment(appState)
  .modelContainer(ModelContainer.enzo)
```

### `EnzoApp/App/AppState.swift`
This is the largest change. Summary of all modifications:

**Remove:**
- `var supabaseUserId: UUID?` property
- All `supabaseUserId` Keychain load/save in `init()` and `authenticate()`
- `private let supabaseService = SupabaseService()` (delete the service entirely)
- `supabaseService.createUser()` call in `authenticate()`
- `supabaseService.fetchUserId()` fallback in `authenticate()`
- `supabaseService.fetchUserProfile()` call in `loadContext()`
- `supabaseService.updateLastActivityDate()` — store display name + last activity date in UserDefaults instead

**Add:**
- `var modelContext: ModelContext` — initialized from `ModelContainer.enzo.mainContext`

**Modify `loadContext()`:**
```swift
// Before: fetches from Supabase via SupabaseService
let rows = try await supabaseService.fetchFitnessSnapshots(userId: supabaseUserId)

// After: fetches from local SwiftData
let descriptor = FetchDescriptor<FitnessSnapshotModel>(
    sortBy: [SortDescriptor(\.month)]
)
let rows = try modelContext.fetch(descriptor)
```
Same pattern for `loadSegments()` and `fetchActiveGoal()`.

**Modify `setGoal()`:**
```swift
// Before: calls supabaseService.saveGoal() async
// After:
// 1. Deactivate existing active goals
let activeGoals = try modelContext.fetch(FetchDescriptor<GoalModel>(
    predicate: #Predicate { $0.isActive }
))
activeGoals.forEach { $0.isActive = false }

// 2. Insert new goal
let goal = GoalModel(targetSegmentName: segment.name, ...)
modelContext.insert(goal)
try modelContext.save()
```

**Modify `resetSyncHistory()`:**
Add: `try modelContext.delete(model: FitnessSnapshotModel.self)` and same for `SegmentScoreModel`, `GoalModel` — wipes local store on reset so next sync starts clean.

### `EnzoApp/Services/SyncService.swift`
**Remove:** `supabaseService` dependency. Add `modelContext: ModelContext` parameter (passed from AppState at init time).

**Modify Phase 1 write path:**
```swift
// Before (per snapshot):
try await supabaseService.upsertFitnessSnapshot(userId: userId, row: row)

// After:
let month = row.monthDate
var descriptor = FetchDescriptor<FitnessSnapshotModel>(
    predicate: #Predicate { $0.month == month }
)
descriptor.fetchLimit = 1
if let existing = try modelContext.fetch(descriptor).first {
    existing.fitnessValue = row.fitnessValue
    existing.fitnessLabel = row.fitnessLabel
    // ... update remaining fields
} else {
    modelContext.insert(FitnessSnapshotModel(from: row))
}
try modelContext.save()
```

**Modify Phase 2 write path:** Same pattern for `SegmentScoreModel`, keyed on `stravaSegmentId`.

**Remove Phase 2 Supabase read:** Currently Phase 2 calls `fetchFitnessSnapshots()` from Supabase to look up fitness values at PR dates. Replace with local fetch:
```swift
let snapshots = try modelContext.fetch(FetchDescriptor<FitnessSnapshotModel>())
```

**Note:** `SyncService` is already initialized with `let` in `AppState.init()`. Pass `modelContext` at init time:
```swift
// AppState.init()
let ctx = ModelContainer.enzo.mainContext
self.syncService = SyncService(modelContext: ctx)
self.modelContext = ctx
```
See build-notes.md — `lazy var` is incompatible with `@Observable`, already using `let` bindings.

### `EnzoApp/Utils/Config.swift`
**Remove:**
```swift
static let supabaseURL: String = ...
static let supabaseAnonKey: String = ...
```

### `EnzoApp/Utils/KeychainHelper.swift`
**Remove:**
```swift
static let supabaseUserId = "supabase_user_id"
```
And any `load`/`save`/`delete` call sites using this key.

### `Config/Debug.xcconfig` and `Config/Release.xcconfig`
**Remove lines:**
```
SUPABASE_HOST = ...
SUPABASE_URL = ...
SUPABASE_ANON_KEY = ...
```

### `Info.plist`
**Remove entries:**
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

---

## Implementation Order

Execute in this sequence to maintain a buildable state at each step:

1. **Create `SwiftDataModels.swift`** — define all three `@Model` classes and `ModelContainer.enzo`
2. **Inject `ModelContainer` in `EnzoAppApp.swift`** — app now has model container in environment
3. **Add `modelContext` to `AppState`** — wire `ModelContainer.enzo.mainContext`, no behaviour change yet
4. **Migrate `SyncService`** — swap Supabase write/read calls for ModelContext operations; remove `supabaseService` dependency from SyncService
5. **Migrate `AppState.loadContext()` and `loadSegments()`** — swap Supabase reads for local fetches
6. **Migrate `AppState.setGoal()`** — swap Supabase goal write for ModelContext insert
7. **Migrate `AppState.authenticate()`** — remove `createUser()` and `supabaseUserId` Keychain handling
8. **Migrate `AppState.resetSyncHistory()`** — add local store wipe
9. **Delete `SupabaseService.swift`** — build will fail here until all call sites are removed; fix any remaining
10. **Clean `Config.swift`**, **xcconfig files**, **Info.plist** — remove Supabase keys
11. **Clean `KeychainHelper.swift`** — remove `supabaseUserId` constant
12. **Delete `SupabaseServiceTests.swift`**, **add `SwiftDataModelsTests.swift`**
13. **Full build + test pass**

---

## Conversion Helpers

Add these `init` convenience methods to each `@Model` class to convert from the existing row types used by `SyncService`:

```swift
extension FitnessSnapshotModel {
    convenience init(from row: FitnessSnapshotRow) {
        self.init(
            month: row.monthDate,         // add monthDate computed prop to FitnessSnapshotRow
            fitnessValue: row.fitnessValue,
            fitnessLabel: row.fitnessLabel,
            trendDirection: row.trendDirection,
            hoursRidden: row.hoursRidden,
            activityCount: row.activityCount,
            avgEfficiency: row.avgEfficiency
        )
    }
}
```

`FitnessSnapshotRow.monthDate` is a new computed property that parses the existing `month: String` ("YYYY-MM-01") into a `Date`.

The domain-facing types `FitnessSnapshot` and `SegmentScore` (used by AppState/Views) are already separate from the row types — they remain unchanged. Add `init(from: FitnessSnapshotModel)` to each domain type, or map inline in `loadContext()`.

---

## Testing Verification

After implementation, verify end-to-end:

1. **Fresh install:** Delete app → reinstall → onboard → complete Phase 1 + Phase 2 → verify fitness chart and segments load correctly from local store
2. **App relaunch:** Force-quit → reopen → data loads without re-sync (no network calls to Supabase)
3. **Goal persistence:** Set a goal → force-quit → reopen → goal is still active
4. **Reset sync:** Settings → Reset sync history → local SwiftData store is wiped → re-sync produces correct data
5. **Build:** `xcodebuild` produces zero warnings about removed Supabase symbols
6. **No Supabase references:** `grep -r "supabase" EnzoApp/` returns zero results (case-insensitive)
7. **Tests:** `xcodebuild test` passes (unit tests only; integration tests for Supabase are deleted)

---

## What Does NOT Change

- Strava OAuth flow and token management
- `SyncService.computeSnapshots()` — pure function, untouched
- Strike score formula and all fitness computation
- All views and navigation
- `ClaudeService` and all AI prompt logic
- `AthleteContext` domain model
- UserDefaults keys for sync timestamps and Claude response cache
- Keychain keys for Strava credentials
