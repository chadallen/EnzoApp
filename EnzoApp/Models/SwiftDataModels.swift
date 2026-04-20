import Foundation
import SwiftData

// MARK: - Overview
//
// SwiftData persistence layer for Enzo. Replaces the previous Supabase REST backend.
//
// All data here is derived — it can be regenerated from Strava at any time via a full re-sync.
// Raw Strava activity data is never stored; only computed outputs live here.
//
// Single-user device design: no user_id foreign keys. Every @Model instance implicitly
// belongs to the authenticated athlete. This removes the UUID indirection that Supabase
// required for multi-user row isolation.
//
// Persistence is stored in the default SwiftData location (Application Support).
// Use ModelContainer.enzo (defined below) as the shared container throughout the app.
//
// CloudKit note: SwiftData has a CloudKit sync backend available via
//   ModelConfiguration(cloudKitContainerIdentifier:)
// Switching to it is a one-line change here. That path is available if cross-device
// sync becomes a requirement in a future version.

// MARK: - FitnessSnapshotModel

/// Persisted monthly fitness summary. One row per calendar month.
///
/// Computed by SyncService.computeSnapshots() from Strava activity history.
/// Never written directly from the UI — always derived from a sync run.
///
/// `month` is stored as a UTC Date (midnight on the first of the month).
/// This replaces the Supabase "yyyy-MM-01" String format — Date is safer
/// for comparisons and avoids string parsing in FetchDescriptor predicates.
@Model
final class FitnessSnapshotModel {
    /// UTC midnight on the first of the month. Unique constraint enforces one row per month.
    /// Use FetchDescriptor with `#Predicate { $0.month == monthDate }` to look up a specific month.
    @Attribute(.unique) var month: Date

    /// Normalized fitness value 0.0–1.0. Computed via percentile normalization (5th/95th)
    /// across all-time efficiency scores. 1.0 = best month ever, 0.0 = worst.
    var fitnessValue: Double

    /// Human-readable label mapped from fitnessValue:
    /// ≥0.85 Epic | 0.65–0.85 Strong | 0.45–0.65 Building | 0.25–0.45 Baseline | <0.25 Recovering
    var fitnessLabel: String

    /// Trend relative to the prior 4-week window: "up" | "flat" | "down"
    var trendDirection: String

    /// Total hours ridden in this calendar month (not the rolling window).
    var hoursRidden: Double

    /// Number of qualifying rides in this calendar month.
    var activityCount: Int

    /// Average efficiency across the 2-month rolling window used to compute fitnessValue.
    /// Stored for diagnostics; not displayed in the UI.
    var avgEfficiency: Double

    init(month: Date, fitnessValue: Double, fitnessLabel: String,
         trendDirection: String, hoursRidden: Double,
         activityCount: Int, avgEfficiency: Double) {
        self.month = month
        self.fitnessValue = fitnessValue
        self.fitnessLabel = fitnessLabel
        self.trendDirection = trendDirection
        self.hoursRidden = hoursRidden
        self.activityCount = activityCount
        self.avgEfficiency = avgEfficiency
    }

    /// Convenience init from the FitnessSnapshotRow DTO used by SyncService.
    /// `row.monthDate` converts the "yyyy-MM-dd" String to a UTC Date.
    convenience init(from row: FitnessSnapshotRow) {
        self.init(
            month: row.monthDate,
            fitnessValue: row.fitnessValue,
            fitnessLabel: row.fitnessLabel,
            trendDirection: row.trendDirection,
            hoursRidden: row.hoursRidden ?? 0,
            activityCount: row.activityCount ?? 0,
            avgEfficiency: row.avgEfficiency ?? 0
        )
    }

    /// Converts to the FitnessSnapshot domain model used by AppState and views.
    /// Formats `month` back to "yyyy-MM" string — the format expected by chart/display code.
    func toSnapshot() -> FitnessSnapshot {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "UTC")
        let monthStr = f.string(from: month)
        return FitnessSnapshot(
            month: monthStr,
            label: fitnessLabel,
            value: fitnessValue,
            hours: hoursRidden,
            rides: activityCount,
            trend: trendDirection
        )
    }
}

// MARK: - SegmentScoreModel

/// Persisted segment PR and strike score. One row per Strava segment.
///
/// Computed by SyncService.syncPhase2() from detailed activity responses.
/// Only segments where the athlete has set a PR (prRank == 1) are stored.
/// Non-PR efforts update lastEffortSeconds/lastEffortDate on the existing row.
///
/// Date fields (prAchievedAt, lastEffortDate) are stored as "yyyy-MM-dd" Strings
/// because they are only ever displayed — no Date arithmetic is needed on them.
@Model
final class SegmentScoreModel {
    /// Strava's numeric segment ID. Unique constraint enforces one row per segment.
    /// Stored as Int (not Int64) because SwiftData maps Int to INTEGER in SQLite,
    /// which is 64-bit on all Apple platforms — no precision loss.
    @Attribute(.unique) var stravaSegmentId: Int

    var segmentName: String

    /// PR elapsed time in seconds.
    var prSeconds: Int

    /// Date the PR was set, "yyyy-MM-DD". Used for display and PR age bonus calculation.
    var prAchievedAt: String

    /// Athlete's normalized fitness value (0.0–1.0) at the time they set this PR.
    /// Used as the baseline for strike score: how fit do you need to be to beat this?
    var fitnessValueAtPr: Double

    /// Athlete's current normalized fitness value (0.0–1.0).
    /// Snapshot at the time of the last Phase 2 sync run.
    var currentFitnessValue: Double

    /// Current fitness trend direction: "up" | "flat" | "down"
    var trendDirection: String

    /// Elapsed time of the athlete's most recent effort on this segment, in seconds.
    /// May equal prSeconds if the PR is also the most recent effort.
    var lastEffortSeconds: Int

    /// Date of the most recent effort, "yyyy-MM-DD".
    var lastEffortDate: String

    /// Strike score 0.0–1.0: probability of beating the PR at current fitness.
    /// Formula: clamp(0.75 + fitnessDelta + prAgeBonus + effortGapModifier, 0, 1)
    /// At parity → 0.75 ("Almost there"). See SegmentScorer for full formula.
    var strikeScore: Double

    /// Human-readable label mapped from strikeScore:
    /// ≥0.80 "Strike now" | 0.65–0.80 "Almost there" | 0.45–0.65 "Worth a shot" |
    /// 0.25–0.45 "Getting there" | <0.25 "Build first"
    var strikeLabel: String

    /// Segment distance in meters. Used in SegmentDetailView for display.
    var distanceMeters: Double

    /// Elevation delta (high - low) in meters. Used for display context.
    var elevationDeltaMeters: Double

    /// JSON-encoded [EffortRecord] array, newest-first, capped at 20.
    /// Default "[]" so existing rows migrate cleanly on first launch after schema change.
    var effortsJSON: String = "[]"

    init(stravaSegmentId: Int, segmentName: String, prSeconds: Int,
         prAchievedAt: String, fitnessValueAtPr: Double, currentFitnessValue: Double,
         trendDirection: String, lastEffortSeconds: Int, lastEffortDate: String,
         strikeScore: Double, strikeLabel: String, distanceMeters: Double,
         elevationDeltaMeters: Double, effortsJSON: String = "[]") {
        self.stravaSegmentId = stravaSegmentId
        self.segmentName = segmentName
        self.prSeconds = prSeconds
        self.prAchievedAt = prAchievedAt
        self.fitnessValueAtPr = fitnessValueAtPr
        self.currentFitnessValue = currentFitnessValue
        self.trendDirection = trendDirection
        self.lastEffortSeconds = lastEffortSeconds
        self.lastEffortDate = lastEffortDate
        self.strikeScore = strikeScore
        self.strikeLabel = strikeLabel
        self.distanceMeters = distanceMeters
        self.elevationDeltaMeters = elevationDeltaMeters
        self.effortsJSON = effortsJSON
    }

    /// Convenience init from the SegmentScoreRow DTO used by SyncService.
    convenience init(from row: SegmentScoreRow) {
        self.init(
            stravaSegmentId: Int(row.stravaSegmentId),
            segmentName: row.segmentName ?? "",
            prSeconds: row.prSeconds ?? 0,
            prAchievedAt: row.prAchievedAt ?? "",
            fitnessValueAtPr: row.fitnessValueAtPr ?? 0,
            currentFitnessValue: row.currentFitnessValue ?? 0,
            trendDirection: row.trendDirection ?? "flat",
            lastEffortSeconds: row.lastEffortSeconds ?? 0,
            lastEffortDate: row.lastEffortDate ?? "",
            strikeScore: row.strikeScore ?? 0,
            strikeLabel: row.strikeLabel ?? "",
            distanceMeters: row.distanceMeters ?? 0,
            elevationDeltaMeters: row.elevationDeltaMeters ?? 0,
            effortsJSON: row.effortsJSON ?? "[]"
        )
    }

    /// Converts to the SegmentScore domain model used by AppState and views.
    /// distanceMeters/elevationDeltaMeters are nil-coalesced back to Optional
    /// because the domain model uses Optional for "not available".
    func toSegmentScore() -> SegmentScore {
        SegmentScore(
            name: segmentName,
            prSeconds: prSeconds,
            prDate: prAchievedAt,
            fitnessValueAtPR: fitnessValueAtPr,
            currentFitnessValue: currentFitnessValue,
            trendDirection: trendDirection,
            lastEffortSeconds: lastEffortSeconds,
            strikeScore: strikeScore,
            strikeLabel: strikeLabel,
            distanceMeters: distanceMeters > 0 ? distanceMeters : nil,
            elevationDeltaMeters: elevationDeltaMeters != 0 ? elevationDeltaMeters : nil,
            effortsJSON: effortsJSON
        )
    }
}

// MARK: - GoalModel

/// Persisted user goal. At most one row should have isActive == true at any time.
///
/// Written by AppState.setGoal() when the user picks a target segment.
/// The previous active goal is deactivated (isActive = false) before inserting a new one.
/// Goals are never hard-deleted — the history is preserved for future reference.
///
/// Currently only "segment_pr" goals are supported, but goalType is stored
/// as a String to allow future expansion without a schema migration.
@Model
final class GoalModel {
    /// The user's goal in plain English — currently always the segment name.
    var rawDescription: String

    /// Optional Enzo-generated interpretation of the goal. Reserved for future use.
    var claudeInterpretation: String?

    /// Goal category. Currently always "segment_pr".
    var goalType: String

    /// Optional Strava segment ID. Not always populated — segment lookup is by name.
    var targetSegmentId: Int?

    /// Name of the target Strava segment. Primary key for goal matching in loadSegments().
    var targetSegmentName: String

    /// Optional target date. Shown in GoalSettingView countdown if set.
    var targetDate: Date?

    /// Optional aspirational target time in seconds. Reserved for future use.
    var targetValue: Double?

    /// Fitness label required to beat this PR (e.g. "Strong").
    /// Derived from fitnessValueAtPR on the segment at the time of goal creation.
    var requiredFitnessLabel: String

    /// Normalized fitness value (0.0–1.0) required to beat this PR.
    var requiredFitnessValue: Double

    /// True for the current active goal. Only one row should be active at a time.
    /// AppState.setGoal() deactivates all active goals before inserting a new one.
    var isActive: Bool

    /// Timestamp of goal creation. Not displayed; useful for debugging goal history.
    var createdAt: Date

    init(rawDescription: String, goalType: String, targetSegmentName: String,
         targetDate: Date?, requiredFitnessLabel: String, requiredFitnessValue: Double,
         isActive: Bool) {
        self.rawDescription = rawDescription
        self.claudeInterpretation = nil
        self.goalType = goalType
        self.targetSegmentId = nil
        self.targetSegmentName = targetSegmentName
        self.targetDate = targetDate
        self.targetValue = nil
        self.requiredFitnessLabel = requiredFitnessLabel
        self.requiredFitnessValue = requiredFitnessValue
        self.isActive = isActive
        self.createdAt = Date()
    }

    /// Converts to GoalRow so AthleteContext.build() can remain unchanged.
    /// GoalRow was originally the Supabase DTO; it's now just a plain struct bridge
    /// between the SwiftData model and the AthleteContext factory.
    func toGoalRow() -> GoalRow {
        var targetDateStr: String? = nil
        if let date = targetDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            targetDateStr = f.string(from: date)
        }
        return GoalRow(
            id: nil,
            userId: nil,
            rawDescription: rawDescription,
            claudeInterpretation: claudeInterpretation,
            goalType: goalType,
            targetSegmentId: targetSegmentId.map { Int64($0) },
            targetSegmentName: targetSegmentName,
            targetDate: targetDateStr,
            targetValue: targetValue,
            requiredFitnessLabel: requiredFitnessLabel,
            requiredFitnessValue: requiredFitnessValue,
            isActive: isActive
        )
    }
}

// MARK: - Fitness v2 Models
//
// These five models replace FitnessSnapshotModel and SegmentScoreModel as part of the
// Fitness Algorithm v2 overhaul (EnzoApp-y69). The old models remain temporarily until
// AppState and SyncService are updated to remove all references.
//
// Data flow:
//   ActivityModel → LTHR → TSS (stored on ActivityModel)
//   ActivityModel → DailyFitnessModel (CTL/ATL/TSB timeline, one row per calendar day)
//   StarredSegmentModel + SegmentEffortModel → OLS regression → SegmentFitnessModel
//   SegmentFitnessModel → PRPredictor → probability displayed in UI

/// One Strava activity. TSS is computed on ingest and stored — it does not change.
/// Only cycling sport types are stored (Ride, VirtualRide, GravelRide, MountainBikeRide, EBikeRide).
/// avgWatts is only populated when Strava's device_watts == true.
@Model
final class ActivityModel {
    @Attribute(.unique) var stravaId: Int
    var date: Date
    var movingTime: Int       // seconds
    var avgHeartRate: Double?
    var avgWatts: Double?     // nil unless device_watts == true
    var tss: Double           // computed on ingest; 0 if neither HR nor power available

    init(stravaId: Int, date: Date, movingTime: Int,
         avgHeartRate: Double?, avgWatts: Double?, tss: Double) {
        self.stravaId = stravaId
        self.date = date
        self.movingTime = movingTime
        self.avgHeartRate = avgHeartRate
        self.avgWatts = avgWatts
        self.tss = tss
    }
}

/// One row per calendar day from the oldest ActivityModel to today.
/// CTL (42-day EMA) = fitness. ATL (7-day EMA) = fatigue.
/// TSB = CTL_yesterday - ATL_yesterday, representing form going INTO the day.
/// Rest days are included (tss contribution = 0) so decay works correctly — never skip days.
@Model
final class DailyFitnessModel {
    @Attribute(.unique) var date: Date
    var ctl: Double
    var atl: Double
    var tsb: Double  // = CTL_yesterday - ATL_yesterday (pre-update readiness)

    init(date: Date, ctl: Double, atl: Double, tsb: Double) {
        self.date = date
        self.ctl = ctl
        self.atl = atl
        self.tsb = tsb
    }
}

/// A segment the athlete has starred on Strava.
/// Only starred segments appear in Enzo — star a segment in Strava to include it.
/// Refreshed on every sync; segments that are unstarred are removed.
@Model
final class StarredSegmentModel {
    @Attribute(.unique) var segmentId: Int
    var name: String
    var distance: Double  // meters
    var avgGrade: Double  // percent

    init(segmentId: Int, name: String, distance: Double, avgGrade: Double) {
        self.segmentId = segmentId
        self.name = name
        self.distance = distance
        self.avgGrade = avgGrade
    }
}

/// One effort by the athlete on a starred segment, fetched from /segments/{id}/all_efforts.
/// ctlOnDay and tsbOnDay are populated during the effort-fitness join (look up DailyFitnessModel
/// for effortDate - 1 day). They default to 0 until the join runs.
@Model
final class SegmentEffortModel {
    @Attribute(.unique) var stravaEffortId: Int
    var segmentId: Int
    var effortDate: Date
    var elapsedTime: Double  // seconds
    var ctlOnDay: Double     // populated by join; CTL from the day before this effort
    var tsbOnDay: Double     // populated by join; TSB from the day before this effort

    init(stravaEffortId: Int, segmentId: Int, effortDate: Date,
         elapsedTime: Double, ctlOnDay: Double = 0, tsbOnDay: Double = 0) {
        self.stravaEffortId = stravaEffortId
        self.segmentId = segmentId
        self.effortDate = effortDate
        self.elapsedTime = elapsedTime
        self.ctlOnDay = ctlOnDay
        self.tsbOnDay = tsbOnDay
    }
}

/// Per-segment OLS regression model: elapsed_time = β₀ + β₁·CTL + β₂·TSB + ε.
/// Fit via normal equations using simd_double3x3.
///
/// isValid = false when:
///   - nEfforts < 1 (no data)
///   - beta1 > 0 (wrong sign — higher fitness predicts slower time, indicates confounding)
///   - XᵀX matrix is singular (all efforts at identical CTL)
///
/// When isValid == false, only naiveFallback is shown in the UI.
/// ctlMin/Max and tsbMin/Max are used for extrapolation detection at display time.
@Model
final class SegmentFitnessModel {
    @Attribute(.unique) var segmentId: Int
    var beta0: Double
    var beta1: Double      // CTL coefficient; expected negative (fitter = faster = lower seconds)
    var beta2: Double      // TSB coefficient; expected negative (fresher = faster = lower seconds)
    var sigmaResid: Double // residual standard deviation; used for probability interval
    var prTime: Double     // seconds — all-time best elapsed_time across all stored efforts
    var prCTL: Double      // CTL on the day the PR was set (for naive fallback string)
    var nEfforts: Int
    var ctlMin: Double     // training range lower bound (extrapolation guard)
    var ctlMax: Double
    var tsbMin: Double
    var tsbMax: Double
    var isValid: Bool
    var fittedAt: Date

    init(segmentId: Int, beta0: Double, beta1: Double, beta2: Double,
         sigmaResid: Double, prTime: Double, prCTL: Double, nEfforts: Int,
         ctlMin: Double, ctlMax: Double, tsbMin: Double, tsbMax: Double,
         isValid: Bool, fittedAt: Date) {
        self.segmentId = segmentId
        self.beta0 = beta0
        self.beta1 = beta1
        self.beta2 = beta2
        self.sigmaResid = sigmaResid
        self.prTime = prTime
        self.prCTL = prCTL
        self.nEfforts = nEfforts
        self.ctlMin = ctlMin
        self.ctlMax = ctlMax
        self.tsbMin = tsbMin
        self.tsbMax = tsbMax
        self.isValid = isValid
        self.fittedAt = fittedAt
    }
}

// MARK: - Shared ModelContainer

extension ModelContainer {
    /// The single shared SwiftData container for the entire app.
    ///
    /// Created lazily on first access. Stored as a `let` static to ensure it's
    /// only ever initialized once. `fatalError` on failure is intentional —
    /// a schema corruption at this point is unrecoverable and should surface
    /// immediately rather than silently losing data.
    ///
    /// Injected into the SwiftUI environment in EnzoAppApp via `.modelContainer(ModelContainer.enzo)`.
    /// AppState accesses it directly via `ModelContainer.enzo.mainContext` in its `init()`.
    ///
    /// To enable iCloud sync in the future, change ModelConfiguration to:
    ///   ModelConfiguration(cloudKitContainerIdentifier: "iCloud.com.enzo.app")
    static let enzo: ModelContainer = {
        let schema = Schema([
            // Legacy models — removed once AppState/SyncService cutover is complete
            FitnessSnapshotModel.self,
            SegmentScoreModel.self,
            // Fitness v2 models (EnzoApp-y69)
            ActivityModel.self,
            DailyFitnessModel.self,
            StarredSegmentModel.self,
            SegmentEffortModel.self,
            SegmentFitnessModel.self,
            // Unchanged
            GoalModel.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()
}
