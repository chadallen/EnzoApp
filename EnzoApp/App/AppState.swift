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
//     ActivityModel         — per-activity TSS (v2)
//     DailyFitnessModel     — CTL/ATL/TSB timeline (v2)
//     StarredSegmentModel   — athlete's starred segments (v2)
//     SegmentEffortModel    — per-effort data for starred segments (v2)
//     SegmentFitnessModel   — OLS regression model per segment (v2)
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
    // True once loadSegments() has written at least one real row from the local store.
    // False on fresh install while segments holds preview data.
    var hasRealSegmentData: Bool = false
    // Total activities fetched — displayed in SyncProgressView as "N rides and counting".
    var syncedActivityCount: Int = 0
    // Set on sync failure, cleared on sync start. Displayed as an inline amber message in ArcView.
    var syncErrorMessage: String? = nil
    // Set when a sync completes successfully. Persisted to UserDefaults.
    var lastSyncedAt: Date? = UserDefaults.standard.object(forKey: "lastSyncedAt") as? Date
    // Progress message shown during syncV2() steps.
    var syncProgressMessage: String = ""

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
            let goalModels = try modelContext.fetch(
                FetchDescriptor<GoalModel>(predicate: #Predicate { $0.isActive })
            )
            let activeGoalRow = goalModels.first?.toGoalRow()

            let displayName = UserDefaults.standard.string(forKey: "athleteDisplayName") ?? "Athlete"
            let lastActivityDate = UserDefaults.standard.object(forKey: "lastActivityDate") as? Date

            let context = AthleteContext.build(
                name: displayName,
                snapshots: [],
                goalRow: activeGoalRow,
                lastActivityDate: lastActivityDate
            )

            athleteContext = context

            NSLog("[Context] Loaded: fitness=\(context.currentFitnessLabel), trend=\(context.trendDirection)")

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
    ///
    /// Uses the v2 path (StarredSegmentModel + SegmentFitnessModel) when data is available,
    /// calling updateSegmentsFromV2Models() so prProbability is always populated after a restart.
    /// If no v2 data exists yet, keeps preview data until first sync completes.
    func loadSegments(goalSegmentName: String? = nil) async {
        guard isAuthenticated else { return }
        do {
            // V2 path: use StarredSegmentModel + SegmentFitnessModel when available.
            // This ensures prProbability is populated even after a restart (not just during sync).
            let starredSegments = (try? modelContext.fetch(FetchDescriptor<StarredSegmentModel>())) ?? []
            let fitnessModels   = (try? modelContext.fetch(FetchDescriptor<SegmentFitnessModel>())) ?? []
            // DEBUG an6.1 — remove: trace v2 model counts on load
            NSLog("[DEBUG an6.1] loadSegments: starredSegments=\(starredSegments.count) fitnessModels=\(fitnessModels.count)")

            if !starredSegments.isEmpty && !fitnessModels.isEmpty {
                // V2 data is available — reconstruct prProbability from stored models.
                let latestDailyFitness = try? modelContext.fetch(
                    FetchDescriptor<DailyFitnessModel>(sortBy: [SortDescriptor(\.date, order: .reverse)])
                ).first
                // DEBUG an6.1 — remove: trace today's fitness on restart load
                NSLog("[DEBUG an6.1] loadSegments v2: todayFitness date=\(String(describing: latestDailyFitness?.date)) ctl=\(latestDailyFitness?.ctl ?? 0) tsb=\(latestDailyFitness?.tsb ?? 0)")
                await updateSegmentsFromV2Models(
                    starredSegments: starredSegments,
                    todayFitness: latestDailyFitness
                )
                // Mark goal segment after updateSegmentsFromV2Models has populated segments.
                if let goalName = goalSegmentName {
                    segments = segments.map { seg in
                        var updated = seg
                        updated.isGoalSegment = seg.name == goalName
                        return updated
                    }
                }
                NSLog("[Segments] Loaded \(starredSegments.count) segments from v2 store with prProbability")
                return
            }

            // No v2 data yet — keep preview data until first sync completes.
            NSLog("[Segments] No segment rows in local store yet — keeping preview data")
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
        // One tier below PR fitness — you don't need to exactly match your peak to challenge a PR.
        let prFitnessLabel = AthleteContext.fitnessLabel(for: requiredValue)
        let requiredLabel: String
        switch prFitnessLabel {
        case "Epic":      requiredLabel = "Strong"
        case "Strong":    requiredLabel = "Building"
        case "Building":  requiredLabel = "Baseline"
        default:          requiredLabel = "Recovering"
        }
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
        UserDefaults.standard.removeObject(forKey: "lastV2SyncDate")
        UserDefaults.standard.removeObject(forKey: "athleteLTHR")
        UserDefaults.standard.removeObject(forKey: "athleteFTP")
        UserDefaults.standard.removeObject(forKey: "lastSyncedAt")
        lastSyncedAt = nil

        // Wipe local SwiftData store so next auth gets a clean slate.
        do {
            try modelContext.delete(model: ActivityModel.self)
            try modelContext.delete(model: DailyFitnessModel.self)
            try modelContext.delete(model: StarredSegmentModel.self)
            try modelContext.delete(model: SegmentEffortModel.self)
            try modelContext.delete(model: SegmentFitnessModel.self)
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
        await syncV2()
    }

    func authenticate(contextProvider: ASWebAuthenticationPresentationContextProviding) async throws {
        let athlete = try await stravaService.authenticate(presentingFrom: contextProvider)
        isAuthenticated = true
        stravaAthleteId = athlete.id
        UserDefaults.standard.set(athlete.displayName, forKey: "athleteDisplayName")
    }

    // MARK: - Sync v2

    /// Full v2 sync pipeline:
    ///   1. Fetch & store activities → compute LTHR → update TSS
    ///   2. Build CTL/ATL/TSB daily timeline
    ///   3. Fetch & sync starred segments + 90-day recency segments (unioned, de-duped)
    ///   4. Fetch & store segment efforts
    ///   5. Join efforts to fitness values
    ///   6. Fit OLS regression per segment
    ///   7. Persist last sync date and LTHR
    ///   8. Update in-memory segments for UI
    func syncV2() async {
        guard isAuthenticated else {
            NSLog("[SyncV2] not authenticated — aborting")
            return
        }

        NSLog("[SyncV2] starting")
        isSyncing = true
        syncErrorMessage = nil

        do {
            try await stravaService.refreshTokenIfNeeded()
            guard let accessToken = KeychainHelper.load(for: KeychainHelper.stravaAccessToken) else {
                throw SyncError.notAuthenticated
            }
            guard let athleteIdStr = KeychainHelper.load(for: KeychainHelper.stravaAthleteId),
                  let athleteId = Int64(athleteIdStr) else {
                throw SyncError.notAuthenticated
            }

            // Step 1a — Fetch activities from Strava
            setSyncProgress("Fetching your rides...")
            let fetchedActivities = try await syncService.fetchActivitiesV2(accessToken: accessToken)
            NSLog("[SyncV2] Fetched \(fetchedActivities.count) activities")

            // Step 1b — Store activities with tss=0 initially (we need LTHR first)
            setSyncProgress("Storing activities...")
            for activity in fetchedActivities {
                upsertActivityModel(activity, tss: 0)
            }
            syncedActivityCount = fetchedActivities.count

            // Step 1c — Estimate LTHR from stored activities
            let allStoredActivities = (try? modelContext.fetch(FetchDescriptor<ActivityModel>())) ?? []
            let lthrInputs = allStoredActivities.map {
                LTHREstimator.ActivityInput(movingTime: $0.movingTime, avgHeartRate: $0.avgHeartRate)
            }
            let lthr = LTHREstimator.estimate(from: lthrInputs)
            let ftp = UserDefaults.standard.object(forKey: "athleteFTP") as? Double
            NSLog("[SyncV2] LTHR=\(lthr.map { String($0) } ?? "nil"), FTP=\(ftp.map { String($0) } ?? "nil")")

            // Step 1d — Recompute TSS for all stored activities using LTHR
            setSyncProgress("Computing your fitness...")
            for model in allStoredActivities {
                let tss = TSSCalculator.compute(
                    movingTime: model.movingTime,
                    avgHeartRate: model.avgHeartRate,
                    avgWatts: model.avgWatts,
                    lthr: lthr,
                    ftp: ftp
                ) ?? 0
                model.tss = tss
            }
            try? modelContext.save()

            // Step 2 — Build fitness timeline (CTL/ATL/TSB)
            setSyncProgress("Building fitness timeline...")
            let lastV2SyncDate = UserDefaults.standard.object(forKey: "lastV2SyncDate") as? Date
            let isIncremental = lastV2SyncDate != nil

            let startCTL: Double
            let startATL: Double
            let startDate: Date

            if isIncremental,
               let lastStored = try? modelContext.fetch(
                   FetchDescriptor<DailyFitnessModel>(sortBy: [SortDescriptor(\.date, order: .reverse)])
               ).first {
                // Incremental: start from the day after the last stored row
                startCTL = lastStored.ctl
                startATL = lastStored.atl
                startDate = Calendar.utc.date(byAdding: .day, value: 1, to: lastStored.date) ?? Date()
            } else {
                // Full rebuild
                startCTL = 0
                startATL = 0
                startDate = DailyFitnessBuilder.oldestActivityDate(from: allStoredActivities) ?? Date()
            }

            let dailyRows = DailyFitnessBuilder.build(
                from: allStoredActivities,
                startCTL: startCTL,
                startATL: startATL,
                startDate: startDate,
                endDate: Date()
            )
            for row in dailyRows {
                upsertDailyFitness(row)
            }
            NSLog("[SyncV2] Built \(dailyRows.count) daily fitness rows")

            // Step 3 — Fetch starred segments + 90-day recency segments (unioned, de-duped)
            setSyncProgress("Fetching your segments...")
            let starredFromStrava = try await syncService.fetchStarredSegmentsV2(accessToken: accessToken)
            let starredIds = Set(starredFromStrava.map { $0.id })

            // Upsert current starred segments (sets isStarred = true)
            for seg in starredFromStrava {
                upsertStarredSegment(seg)
            }

            // Step 3b — Collect segment IDs from recent (90-day) activity efforts.
            // These come from the activity summary responses already fetched in Step 1a.
            // No extra activity API calls — segment efforts are included in the summary.
            let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            let recentSegmentIds = SyncService.recentSegmentIds(
                from: fetchedActivities,
                cutoff: ninetyDaysAgo
            )
            // De-duplicate: only fetch details for recency segments not already starred.
            let newRecencyIds = recentSegmentIds.subtracting(starredIds)
            NSLog("[SyncV2] \(recentSegmentIds.count) unique segment IDs from 90-day activities, \(newRecencyIds.count) not already starred")

            setSyncProgress("Fetching recent segment details...")
            // Cap at 50 recency segments per sync: each fetches ~1 detail + ~N effort pages.
            // Budget: 50 detail calls + effort calls in Step 4 must stay within 200 req/15 min.
            for segId in newRecencyIds.prefix(50) {
                do {
                    let detail = try await syncService.fetchSegmentDetailV2(
                        segmentId: segId,
                        accessToken: accessToken
                    )
                    upsertRecencySegment(detail)
                } catch SyncError.rateLimited {
                    NSLog("[SyncV2] Rate limited fetching recency segment \(segId) — stopping early")
                    break
                } catch {
                    // Non-fatal: skip segments that fail (deleted, private, etc.)
                    NSLog("[SyncV2] Skipping recency segment \(segId): \(error)")
                }
            }

            // Remove segments that are neither starred nor in the 90-day recency set.
            let keepIds = starredIds.union(recentSegmentIds)
            let existingModels = (try? modelContext.fetch(FetchDescriptor<StarredSegmentModel>())) ?? []
            for model in existingModels where !keepIds.contains(model.segmentId) {
                modelContext.delete(model)
            }
            try? modelContext.save()
            let totalSegmentCount = (try? modelContext.fetch(FetchDescriptor<StarredSegmentModel>()))?.count ?? 0
            NSLog("[SyncV2] \(starredFromStrava.count) starred + \(newRecencyIds.count) recency-only = \(totalSegmentCount) total segments")

            // Step 4 — Fetch segment efforts for each segment
            setSyncProgress("Analyzing segments...")
            let currentStarred = (try? modelContext.fetch(FetchDescriptor<StarredSegmentModel>())) ?? []
            for starred in currentStarred {
                do {
                    let efforts = try await syncService.fetchSegmentEffortsV2(
                        segmentId: starred.segmentId,
                        athleteId: athleteId,
                        accessToken: accessToken
                    )
                    for effort in efforts {
                        upsertSegmentEffort(effort, segmentId: starred.segmentId)
                    }
                } catch SyncError.rateLimited {
                    NSLog("[SyncV2] Rate limited fetching efforts for segment \(starred.segmentId) — stopping early")
                    break
                } catch {
                    // Non-fatal: skip segments that fail (deleted, private, etc.)
                    NSLog("[SyncV2] Skipping segment efforts for \(starred.segmentId): \(error)")
                }
            }
            NSLog("[SyncV2] Segment efforts stored")

            // Step 5 — Join efforts to fitness values
            setSyncProgress("Joining efforts to fitness...")
            let allDailyFitness = (try? modelContext.fetch(FetchDescriptor<DailyFitnessModel>())) ?? []
            let fitnessIndex = EffortFitnessJoiner.buildIndex(from: allDailyFitness)
            let allEfforts = (try? modelContext.fetch(FetchDescriptor<SegmentEffortModel>())) ?? []
            let joinResults = EffortFitnessJoiner.join(efforts: allEfforts, fitnessIndex: fitnessIndex)
            let joinById = Dictionary(joinResults.map { ($0.effortId, $0) },
                                      uniquingKeysWith: { first, _ in first })
            for effort in allEfforts {
                if let r = joinById[effort.stravaEffortId] {
                    effort.ctlOnDay = r.ctlOnDay
                    effort.tsbOnDay = r.tsbOnDay
                }
            }
            try? modelContext.save()
            // DEBUG an6.1 — remove: trace effort-fitness join quality
            let joinedWithFitness = allEfforts.filter { $0.ctlOnDay > 0 }.count
            NSLog("[DEBUG an6.1] Effort-fitness join: \(joinedWithFitness)/\(allEfforts.count) efforts have non-zero CTL. dailyFitnessRows=\(allDailyFitness.count)")

            // Step 6 — Fit regression per segment
            setSyncProgress("Fitting performance models...")
            let latestDailyFitness = (try? modelContext.fetch(
                FetchDescriptor<DailyFitnessModel>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            ).first)
            // DEBUG an6.1 — remove: trace today's CTL/TSB used for probability
            NSLog("[DEBUG an6.1] Today's fitness: date=\(String(describing: latestDailyFitness?.date)) ctl=\(latestDailyFitness?.ctl ?? 0) tsb=\(latestDailyFitness?.tsb ?? 0)")

            for starred in currentStarred {
                let segId = starred.segmentId
                var descriptor = FetchDescriptor<SegmentEffortModel>(
                    predicate: #Predicate { $0.segmentId == segId }
                )
                descriptor.sortBy = [SortDescriptor(\.effortDate)]
                let segEfforts = (try? modelContext.fetch(descriptor)) ?? []

                let points = segEfforts.map {
                    SegmentOLSSolver.EffortPoint(
                        elapsedTime: $0.elapsedTime,
                        ctlOnDay: $0.ctlOnDay,
                        tsbOnDay: $0.tsbOnDay
                    )
                }
                let fitResult = SegmentOLSSolver.fit(efforts: points)
                // DEBUG an6.1 — remove: trace OLS result per segment
                NSLog("[DEBUG an6.1] segId=\(segId) name=\(starred.name) nEfforts=\(fitResult.nEfforts) isValid=\(fitResult.isValid) prTime=\(fitResult.prTime) beta1=\(fitResult.beta1) sigmaResid=\(fitResult.sigmaResid)")
                upsertSegmentFitness(segmentId: segId, result: fitResult)
            }
            try? modelContext.save()
            NSLog("[SyncV2] Regression models fit for \(currentStarred.count) segments")

            // Step 7 — Persist last sync date and LTHR
            UserDefaults.standard.set(Date(), forKey: "lastV2SyncDate")
            if let lthr {
                UserDefaults.standard.set(lthr, forKey: "athleteLTHR")
            }
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: "lastSyncedAt")

            // Step 8 — Update in-memory segments for UI
            setSyncProgress("Preparing your segments...")
            await updateSegmentsFromV2Models(
                starredSegments: currentStarred,
                todayFitness: latestDailyFitness
            )

            NSLog("[SyncV2] complete")
        } catch let error as StravaError {
            NSLog("[SyncV2] Strava error: \(error)")
            switch error {
            case .notAuthenticated, .tokenExchangeFailed:
                syncErrorMessage = "Strava needs you to reconnect — takes 10 seconds."
            case .httpError(let code, _) where code == 401:
                syncErrorMessage = "Strava needs you to reconnect — takes 10 seconds."
            default:
                syncErrorMessage = "Sync didn't complete — tap to try again."
            }
        } catch {
            NSLog("[SyncV2] error: \(error)")
            syncErrorMessage = "Sync didn't complete — tap to try again."
        }

        syncProgressMessage = ""
        isSyncing = false
    }

    /// Clears sync history and wipes the local SwiftData store so the next sync re-fetches from scratch.
    func resetSyncHistory() {
        UserDefaults.standard.removeObject(forKey: SyncService.lastPhase2SyncKey)
        UserDefaults.standard.removeObject(forKey: "lastV2SyncDate")
        do {
            try modelContext.delete(model: ActivityModel.self)
            try modelContext.delete(model: DailyFitnessModel.self)
            try modelContext.delete(model: StarredSegmentModel.self)
            try modelContext.delete(model: SegmentEffortModel.self)
            try modelContext.delete(model: SegmentFitnessModel.self)
            try modelContext.save()
        } catch {
            NSLog("[Sync] Failed to wipe local store on reset: \(error)")
        }
        NSLog("[Sync] History reset — local store wiped, next sync will re-fetch from scratch")
    }

    // MARK: - Private: v2 SwiftData write helpers

    private func setSyncProgress(_ message: String) {
        syncProgressMessage = message
        NSLog("[SyncV2] \(message)")
    }

    /// Upsert one ActivityModel from a StravaActivityV2. TSS is set by the caller after LTHR is known.
    private func upsertActivityModel(_ activity: SyncService.StravaActivityV2, tss: Double) {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let date = isoFull.date(from: activity.startDate)
            ?? isoBasic.date(from: activity.startDate)
            ?? Date()

        let watts: Double? = (activity.deviceWatts == true) ? activity.averageWatts : nil
        let id = activity.id
        var descriptor = FetchDescriptor<ActivityModel>(predicate: #Predicate { $0.stravaId == id })
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.date = date
            existing.movingTime = activity.movingTime
            existing.avgHeartRate = activity.averageHeartrate
            existing.avgWatts = watts
            existing.tss = tss
        } else {
            modelContext.insert(ActivityModel(
                stravaId: id,
                date: date,
                movingTime: activity.movingTime,
                avgHeartRate: activity.averageHeartrate,
                avgWatts: watts,
                tss: tss
            ))
        }
        try? modelContext.save()
    }

    /// Upsert one DailyFitnessModel, keyed on date (UTC midnight).
    private func upsertDailyFitness(_ row: DailyFitnessModel) {
        let day = row.date
        var descriptor = FetchDescriptor<DailyFitnessModel>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.ctl = row.ctl
            existing.atl = row.atl
            existing.tsb = row.tsb
        } else {
            modelContext.insert(row)
        }
    }

    /// Upsert one StarredSegmentModel from a starred segment response, keyed on segmentId.
    /// Always sets isStarred = true — this path is only called for Strava-starred segments.
    private func upsertStarredSegment(_ seg: SyncService.StravaStarredSegmentV2) {
        let id = seg.id
        var descriptor = FetchDescriptor<StarredSegmentModel>(predicate: #Predicate { $0.segmentId == id })
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.name = seg.name
            existing.distance = seg.distance
            existing.avgGrade = seg.averageGrade
            existing.isStarred = true
        } else {
            modelContext.insert(StarredSegmentModel(
                segmentId: id,
                name: seg.name,
                distance: seg.distance,
                avgGrade: seg.averageGrade,
                isStarred: true
            ))
        }
        try? modelContext.save()
    }

    /// Upsert one StarredSegmentModel from a segment detail response (recency-only path).
    /// Sets isStarred = false unless the segment is already in the store as starred.
    private func upsertRecencySegment(_ seg: SyncService.StravaSegmentDetailV2) {
        let id = seg.id
        var descriptor = FetchDescriptor<StarredSegmentModel>(predicate: #Predicate { $0.segmentId == id })
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // Update metadata; preserve isStarred — don't demote a starred segment.
            existing.name = seg.name
            existing.distance = seg.distance
            existing.avgGrade = seg.averageGrade
        } else {
            modelContext.insert(StarredSegmentModel(
                segmentId: id,
                name: seg.name,
                distance: seg.distance,
                avgGrade: seg.averageGrade,
                isStarred: false
            ))
        }
        try? modelContext.save()
    }

    /// Upsert one SegmentEffortModel, keyed on stravaEffortId.
    private func upsertSegmentEffort(_ effort: SyncService.StravaSegmentEffortV2, segmentId: Int) {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let date = isoFull.date(from: effort.startDate)
            ?? isoBasic.date(from: effort.startDate)
            ?? Date()

        let effortId = effort.id
        var descriptor = FetchDescriptor<SegmentEffortModel>(
            predicate: #Predicate { $0.stravaEffortId == effortId }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.effortDate = date
            existing.elapsedTime = Double(effort.elapsedTime)
            // ctlOnDay/tsbOnDay are populated by the join step — don't overwrite here
        } else {
            modelContext.insert(SegmentEffortModel(
                stravaEffortId: effortId,
                segmentId: segmentId,
                effortDate: date,
                elapsedTime: Double(effort.elapsedTime)
            ))
        }
        try? modelContext.save()
    }

    /// Upsert one SegmentFitnessModel from an OLS FitResult, keyed on segmentId.
    private func upsertSegmentFitness(segmentId: Int, result: SegmentOLSSolver.FitResult) {
        var descriptor = FetchDescriptor<SegmentFitnessModel>(
            predicate: #Predicate { $0.segmentId == segmentId }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.beta0 = result.beta0
            existing.beta1 = result.beta1
            existing.beta2 = result.beta2
            existing.sigmaResid = result.sigmaResid
            existing.prTime = result.prTime
            existing.prCTL = result.prCTL
            existing.nEfforts = result.nEfforts
            existing.ctlMin = result.ctlMin
            existing.ctlMax = result.ctlMax
            existing.tsbMin = result.tsbMin
            existing.tsbMax = result.tsbMax
            existing.isValid = result.isValid
            existing.fittedAt = Date()
        } else {
            modelContext.insert(SegmentFitnessModel(
                segmentId: segmentId,
                beta0: result.beta0,
                beta1: result.beta1,
                beta2: result.beta2,
                sigmaResid: result.sigmaResid,
                prTime: result.prTime,
                prCTL: result.prCTL,
                nEfforts: result.nEfforts,
                ctlMin: result.ctlMin,
                ctlMax: result.ctlMax,
                tsbMin: result.tsbMin,
                tsbMax: result.tsbMax,
                isValid: result.isValid,
                fittedAt: Date()
            ))
        }
    }

    /// Populates appState.segments from v2 models. Acts as a bridge until the UI task (1tl)
    /// fully adopts the new data model. Uses PRPredictor probability as the strike score.
    private func updateSegmentsFromV2Models(
        starredSegments: [StarredSegmentModel],
        todayFitness: DailyFitnessModel?
    ) async {
        let ctlToday = todayFitness?.ctl ?? 0
        let tsbToday = todayFitness?.tsb ?? 0

        var newSegments: [SegmentScore] = []

        for starred in starredSegments {
            let segId = starred.segmentId
            var descriptor = FetchDescriptor<SegmentFitnessModel>(
                predicate: #Predicate { $0.segmentId == segId }
            )
            descriptor.fetchLimit = 1
            guard let fitModel = (try? modelContext.fetch(descriptor))?.first else { continue }

            let prediction = PRPredictor.predict(
                model: fitModel,
                ctlToday: ctlToday,
                tsbToday: tsbToday
            )
            // DEBUG an6.1 — remove: trace probability per segment
            NSLog("[DEBUG an6.1] segId=\(segId) name=\(starred.name) ctlToday=\(ctlToday) tsbToday=\(tsbToday) modelValid=\(fitModel.isValid) prob=\(prediction.probability) predValid=\(prediction.isValid)")

            let strikeScore = prediction.probability
            let strikeLabel = Self.strikeLabelV2(for: strikeScore)

            // Fetch PR time from the model for display (convert seconds to Int)
            let prSeconds = Int(fitModel.prTime.rounded())
            let lastEffortSeconds: Int
            // Fetch all efforts for this segment to find the PR date and latest effort.
            let effortDescriptor = FetchDescriptor<SegmentEffortModel>(
                predicate: #Predicate { $0.segmentId == segId },
                sortBy: [SortDescriptor(\.effortDate, order: .reverse)]
            )
            let allSegEfforts = (try? modelContext.fetch(effortDescriptor)) ?? []
            let latestEffort = allSegEfforts.first
            lastEffortSeconds = latestEffort.map { Int($0.elapsedTime.rounded()) } ?? prSeconds

            // Derive the PR date from the effort with the minimum elapsed time.
            let prEffort = allSegEfforts.min(by: { $0.elapsedTime < $1.elapsedTime })
            let prDateString: String
            if let prEffortDate = prEffort?.effortDate {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.timeZone = TimeZone(identifier: "UTC")
                prDateString = fmt.string(from: prEffortDate)
            } else {
                prDateString = ""
            }

            var score = SegmentScore(
                name: starred.name,
                prSeconds: prSeconds,
                prDate: prDateString,
                fitnessValueAtPR: fitModel.prCTL / 100.0,  // rough bridge: CTL/100 ≈ 0-1
                currentFitnessValue: ctlToday / 100.0,
                trendDirection: "flat",
                lastEffortSeconds: lastEffortSeconds,
                strikeScore: strikeScore,
                strikeLabel: strikeLabel,
                distanceMeters: starred.distance,
                elevationDeltaMeters: starred.avgGrade > 0 ? starred.distance * starred.avgGrade / 100.0 : nil,
                effortsJSON: "[]"
            )
            score.isStarred = starred.isStarred
            // Populate v2 prediction fields from PRPredictor result
            score.prProbability = prediction.isValid ? prediction.probability : nil
            score.predictedTime = prediction.isValid ? prediction.predictedTime : nil
            score.predictionSigma = prediction.isValid ? fitModel.sigmaResid : nil
            score.isExtrapolating = prediction.isExtrapolating
            score.naiveFallback = prediction.naiveFallback
            score.nEfforts = prediction.nEfforts
            newSegments.append(score)
        }

        if !newSegments.isEmpty {
            segments = newSegments.sorted { $0.strikeScore > $1.strikeScore }
            hasRealSegmentData = true
            NSLog("[SyncV2] Updated \(newSegments.count) segments in-memory")
        }
    }

    /// Maps a probability value to the standard 5-tier strike label.
    static func strikeLabelV2(for probability: Double) -> String {
        switch probability {
        case 0.80...: return "Strike now"
        case 0.65..<0.80: return "Almost there"
        case 0.45..<0.65: return "Worth a shot"
        case 0.25..<0.45: return "Getting there"
        default: return "Build first"
        }
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
        var prompt = "Quick read on \(segment.name) — 2-4 sentences, no lists. " +
        "My fitness is \(athleteContext.currentFitnessLabel), trending \(athleteContext.trendDirection). "
        if let prob = segment.prProbability {
            let pct = Int(prob * 100)
            prompt += "PR probability: \(pct)% (\(segment.strikeLabel)). "
            if let predicted = segment.predictedTime {
                let mins = Int(predicted) / 60
                let secs = Int(predicted) % 60
                prompt += "Predicted time: \(mins):\(String(format: "%02d", secs)). "
            }
            if segment.isExtrapolating {
                prompt += "Note: current fitness is outside the range used to build this model — confidence is limited. "
            }
        } else {
            prompt += "Not enough data to model a probability — \(segment.naiveFallback ?? "limited history on this segment"). "
        }
        prompt += "Is this a good window, and if not, what changes it?"
        return prompt
    }
}
