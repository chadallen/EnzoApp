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
    private let supabaseService: SupabaseService

    init(stravaService: StravaService, supabaseService: SupabaseService) {
        self.stravaService = stravaService
        self.supabaseService = supabaseService
    }

    // MARK: - Phase 1 sync

    /// Fetches all Strava activities, computes monthly fitness snapshots in-memory,
    /// and writes derived rows to Supabase. Raw Strava data is never persisted.
    func syncPhase1(userId: UUID) async throws {
        try await stravaService.refreshTokenIfNeeded()
        guard let accessToken = KeychainHelper.load(for: KeychainHelper.stravaAccessToken) else {
            throw SyncError.notAuthenticated
        }

        let activities = try await fetchAllActivities(accessToken: accessToken)
        let rides = filterAndComputeRides(activities)
        let snapshots = Self.computeSnapshots(from: rides, userId: userId)

        for snapshot in snapshots {
            _ = try await supabaseService.upsertFitnessSnapshot(snapshot)
        }

        // Track most recent qualifying ride date for days_since_last_ride computation.
        if let mostRecentDate = rides.map({ $0.date }).max() {
            try? await supabaseService.updateLastActivityDate(userId: userId, date: mostRecentDate)
        }
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
    static func computeSnapshots(from rides: [RideData], userId: UUID) -> [FitnessSnapshotRow] {
        guard !rides.isEmpty else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.timeZone = TimeZone(identifier: "UTC")

        // All-time min/max efficiency across every qualifying ride — used for normalization.
        let allEfficiencies = rides.map { $0.efficiencyValue }
        let allTimeMin = allEfficiencies.min()!
        let allTimeMax = allEfficiencies.max()!

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
            var row = FitnessSnapshotRow(snapshot: snapshot, userId: userId)
            row.avgEfficiency = avgEfficiency
            return row
        }
    }

    // MARK: - Phase 2 sync

    /// Maximum number of activities to fetch in Phase 2.
    /// TODO: Placeholder for proof of concept — production requires proper rate-limit
    /// batching across the full activity history (200 req/15 min, 2000 req/day).
    static let phase2ActivityLimit = 100

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
        let segment: StravaSegmentSummary

        enum CodingKeys: String, CodingKey {
            case elapsedTime = "elapsed_time"
            case startDate   = "start_date"
            case segment
        }
    }

    struct StravaSegmentSummary: Decodable {
        let id: Int64
        let name: String
        let startLatlng: [Double]?
        let endLatlng: [Double]?
        let effortCount: Int?
        let athletePrEffort: StravaAthletePREffort?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case startLatlng    = "start_latlng"
            case endLatlng      = "end_latlng"
            case effortCount    = "effort_count"
            case athletePrEffort = "athlete_pr_effort"
        }
    }

    struct StravaAthletePREffort: Decodable {
        let prElapsedTime: Int
        let startDateLocal: String

        enum CodingKeys: String, CodingKey {
            case prElapsedTime  = "pr_elapsed_time"
            case startDateLocal = "start_date_local"
        }
    }

    /// Fetches the 100 most recent cycling activities in detail, extracts segment efforts,
    /// computes strike scores, and upserts to the segment_scores table.
    /// Raw Strava data is never persisted.
    func syncPhase2(userId: UUID) async throws {
        try await stravaService.refreshTokenIfNeeded()
        guard let accessToken = KeychainHelper.load(for: KeychainHelper.stravaAccessToken) else {
            throw SyncError.notAuthenticated
        }

        // Fetch fitness snapshots once — used as a lookup for fitness_value_at_pr.
        let snapshotRows = try await supabaseService.fetchFitnessSnapshots(userId: userId)
        // month is stored as "YYYY-MM-01"; normalize to "YYYY-MM" for lookup.
        let snapshotByMonth: [String: Double] = Dictionary(
            snapshotRows.map { row -> (String, Double) in
                let key = String(row.month.prefix(7))
                return (key, row.fitnessValue)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Fetch the most recent N cycling activity IDs.
        let recentActivities = try await fetchRecentCyclingActivities(
            accessToken: accessToken,
            limit: Self.phase2ActivityLimit
        )

        // Track one row per segment. Strava returns activities newest-first,
        // so the first time we see a segment gives us its most recent effort data.
        var segmentMap: [Int64: SegmentScoreRow] = [:]

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

            guard let efforts = detail.segmentEfforts else { continue }

            for effort in efforts {
                let seg = effort.segment
                guard let prEffort = seg.athletePrEffort else { continue }

                let segId = seg.id

                // Derive "YYYY-MM" from PR date for snapshot lookup.
                // PR date from Strava is ISO8601; trim to "YYYY-MM".
                let prDateISO = prEffort.startDateLocal
                let prMonthKey = String(prDateISO.prefix(7))
                let prDateFormatted: String
                if prDateISO.count >= 10 {
                    prDateFormatted = String(prDateISO.prefix(10))
                } else {
                    prDateFormatted = prDateISO
                }

                let fitnessAtPR = snapshotByMonth[prMonthKey] ?? 0.0

                // Current fitness = most recent snapshot value (snapshots are ordered asc by month).
                let currentFitness = snapshotRows.last?.fitnessValue ?? 0.0

                // Trend = most recent snapshot trend.
                let currentTrend = snapshotRows.last?.trendDirection ?? "flat"

                let score = SegmentScorer.strikeScore(
                    fitnessValueAtPR: fitnessAtPR,
                    currentFitnessValue: currentFitness,
                    trendDirection: currentTrend,
                    prDate: prDateFormatted
                )

                // Determine this effort's date (normalized to "YYYY-MM-DD").
                let effortDateStr: String
                if let parsed = isoFull.date(from: effort.startDate) ?? isoBasic.date(from: effort.startDate) {
                    effortDateStr = dateFormatter.string(from: parsed)
                } else {
                    effortDateStr = String(effort.startDate.prefix(10))
                }

                // Only write a row the first time we see this segment.
                // Strava returns activities newest-first, so the first effort seen
                // is the most recent one — use it for last_effort_* fields.
                // PR data (athlete_pr_effort) is the same regardless of which activity surfaces it.
                if segmentMap[segId] == nil {
                    let row = SegmentScoreRow(
                        id: nil,
                        userId: userId,
                        stravaSegmentId: segId,
                        segmentName: seg.name,
                        prSeconds: prEffort.prElapsedTime,
                        prAchievedAt: prDateFormatted,
                        fitnessValueAtPr: fitnessAtPR,
                        currentFitnessValue: currentFitness,
                        trendDirection: currentTrend,
                        lastEffortSeconds: effort.elapsedTime,
                        lastEffortDate: effortDateStr,
                        strikeScore: score,
                        strikeLabel: SegmentScorer.strikeLabel(for: score)
                    )
                    segmentMap[segId] = row
                }
            }
        }

        NSLog("[Sync P2] Upserting \(segmentMap.count) segment rows")
        for row in segmentMap.values {
            _ = try await supabaseService.upsertSegmentScore(row)
        }
        NSLog("[Sync P2] Phase 2 complete")
    }

    // MARK: - Private: Phase 2 fetch helpers

    private func fetchRecentCyclingActivities(accessToken: String, limit: Int) async throws -> [StravaActivity] {
        var result: [StravaActivity] = []
        var page = 1

        while result.count < limit {
            let batch = try await fetchPage(accessToken: accessToken, page: page)
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

    private func fetchPage(accessToken: String, page: Int) async throws -> [StravaActivity] {
        guard var components = URLComponents(string: Self.activitiesURLString) else {
            throw SyncError.fetchFailed(nil)
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "200"),
            URLQueryItem(name: "page",     value: String(page))
        ]
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
