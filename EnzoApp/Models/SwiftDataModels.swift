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

// MARK: - Fitness v2 Models
//
// Introduced in Fitness Algorithm v2 overhaul (EnzoApp-y69).
// Replaces the legacy FitnessSnapshotModel + SegmentScoreModel (removed in EnzoApp-1tl).
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

/// A segment the athlete has either starred on Strava or ridden in the last 90 days.
/// Starred segments are refreshed on every sync; non-starred segments that fall outside
/// the 90-day window are removed on the next sync. `isStarred` distinguishes the source.
@Model
final class StarredSegmentModel {
    @Attribute(.unique) var segmentId: Int
    var name: String
    var distance: Double  // meters
    var avgGrade: Double  // percent
    /// True when the athlete has starred this segment on Strava.
    /// False for recency-only segments (ridden within 90 days but not starred).
    var isStarred: Bool

    init(segmentId: Int, name: String, distance: Double, avgGrade: Double, isStarred: Bool = true) {
        self.segmentId = segmentId
        self.name = name
        self.distance = distance
        self.avgGrade = avgGrade
        self.isStarred = isStarred
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
            // Fitness v2 models (EnzoApp-y69)
            ActivityModel.self,
            DailyFitnessModel.self,
            StarredSegmentModel.self,
            SegmentEffortModel.self,
            SegmentFitnessModel.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()
}
