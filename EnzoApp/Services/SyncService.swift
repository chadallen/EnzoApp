import Foundation

// MARK: - Errors

enum SyncError: Error {
    case notAuthenticated
    case fetchFailed(String?)
    case decodingFailed
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
