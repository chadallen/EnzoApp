import Foundation
import Observation
import AuthenticationServices
import SwiftData

// MARK: - Persistence overview
//
// AppState is the single source of truth for all in-memory app state.
// It reads from and writes to three persistence layers:
//
//   SwiftData (ModelContext)
//     FitnessSnapshotModel  — monthly fitness history, written by Phase 1 sync
//     SegmentScoreModel     — segment PRs + strike scores, written by Phase 2 sync
//     GoalModel             — active/historical goals, written by setGoal()
//
//   Keychain
//     Strava OAuth tokens (access, refresh, expiry) and athlete ID
//
//   UserDefaults
//     Onboarding flag, last sync timestamps, athlete display name, last activity date
//
// Raw Strava activity data is NEVER persisted — only derived outputs reach storage.

@Observable
@MainActor
class AppState {
    // MARK: - Published state

    // In-memory context built from SwiftData on each launch.
    // Preview values are shown until loadContext() completes.
    var athleteContext: AthleteContext = .preview
    var fitnessSnapshots: [FitnessSnapshot] = FitnessSnapshot.previewSnapshots
    var segments: [SegmentScore] = SegmentScore.previewSegments

    // Streaming state for the in-progress Enzo response
    var isStreaming = false
    var streamingText = ""

    // Auth state — populated after successful OAuth flow or Keychain restore on launch
    var isAuthenticated: Bool = false
    var stravaAthleteId: Int64? = nil

    // Onboarding state — persisted to UserDefaults
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    // True while loadContext() is running to resolve whether onboarding is needed.
    // Prevents the gate from flashing GoalSettingView for existing users on first launch.
    var isResolvingOnboarding: Bool = false
    // True from startOnboardingSync() until SyncProgressView's onComplete fires.
    // Distinct from isSyncing so manual syncs (SettingsSheet) don't re-trigger onboarding screen.
    var isOnboardingSyncing: Bool = false

    // Sync state
    var isSyncing: Bool = false
    var isSyncingPhase2: Bool = false
    // True once loadSegments() has written at least one real row from the local store.
    // False on fresh install while segments holds preview data.
    var hasRealSegmentData: Bool = false
    // Total activities fetched in Phase 1 — displayed in SyncProgressView as "N rides and counting".
    var syncedActivityCount: Int = 0
    // Set on sync failure, cleared on sync start. Displayed as an inline amber message in ArcView.
    var syncErrorMessage: String? = nil
    // Set when a sync completes successfully. Persisted to UserDefaults.
    var lastSyncedAt: Date? = UserDefaults.standard.object(forKey: "lastSyncedAt") as? Date

    // MARK: - Services

    private let claudeService: ClaudeService
    private let stravaService: StravaService
    private let syncService: SyncService

    // SwiftData context for all local persistence reads/writes.
    // Uses mainContext (main actor) because AppState itself is @MainActor.
    // `let` (not `lazy var`) is required — lazy var is incompatible with @Observable.
    let modelContext: ModelContext

    // MARK: - Init

    init() {
        let strava = StravaService()
        claudeService = ClaudeService()
        stravaService = strava
        syncService   = SyncService(stravaService: strava)
        // Pull the main context from the shared singleton container.
        // All SwiftData reads/writes in AppState go through this context.
        modelContext  = ModelContainer.enzo.mainContext

        // Restore auth state from Keychain on launch.
        // stravaAthleteId is the only identity token needed — there is no
        // supabaseUserId anymore. If the Strava token is absent, treat as unauthenticated.
        if let idString = KeychainHelper.load(for: KeychainHelper.stravaAthleteId),
           let id = Int64(idString) {
            isAuthenticated = true
            stravaAthleteId = id
        }

        // If authenticated but onboarding not yet confirmed, flag for resolution
        // so the gate waits for loadContext() before deciding which screen to show.
        if isAuthenticated && !hasCompletedOnboarding {
            isResolvingOnboarding = true
        }
    }

    // MARK: - Context loading

    /// Fetches fitness snapshots, user profile, and active goal from local SwiftData store,
    /// then builds a live AthleteContext. No-ops gracefully if not authenticated.
    func loadContext() async {
        guard isAuthenticated else {
            isResolvingOnboarding = false
            return
        }

        do {
            let snapshotModels = try modelContext.fetch(
                FetchDescriptor<FitnessSnapshotModel>(sortBy: [SortDescriptor(\.month)])
            )
            let snapshots = snapshotModels.map { $0.toSnapshot() }

            let goalModels = try modelContext.fetch(
                FetchDescriptor<GoalModel>(predicate: #Predicate { $0.isActive })
            )
            let activeGoalRow = goalModels.first?.toGoalRow()

            let displayName = UserDefaults.standard.string(forKey: "athleteDisplayName") ?? "Athlete"
            let lastActivityDate = UserDefaults.standard.object(forKey: "lastActivityDate") as? Date

            let context = AthleteContext.build(
                name: displayName,
                snapshots: snapshots,
                goalRow: activeGoalRow,
                lastActivityDate: lastActivityDate
            )

            fitnessSnapshots = snapshots
            athleteContext = context

            NSLog("[Context] Loaded: \(snapshots.count) snapshots, fitness=\(context.currentFitnessLabel), trend=\(context.trendDirection)")

            // Auto-complete onboarding for existing users who already have a goal.
            if activeGoalRow != nil && !hasCompletedOnboarding {
                hasCompletedOnboarding = true
                NSLog("[Onboarding] Existing user — marking onboarding complete")
            }

            // Load real segment scores from local store (no-op if store is empty).
            await loadSegments(goalSegmentName: activeGoalRow?.targetSegmentName)
        } catch {
            NSLog("[Context] loadContext error: \(error)")
        }
        isResolvingOnboarding = false
    }

    /// Fetches segment scores from the local SwiftData store and populates appState.segments.
    /// Marks the goal segment if a goal is active.
    func loadSegments(goalSegmentName: String? = nil) async {
        guard isAuthenticated else { return }
        do {
            let models = try modelContext.fetch(FetchDescriptor<SegmentScoreModel>())
            guard !models.isEmpty else {
                NSLog("[Segments] No segment rows in local store yet — keeping preview data")
                return
            }
            let loaded = models.map { model -> SegmentScore in
                var score = model.toSegmentScore()
                score.isGoalSegment = score.name == goalSegmentName
                return score
            }
            segments = loaded.sorted { $0.strikeScore > $1.strikeScore }
            hasRealSegmentData = true
            NSLog("[Segments] Loaded \(loaded.count) segments from local store")
        } catch {
            NSLog("[Segments] loadSegments error: \(error)")
        }
    }

    // MARK: - Goal setting

    func setGoal(_ segment: SegmentScore, targetDate: Date?) {
        let daysRemaining: Int? = targetDate.map { date in
            max(0, Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0)
        }
        let weeksRemaining: Int? = daysRemaining.map { $0 / 7 }

        let requiredValue = segment.fitnessValueAtPR
        let requiredLabel = SegmentScorer.requiredFitnessLabel(fitnessValueAtPR: requiredValue)
        let newGoal = GoalContext(
            segmentName: segment.name,
            requiredFitnessLabel: requiredLabel,
            requiredFitnessValue: requiredValue,
            targetDate: targetDate,
            weeksRemaining: weeksRemaining,
            daysRemaining: daysRemaining
        )

        athleteContext = AthleteContext(
            name: athleteContext.name,
            yearsActive: athleteContext.yearsActive,
            totalActivities: athleteContext.totalActivities,
            currentFitnessLabel: athleteContext.currentFitnessLabel,
            currentFitnessValue: athleteContext.currentFitnessValue,
            trendDirection: athleteContext.trendDirection,
            peakFitnessLabel: athleteContext.peakFitnessLabel,
            peakFitnessMonth: athleteContext.peakFitnessMonth,
            daysSinceLastRide: athleteContext.daysSinceLastRide,
            goal: newGoal
        )

        segments = segments.map { seg in
            var updated = seg
            updated.isGoalSegment = seg.name == segment.name
            return updated
        }

        // Deactivate all existing active goals, then insert the new one.
        do {
            let activeGoals = try modelContext.fetch(
                FetchDescriptor<GoalModel>(predicate: #Predicate { $0.isActive })
            )
            activeGoals.forEach { $0.isActive = false }
            let goal = GoalModel(
                rawDescription: segment.name,
                goalType: "segment_pr",
                targetSegmentName: segment.name,
                targetDate: targetDate,
                requiredFitnessLabel: requiredLabel,
                requiredFitnessValue: requiredValue,
                isActive: true
            )
            modelContext.insert(goal)
            try modelContext.save()
            NSLog("[Goal] Saved goal '\(segment.name)' to local store")
        } catch {
            NSLog("[Goal] Failed to save goal: \(error)")
        }
    }

    func goalReactionStream(for segment: SegmentScore) async -> AsyncStream<String> {
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: athleteContext)
        let context = athleteContext.contextPayload(snapshots: fitnessSnapshots, segments: segments)
        return await claudeService.stream(userMessage: prompt, context: context)
    }

    /// Pure function — builds the Enzo prompt for reacting to a newly selected goal segment.
    /// Extracted for testability.
    static func goalReactionPrompt(segment: SegmentScore, athleteContext: AthleteContext) -> String {
        let fitnessAtPRLabel = AthleteContext.fitnessLabel(for: segment.fitnessValueAtPR)
        return "I want to set \(segment.name) as my PR goal. " +
               "I set that PR (\(segment.prFormatted)) on \(segment.prDate) " +
               "when I was at \(fitnessAtPRLabel) fitness. " +
               "My current fitness is \(athleteContext.currentFitnessLabel), trending \(athleteContext.trendDirection). " +
               "React to this goal choice — be honest about where I stand and whether a target date makes sense."
    }

    // MARK: - Authentication

    func disconnect() {
        KeychainHelper.delete(for: KeychainHelper.stravaAccessToken)
        KeychainHelper.delete(for: KeychainHelper.stravaRefreshToken)
        KeychainHelper.delete(for: KeychainHelper.stravaTokenExpiry)
        KeychainHelper.delete(for: KeychainHelper.stravaAthleteId)
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "athleteDisplayName")
        UserDefaults.standard.removeObject(forKey: "lastActivityDate")
        UserDefaults.standard.removeObject(forKey: SyncService.lastPhase2SyncKey)
        UserDefaults.standard.removeObject(forKey: "lastSyncedAt")
        lastSyncedAt = nil

        // Wipe local SwiftData store so next auth gets a clean slate.
        do {
            try modelContext.delete(model: FitnessSnapshotModel.self)
            try modelContext.delete(model: SegmentScoreModel.self)
            try modelContext.delete(model: GoalModel.self)
            try modelContext.save()
        } catch {
            NSLog("[Auth] Failed to wipe local store on disconnect: \(error)")
        }

        isAuthenticated = false
        hasCompletedOnboarding = false
        isResolvingOnboarding = false
        stravaAthleteId = nil
        athleteContext = .preview
        fitnessSnapshots = FitnessSnapshot.previewSnapshots
        segments = SegmentScore.previewSegments
        NSLog("[Auth] Disconnected — state reset to preview")
    }

    /// Kicks off the first-time onboarding sync. Sets isOnboardingSyncing = true so RootView
    /// routes to SyncProgressView. Does not clear isOnboardingSyncing — SyncProgressView does
    /// that via its onComplete handler after the completion animation finishes.
    func startOnboardingSync() async {
        isOnboardingSyncing = true
        await syncPhase1()
    }

    func authenticate(contextProvider: ASWebAuthenticationPresentationContextProviding) async throws {
        let athlete = try await stravaService.authenticate(presentingFrom: contextProvider)
        isAuthenticated = true
        stravaAthleteId = athlete.id
        UserDefaults.standard.set(athlete.displayName, forKey: "athleteDisplayName")
    }

    // MARK: - Sync

    func syncPhase1() async {
        NSLog("[Sync] starting Phase 1")
        isSyncing = true
        syncErrorMessage = nil
        do {
            let (count, snapshotRows, lastActivityDate) = try await syncService.syncPhase1()

            for row in snapshotRows {
                upsertSnapshot(row)
            }
            if let date = lastActivityDate {
                UserDefaults.standard.set(date, forKey: "lastActivityDate")
            }

            // Reload context from newly written snapshots.
            await loadContext()

            syncedActivityCount = count
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: "lastSyncedAt")
            NSLog("[Sync] Phase 1 complete — \(count) activities fetched, \(snapshotRows.count) snapshots written")
        } catch let error as StravaError {
            NSLog("[Sync] Phase 1 Strava error: \(error)")
            switch error {
            case .notAuthenticated, .tokenExchangeFailed:
                syncErrorMessage = "Strava needs you to reconnect — takes 10 seconds."
            case .httpError(let code, _) where code == 401:
                syncErrorMessage = "Strava needs you to reconnect — takes 10 seconds."
            default:
                syncErrorMessage = "Sync didn't complete — tap to try again."
            }
        } catch {
            NSLog("[Sync] Phase 1 error: \(error)")
            syncErrorMessage = "Sync didn't complete — tap to try again."
        }
        isSyncing = false

        // Phase 2 runs automatically after Phase 1 completes.
        await syncPhase2()
    }

    /// Clears sync history and wipes the local SwiftData store so the next sync re-fetches from scratch.
    func resetSyncHistory() {
        UserDefaults.standard.removeObject(forKey: SyncService.lastPhase2SyncKey)
        do {
            try modelContext.delete(model: FitnessSnapshotModel.self)
            try modelContext.delete(model: SegmentScoreModel.self)
            try modelContext.save()
        } catch {
            NSLog("[Sync] Failed to wipe local store on reset: \(error)")
        }
        NSLog("[Sync] History reset — local store wiped, next sync will re-fetch from scratch")
    }

    func syncPhase2() async {
        guard isAuthenticated else {
            NSLog("[Sync] syncPhase2: not authenticated — aborting")
            return
        }

        NSLog("[Sync] starting Phase 2")
        isSyncingPhase2 = true
        do {
            let segmentRows = try await syncService.syncPhase2(fitnessSnapshots: fitnessSnapshots)
            for row in segmentRows {
                upsertSegmentScore(row)
            }
            NSLog("[Sync] Phase 2 complete — \(segmentRows.count) segment rows written")
            await loadSegments(goalSegmentName: athleteContext.goal.segmentName)
        } catch {
            NSLog("[Sync] Phase 2 error: \(error)")
        }
        isSyncingPhase2 = false
    }

    // MARK: - Private: SwiftData write helpers

    /// Insert-or-update for a fitness snapshot row, keyed on month Date.
    /// SwiftData doesn't have native upsert semantics, so we fetch first.
    /// The @Attribute(.unique) on FitnessSnapshotModel.month prevents duplicates
    /// but doesn't auto-merge — we handle that here manually.
    private func upsertSnapshot(_ row: FitnessSnapshotRow) {
        let monthDate = row.monthDate
        var descriptor = FetchDescriptor<FitnessSnapshotModel>(
            predicate: #Predicate { $0.month == monthDate }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // Update all mutable fields — month (the unique key) stays unchanged.
            existing.fitnessValue    = row.fitnessValue
            existing.fitnessLabel   = row.fitnessLabel
            existing.trendDirection = row.trendDirection
            existing.hoursRidden    = row.hoursRidden ?? 0
            existing.activityCount  = row.activityCount ?? 0
            existing.avgEfficiency  = row.avgEfficiency ?? 0
        } else {
            modelContext.insert(FitnessSnapshotModel(from: row))
        }
        try? modelContext.save()
    }

    /// Insert-or-update for a segment score row, keyed on Strava segment ID.
    /// Same fetch-first pattern as upsertSnapshot — keyed on stravaSegmentId.
    private func upsertSegmentScore(_ row: SegmentScoreRow) {
        let segId = Int(row.stravaSegmentId)
        var descriptor = FetchDescriptor<SegmentScoreModel>(
            predicate: #Predicate { $0.stravaSegmentId == segId }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // Update all mutable fields — stravaSegmentId (the unique key) stays unchanged.
            existing.segmentName          = row.segmentName ?? ""
            existing.prSeconds            = row.prSeconds ?? 0
            existing.prAchievedAt         = row.prAchievedAt ?? ""
            existing.fitnessValueAtPr     = row.fitnessValueAtPr ?? 0
            existing.currentFitnessValue  = row.currentFitnessValue ?? 0
            existing.trendDirection       = row.trendDirection ?? "flat"
            existing.lastEffortSeconds    = row.lastEffortSeconds ?? 0
            existing.lastEffortDate       = row.lastEffortDate ?? ""
            existing.strikeScore          = row.strikeScore ?? 0
            existing.strikeLabel          = row.strikeLabel ?? ""
            existing.distanceMeters       = row.distanceMeters ?? 0
            existing.elevationDeltaMeters = row.elevationDeltaMeters ?? 0
        } else {
            modelContext.insert(SegmentScoreModel(from: row))
        }
        try? modelContext.save()
    }

    // MARK: - Messaging

    func sendMessage(_ text: String) async {
        isStreaming = true
        streamingText = ""
        let context = athleteContext.contextPayload(snapshots: fitnessSnapshots, segments: segments)
        let tokenStream = await claudeService.stream(userMessage: text, context: context)
        for await token in tokenStream {
            streamingText += token
        }
        streamingText = ""
        isStreaming = false
    }

    /// Streams a segment-scoped response from Enzo. Context includes both the athlete payload
    /// and segment-specific details (name, PR, strike score, last effort).
    /// history: prior ArcMessages in this conversation (oldest first, empty on first message).
    func sendSegmentMessage(_ text: String, segment: SegmentScore, history: [ArcMessage]) async -> AsyncStream<String> {
        let athletePayload = athleteContext.contextPayload(snapshots: fitnessSnapshots, segments: segments)
        let lastEffortMins = segment.lastEffortSeconds / 60
        let lastEffortSecs = segment.lastEffortSeconds % 60
        let lastEffortFormatted = String(format: "%d:%02d", lastEffortMins, lastEffortSecs)
        let segmentPayload = """
            Focused segment: \(segment.name)
            Current PR: \(segment.prFormatted) (set \(segment.prDate))
            Strike score: \(String(format: "%.0f", segment.strikeScore * 100)) — \(segment.strikeLabel)
            Last effort: \(lastEffortFormatted)
            """
        let context = "\(athletePayload)\n\n\(segmentPayload)"
        return await claudeService.stream(userMessage: text, context: context, history: history)
    }

    /// Pure function — builds the opening prompt Enzo receives when the user taps "Ask Enzo"
    /// on a segment. Extracted for testability and playground use.
    static func segmentAssessmentPrompt(segment: SegmentScore, athleteContext: AthleteContext) -> String {
        "Give me a quick read on \(segment.name). " +
        "My fitness is \(athleteContext.currentFitnessLabel), trending \(athleteContext.trendDirection). " +
        "The readiness score is \(segment.strikeLabel). " +
        "Is now a good window to go after this, and what would move the needle if not?"
    }
}
