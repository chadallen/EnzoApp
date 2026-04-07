import Foundation

// MARK: - Errors

enum SyncError: Error {
    case notAuthenticated
    case fetchFailed(String?)
    case decodingFailed
    case rateLimited
}

// MARK: - SyncService

actor SyncService {

    static let activitiesURLString = "https://www.strava.com/api/v3/athlete/activities"

    // Minimal Strava summary activity — only fields needed for Phase 1.
    // Never persisted; decoded in-memory and discarded after computation.
    struct StravaActivity: Decodable {
        let id: Int64
        let startDate: String
        let movingTime: Int          // seconds
        let distance: Double         // meters
        let sportType: String
        let hasHeartrate: Bool
        let averageHeartrate: Double?
        let totalElevationGain: Double
        let trainer: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case startDate          = "start_date"
            case movingTime         = "moving_time"
            case distance
            case sportType          = "sport_type"
            case hasHeartrate       = "has_heartrate"
            case averageHeartrate   = "average_heartrate"
            case totalElevationGain = "total_elevation_gain"
            case trainer
        }
    }

    // Per-ride computed value — ephemeral, never persisted.
    struct RideData {
        let date: Date
        let efficiencyValue: Double
        let durationHours: Double
    }

    private let stravaService: StravaService

    init(stravaService: StravaService) {
        self.stravaService = stravaService
    }

    // MARK: - Phase 1 sync

    /// Fetches all Strava activities, computes monthly fitness snapshots in-memory,
    /// and returns them for the caller to persist. Raw Strava data is never persisted.
    /// Returns activity count, computed snapshot rows, and the most recent qualifying ride date.
    func syncPhase1() async throws -> (activityCount: Int, snapshots: [FitnessSnapshotRow], lastActivityDate: Date?) {
        try await stravaService.refreshTokenIfNeeded()
        guard let accessToken = KeychainHelper.load(for: KeychainHelper.stravaAccessToken) else {
            throw SyncError.notAuthenticated
        }

        let activities = try await fetchAllActivities(accessToken: accessToken)
        let rides = filterAndComputeRides(activities)
        let snapshots = Self.computeSnapshots(from: rides)
        let lastActivityDate = rides.map({ $0.date }).max()

        return (activityCount: activities.count, snapshots: snapshots, lastActivityDate: lastActivityDate)
    }

    // MARK: - Static helpers (testable without network)

    /// Returns true if an activity qualifies for efficiency computation.
    /// Cycling type + at least 30 minutes + has heart rate data.
    static func isQualifying(_ activity: StravaActivity) -> Bool {
        guard FitnessCalculator.cyclingTypes.contains(activity.sportType) else { return false }
        guard activity.movingTime >= 1800 else { return false }   // 30 minutes = 1800 s
        guard activity.hasHeartrate else { return false }
        return true
    }

    /// Builds monthly `FitnessSnapshotRow`s from pre-computed ride data.
    ///
    /// Pure function: deterministic from input, no I/O. Each month's snapshot uses:
    /// - A 2-month rolling window for the fitness value (normalized against all-time min/max)
    /// - A 4-week vs prior-4-week comparison for trend direction
    /// - That specific month's hours and activity count for summary stats
    static func computeSnapshots(from rides: [RideData]) -> [FitnessSnapshotRow] {
        guard !rides.isEmpty else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.timeZone = TimeZone(identifier: "UTC")

        // Percentile-based normalization: use 5th/95th percentile instead of absolute min/max.
        // Prevents outlier months (illness, barely riding) from compressing all normal months
        // into a narrow band in the middle of the scale.
        let allEfficiencies = rides.map { $0.efficiencyValue }
        let allTimeMin = FitnessCalculator.percentile(5, of: allEfficiencies)
        let allTimeMax = FitnessCalculator.percentile(95, of: allEfficiencies)

        // Group rides by "yyyy-MM" key.
        var ridesByMonth: [String: [RideData]] = [:]
        for ride in rides {
            let key = monthFormatter.string(from: ride.date)
            ridesByMonth[key, default: []].append(ride)
        }

        return ridesByMonth.keys.sorted().compactMap { monthKey in
            guard let monthStart = monthFormatter.date(from: monthKey) else { return nil }

            // Last second of the month.
            var oneMonthOneMoment = DateComponents()
            oneMonthOneMoment.month = 1
            oneMonthOneMoment.second = -1
            guard let monthEnd = calendar.date(byAdding: oneMonthOneMoment, to: monthStart) else { return nil }

            // 2-month rolling window: rides in prior month + this month.
            guard let windowStart = calendar.date(byAdding: .month, value: -1, to: monthStart) else { return nil }
            let windowRides = rides.filter { $0.date >= windowStart && $0.date <= monthEnd }
            let windowEfficiencies = windowRides.map { $0.efficiencyValue }

            let fitnessValue = FitnessCalculator.fitnessValue(
                recentEfficiencies: windowEfficiencies,
                allTimeMin: allTimeMin,
                allTimeMax: allTimeMax
            )

            // Trend: last 4 weeks vs prior 4 weeks, measured from end of month.
            let fourWeeksAgo  = calendar.date(byAdding: .day, value: -28, to: monthEnd)!
            let eightWeeksAgo = calendar.date(byAdding: .day, value: -56, to: monthEnd)!

            let recentRides = rides.filter { $0.date > fourWeeksAgo  && $0.date <= monthEnd }
            let priorRides  = rides.filter { $0.date > eightWeeksAgo && $0.date <= fourWeeksAgo }

            let trend: String
            if recentRides.isEmpty || priorRides.isEmpty {
                trend = "flat"
            } else {
                let recentAvg = recentRides.map { $0.efficiencyValue }.reduce(0, +) / Double(recentRides.count)
                let priorAvg  = priorRides.map  { $0.efficiencyValue }.reduce(0, +) / Double(priorRides.count)
                trend = FitnessCalculator.trendDirection(recentFourWeeks: recentAvg, priorFourWeeks: priorAvg)
            }

            // Summary stats: this month's rides only (not the rolling window).
            let thisMonthRides = ridesByMonth[monthKey]!
            let hoursRidden    = thisMonthRides.map { $0.durationHours }.reduce(0, +)
            let avgEfficiency  = windowEfficiencies.isEmpty ? 0.0 :
                windowEfficiencies.reduce(0, +) / Double(windowEfficiencies.count)

            let snapshot = FitnessSnapshot(
                month: monthKey,
                label: FitnessCalculator.fitnessLabel(for: fitnessValue),
                value: fitnessValue,
                hours: hoursRidden,
                rides: thisMonthRides.count,
                trend: trend
            )
            var row = FitnessSnapshotRow(snapshot: snapshot)
            row.avgEfficiency = avgEfficiency
            return row
        }
    }

    // MARK: - Phase 2 sync

    /// Maximum number of *new* activities to fetch per Phase 2 run.
    /// Tunable: 25 is fast for iteration; raise toward 200 once smoke tests pass.
    /// Production full-history import will need batch pausing (200 req/15 min limit).
    static let phase2ActivityLimit = 25

    /// UserDefaults key for the timestamp of the last successful Phase 2 run.
    /// Used to make Phase 2 incremental — only fetches activities newer than this date.
    static let lastPhase2SyncKey = "lastPhase2SyncTimestamp"

    // Strava full activity response — ephemeral, never persisted.
    struct StravaDetailActivity: Decodable {
        let id: Int64
        let segmentEfforts: [StravaSegmentEffort]?

        enum CodingKeys: String, CodingKey {
            case id
            case segmentEfforts = "segment_efforts"
        }
    }

    struct StravaSegmentEffort: Decodable {
        let elapsedTime: Int
        let startDate: String
        let startDateLocal: String
        let segment: StravaSegmentSummary
        // prRank == 1 means this effort is the athlete's all-time PR on this segment.
        // athlete_pr_effort is schema-defined on SummarySegment but Strava does not populate
        // it in activity detail responses — prRank is the reliable signal.
        let prRank: Int?

        enum CodingKeys: String, CodingKey {
            case elapsedTime    = "elapsed_time"
            case startDate      = "start_date"
            case startDateLocal = "start_date_local"
            case segment
            case prRank         = "pr_rank"
        }
    }

    struct StravaSegmentSummary: Decodable {
        let id: Int64
        let name: String
        let distance: Double
        let elevationHigh: Double
        let elevationLow: Double

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case distance
            case elevationHigh = "elevation_high"
            case elevationLow  = "elevation_low"
        }
    }

    /// Fetches recent cycling activities in detail, extracts segment efforts,
    /// computes strike scores, and returns rows for the caller to persist.
    /// Raw Strava data is never persisted.
    func syncPhase2(fitnessSnapshots: [FitnessSnapshot]) async throws -> [SegmentScoreRow] {
        try await stravaService.refreshTokenIfNeeded()
        guard let accessToken = KeychainHelper.load(for: KeychainHelper.stravaAccessToken) else {
            throw SyncError.notAuthenticated
        }

        // Build fitness lookup from the locally stored snapshots.
        // FitnessSnapshot.month is already "YYYY-MM" format.
        let sortedSnapshots = fitnessSnapshots.sorted { $0.month < $1.month }
        let snapshotByMonth: [String: Double] = Dictionary(
            sortedSnapshots.map { ($0.month, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentFitness = sortedSnapshots.last?.value ?? 0.0
        let currentTrend = sortedSnapshots.last?.trend ?? "flat"

        // Incremental: only fetch activities newer than the last Phase 2 run.
        // On first run, lastSync is nil → fetches the most recent N activities.
        let lastSync = UserDefaults.standard.object(forKey: Self.lastPhase2SyncKey) as? Date
        if let lastSync {
            NSLog("[Sync P2] Incremental — fetching activities after \(lastSync)")
        } else {
            NSLog("[Sync P2] First run — fetching most recent \(Self.phase2ActivityLimit) activities")
        }

        let recentActivities = try await fetchRecentCyclingActivities(
            accessToken: accessToken,
            limit: Self.phase2ActivityLimit,
            after: lastSync
        )

        guard !recentActivities.isEmpty else {
            NSLog("[Sync P2] No new activities since last sync — skipping")
            return []
        }

        NSLog("[Sync P2] Processing \(recentActivities.count) activities")

        // Track one row per segment. Strava returns activities newest-first,
        // so the first time we see a segment gives us its most recent effort data.
        var segmentMap: [Int64: SegmentScoreRow] = [:]

        // Tracks the most recent elapsed time per segment (newest-first order means
        // the first occurrence of each segment is the latest real-world effort).
        var latestEffortMap: [Int64: Int] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        for activity in recentActivities {
            // Rate limit: Strava allows 200 req/15 min (~0.22 req/sec).
            // 1.5s delay = ~0.67 req/sec — comfortably under limit, ~2.5 min for 100 activities.
            // TODO: Production needs batch pausing (sleep 15 min after 200 calls) for full history.
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let detail: StravaDetailActivity
            do {
                detail = try await fetchActivityDetail(
                    activityId: activity.id,
                    accessToken: accessToken
                )
            } catch SyncError.rateLimited {
                NSLog("[Sync P2] Rate limited — stopping Phase 2 early at activity \(activity.id)")
                break
            }

            guard let efforts = detail.segmentEfforts else {
                NSLog("[Sync P2] Activity \(activity.id): no segment_efforts (nil)")
                continue
            }

            let prEfforts = efforts.filter { $0.prRank == 1 }
            NSLog("[Sync P2] Activity \(activity.id): \(efforts.count) efforts, \(prEfforts.count) with PR")

            for effort in efforts {
                let seg = effort.segment
                let segId = seg.id

                // Record most recent elapsed time — first occurrence wins (activities are newest-first).
                if latestEffortMap[segId] == nil {
                    latestEffortMap[segId] = effort.elapsedTime
                }

                // Determine this effort's date (normalized to "YYYY-MM-DD").
                let effortDateStr: String
                if let parsed = isoFull.date(from: effort.startDate) ?? isoBasic.date(from: effort.startDate) {
                    effortDateStr = dateFormatter.string(from: parsed)
                } else {
                    effortDateStr = String(effort.startDate.prefix(10))
                }

                // prRank == 1 means this effort IS the athlete's all-time PR on this segment.
                if effort.prRank == 1 {
                    let prDateISO = effort.startDateLocal
                    let prMonthKey = String(prDateISO.prefix(7))
                    let prDateFormatted = prDateISO.count >= 10 ? String(prDateISO.prefix(10)) : prDateISO

                    let fitnessAtPR = snapshotByMonth[prMonthKey] ?? 0.0
                    let prSecs = effort.elapsedTime
                    let lastSecs = latestEffortMap[segId] ?? prSecs

                    let baseScore = SegmentScorer.strikeScore(
                        fitnessValueAtPR: fitnessAtPR,
                        currentFitnessValue: currentFitness,
                        prDate: prDateFormatted,
                        lastEffortSeconds: lastSecs,
                        prSeconds: prSecs
                    )
                    // DEMO: deterministic jitter per segment so scores spread visually.
                    // Seeded from segId — same segment always gets the same offset.
                    // Remove before shipping.
                    let demoJitter = Double((segId &* 2654435761) & 0xFFFF) / Double(0xFFFF) * 0.5 - 0.25
                    let score = min(max(baseScore + demoJitter, 0.10), 0.95)

                    let row = SegmentScoreRow(
                        id: nil,
                        userId: nil,
                        stravaSegmentId: segId,
                        segmentName: seg.name,
                        prSeconds: prSecs,
                        prAchievedAt: prDateFormatted,
                        fitnessValueAtPr: fitnessAtPR,
                        currentFitnessValue: currentFitness,
                        trendDirection: currentTrend,
                        lastEffortSeconds: lastSecs,
                        lastEffortDate: effortDateStr,
                        strikeScore: score,
                        strikeLabel: SegmentScorer.strikeLabel(for: score),
                        distanceMeters: seg.distance,
                        elevationDeltaMeters: seg.elevationHigh - seg.elevationLow
                    )
                    segmentMap[segId] = row
                } else if segmentMap[segId] == nil {
                    // Non-PR effort on a segment we haven't seen yet — skip.
                }
            }
        }

        NSLog("[Sync P2] Computed \(segmentMap.count) segment rows")

        // Mark this run's timestamp so the next sync only fetches new activities.
        UserDefaults.standard.set(Date(), forKey: Self.lastPhase2SyncKey)
        NSLog("[Sync P2] Phase 2 complete")

        return Array(segmentMap.values)
    }

    // MARK: - Private: Phase 2 fetch helpers

    private func fetchRecentCyclingActivities(accessToken: String, limit: Int, after: Date? = nil) async throws -> [StravaActivity] {
        var result: [StravaActivity] = []
        var page = 1

        while result.count < limit {
            let batch = try await fetchPage(accessToken: accessToken, page: page, after: after)
            if batch.isEmpty { break }
            let cycling = batch.filter { FitnessCalculator.cyclingTypes.contains($0.sportType) }
            result.append(contentsOf: cycling)
            if batch.count < 200 { break }
            page += 1
        }

        return Array(result.prefix(limit))
    }

    private func fetchActivityDetail(activityId: Int64, accessToken: String) async throws -> StravaDetailActivity {
        let urlString = "https://www.strava.com/api/v3/activities/\(activityId)?include_all_efforts=true"
        guard let url = URL(string: urlString) else { throw SyncError.fetchFailed(nil) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw SyncError.fetchFailed(nil) }

        if http.statusCode == 429 { throw SyncError.rateLimited }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw SyncError.fetchFailed("HTTP \(http.statusCode): \(body ?? "")")
        }

        do {
            return try JSONDecoder().decode(StravaDetailActivity.self, from: data)
        } catch {
            throw SyncError.decodingFailed
        }
    }

    // MARK: - Private: Strava fetch

    private func fetchAllActivities(accessToken: String) async throws -> [StravaActivity] {
        var all: [StravaActivity] = []
        var page = 1

        while true {
            let batch = try await fetchPage(accessToken: accessToken, page: page)
            all.append(contentsOf: batch)
            if batch.count < 200 { break }
            page += 1
        }

        return all
    }

    private func fetchPage(accessToken: String, page: Int, after: Date? = nil) async throws -> [StravaActivity] {
        guard var components = URLComponents(string: Self.activitiesURLString) else {
            throw SyncError.fetchFailed(nil)
        }
        var queryItems = [
            URLQueryItem(name: "per_page", value: "200"),
            URLQueryItem(name: "page",     value: String(page))
        ]
        if let after {
            queryItems.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw SyncError.fetchFailed(nil) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
            throw SyncError.fetchFailed("HTTP \(code): \(body ?? "")")
        }

        do {
            return try JSONDecoder().decode([StravaActivity].self, from: data)
        } catch {
            throw SyncError.decodingFailed
        }
    }

    // MARK: - Private: filter + efficiency

    private func filterAndComputeRides(_ activities: [StravaActivity]) -> [RideData] {
        // Strava returns ISO8601 dates; try both with and without fractional seconds.
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        return activities.compactMap { activity in
            guard Self.isQualifying(activity) else { return nil }
            guard let avgHR = activity.averageHeartrate, avgHR > 0 else { return nil }

            let durationHours = Double(activity.movingTime) / 3600.0
            let distanceKm    = activity.distance / 1000.0

            guard let eff = FitnessCalculator.efficiency(
                distanceKm: distanceKm,
                elevationGainM: activity.totalElevationGain,
                sportType: activity.sportType,
                durationHours: durationHours,
                avgHR: Int(avgHR)
            ) else { return nil }

            let date = isoFull.date(from: activity.startDate)
                    ?? isoBasic.date(from: activity.startDate)
            guard let date else { return nil }

            return RideData(date: date, efficiencyValue: eff, durationHours: durationHours)
        }
    }
}
