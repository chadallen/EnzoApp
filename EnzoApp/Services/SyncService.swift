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

    // 30s to get first byte; 60s total per resource. Guards against Strava responses
    // that start arriving but never complete (default URLSession.shared has a 7-day resource timeout).
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    static let activitiesURLString = "https://www.strava.com/api/v3/athlete/activities"

    /// UserDefaults key for the timestamp of the last successful Phase 2 run.
    /// Kept for UserDefaults cleanup in AppState.disconnect()/resetSyncHistory().
    static let lastPhase2SyncKey = "lastPhase2SyncTimestamp"

    // SyncService no longer owns a persistence layer. All writes are handled by
    // AppState, which owns the SwiftData ModelContext. SyncService is purely a
    // data-fetching and computation layer: fetch from Strava, return rows.
    // This keeps SyncService as a testable actor with no SwiftData dependency.
    private let stravaService: StravaService

    init(stravaService: StravaService) {
        self.stravaService = stravaService
    }

    // MARK: - v2 Response types (ephemeral — never persisted)

    /// Cycling sport types included in v2 activity fetch.
    static let v2CyclingTypes: Set<String> = [
        "Ride", "VirtualRide", "GravelRide", "MountainBikeRide", "EBikeRide"
    ]

    static let starredSegmentsURLString = "https://www.strava.com/api/v3/segments/starred"
    static let segmentBaseURLString     = "https://www.strava.com/api/v3/segments"

    /// Strava summary activity — v2 fields only. Never stored; decoded then discarded.
    struct StravaActivityV2: Decodable {
        let id: Int
        let startDate: String     // ISO8601 UTC
        let movingTime: Int       // seconds
        let averageHeartrate: Double?
        let averageWatts: Double?
        let deviceWatts: Bool?    // true → averageWatts came from a real power meter
        let sportType: String
        /// Segment efforts included in the activity summary response.
        /// Each effort contains enough data to extract the segment ID for recency tracking.
        let segmentEfforts: [StravaSegmentEffortSummary]?

        enum CodingKeys: String, CodingKey {
            case id
            case startDate       = "start_date"
            case movingTime      = "moving_time"
            case averageHeartrate = "average_heartrate"
            case averageWatts    = "average_watts"
            case deviceWatts     = "device_watts"
            case sportType       = "sport_type"
            case segmentEfforts  = "segment_efforts"
        }
    }

    /// Minimal segment effort from the activity summary list — used only to extract segment IDs.
    /// Never stored; decoded in-memory and discarded.
    struct StravaSegmentEffortSummary: Decodable {
        struct SegmentRef: Decodable {
            let id: Int
        }
        let segment: SegmentRef
    }

    /// Segment detail returned by GET /segments/{id}. Never stored directly;
    /// converted to StarredSegmentModel for the recency-only segment upsert path.
    struct StravaSegmentDetailV2: Decodable {
        let id: Int
        let name: String
        let distance: Double    // meters
        let averageGrade: Double // percent

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case distance
            case averageGrade = "average_grade"
        }
    }

    // MARK: - v2 Static helpers (pure — testable without network)

    /// Extracts unique segment IDs from activities whose start_date is within the last `days` days.
    ///
    /// Used to build the 90-day recency segment set. Pure function — no network, no SwiftData.
    /// The caller unions this result with the starred segment IDs and fetches details for any
    /// segment not already known.
    ///
    /// - Parameters:
    ///   - activities: The full list of fetched StravaActivityV2 objects (all sport types).
    ///   - cutoff: Activities at or after this date are included. Typically now - 90 days.
    /// - Returns: Unique segment IDs from qualifying activities, ordered arbitrarily.
    static func recentSegmentIds(from activities: [StravaActivityV2], cutoff: Date) -> Set<Int> {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        var ids = Set<Int>()
        for activity in activities {
            let activityDate = isoFull.date(from: activity.startDate)
                ?? isoBasic.date(from: activity.startDate)
                ?? Date.distantPast
            guard activityDate >= cutoff else { continue }
            for effort in activity.segmentEfforts ?? [] {
                ids.insert(effort.segment.id)
            }
        }
        return ids
    }

    /// One starred segment returned by GET /segments/starred. Never stored; converted to StarredSegmentModel.
    struct StravaStarredSegmentV2: Decodable {
        let id: Int
        let name: String
        let distance: Double   // meters
        let averageGrade: Double // percent

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case distance
            case averageGrade = "average_grade"
        }
    }

    /// One effort from GET /segments/{id}/all_efforts. Never stored; converted to SegmentEffortModel.
    struct StravaSegmentEffortV2: Decodable {
        let id: Int
        let elapsedTime: Int     // seconds
        let startDate: String    // ISO8601 UTC
        let averageHeartrate: Double?
        let averageWatts: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case elapsedTime     = "elapsed_time"
            case startDate       = "start_date"
            case averageHeartrate = "average_heartrate"
            case averageWatts    = "average_watts"
        }
    }

    // MARK: - v2 Fetch methods

    /// Fetches up to 300 cycling activities from the past 3 years.
    /// Filters by sport type client-side. Paginates at 100/page until exhausted or cap reached.
    func fetchActivitiesV2(accessToken: String) async throws -> [StravaActivityV2] {
        let threeYearsAgo = Calendar.current.date(byAdding: .year, value: -3, to: Date())!
        let afterTimestamp = Int(threeYearsAgo.timeIntervalSince1970)

        var results: [StravaActivityV2] = []
        var page = 1

        while results.count < 300 {
            guard var components = URLComponents(string: Self.activitiesURLString) else {
                throw SyncError.fetchFailed("Invalid activities URL")
            }
            components.queryItems = [
                URLQueryItem(name: "after",    value: String(afterTimestamp)),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page",     value: String(page))
            ]
            guard let url = components.url else { throw SyncError.fetchFailed("Invalid activities URL") }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await Self.urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SyncError.fetchFailed("No response") }
            if http.statusCode == 429 { throw SyncError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw SyncError.fetchFailed("HTTP \(http.statusCode)")
            }

            let batch = try JSONDecoder().decode([StravaActivityV2].self, from: data)
            guard !batch.isEmpty else { break }

            let cycling = batch.filter { Self.v2CyclingTypes.contains($0.sportType) }
            results.append(contentsOf: cycling)

            if batch.count < 100 { break } // last page
            page += 1
        }

        return Array(results.prefix(300))
    }

    /// Fetches all segments the athlete has starred on Strava.
    /// Paginates until exhausted. Returns raw Strava structs for the caller to convert.
    func fetchStarredSegmentsV2(accessToken: String) async throws -> [StravaStarredSegmentV2] {
        var results: [StravaStarredSegmentV2] = []
        var page = 1

        while true {
            guard var components = URLComponents(string: Self.starredSegmentsURLString) else {
                throw SyncError.fetchFailed("Invalid starred segments URL")
            }
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "200"),
                URLQueryItem(name: "page",     value: String(page))
            ]
            guard let url = components.url else { throw SyncError.fetchFailed("Invalid starred segments URL") }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await Self.urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SyncError.fetchFailed("No response") }
            if http.statusCode == 429 { throw SyncError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw SyncError.fetchFailed("HTTP \(http.statusCode)")
            }

            let batch = try JSONDecoder().decode([StravaStarredSegmentV2].self, from: data)
            results.append(contentsOf: batch)

            if batch.count < 200 { break } // last page
            page += 1
        }

        return results
    }

    /// Fetches all efforts by the athlete on a specific segment over the past 3 years.
    /// Uses GET /segments/{id}/all_efforts. Paginates until exhausted.
    func fetchSegmentEffortsV2(segmentId: Int, athleteId: Int64, accessToken: String) async throws -> [StravaSegmentEffortV2] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let threeYearsAgo = Calendar.current.date(byAdding: .year, value: -3, to: Date())!
        let startDateStr = isoFormatter.string(from: threeYearsAgo)
        let endDateStr   = isoFormatter.string(from: Date())

        var results: [StravaSegmentEffortV2] = []
        var page = 1

        while true {
            let urlString = "\(Self.segmentBaseURLString)/\(segmentId)/all_efforts"
            guard var components = URLComponents(string: urlString) else {
                throw SyncError.fetchFailed("Invalid segment efforts URL")
            }
            components.queryItems = [
                URLQueryItem(name: "athlete_id",       value: String(athleteId)),
                URLQueryItem(name: "start_date_local", value: startDateStr),
                URLQueryItem(name: "end_date_local",   value: endDateStr),
                URLQueryItem(name: "per_page",         value: "200"),
                URLQueryItem(name: "page",             value: String(page))
            ]
            guard let url = components.url else { throw SyncError.fetchFailed("Invalid segment efforts URL") }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await Self.urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SyncError.fetchFailed("No response") }
            if http.statusCode == 429 { throw SyncError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw SyncError.fetchFailed("HTTP \(http.statusCode)")
            }

            let batch = try JSONDecoder().decode([StravaSegmentEffortV2].self, from: data)
            results.append(contentsOf: batch)

            if batch.count < 200 { break } // last page
            page += 1
        }

        return results
    }

    /// Fetches details for a single segment by ID from GET /segments/{id}.
    /// Used for the recency-only segment upsert path — only called when the segment
    /// is not already in the starred set.
    func fetchSegmentDetailV2(segmentId: Int, accessToken: String) async throws -> StravaSegmentDetailV2 {
        let urlString = "\(Self.segmentBaseURLString)/\(segmentId)"
        guard let url = URL(string: urlString) else {
            throw SyncError.fetchFailed("Invalid segment detail URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await Self.urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.fetchFailed("No response") }
        if http.statusCode == 429 { throw SyncError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.fetchFailed("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(StravaSegmentDetailV2.self, from: data)
        } catch {
            throw SyncError.decodingFailed
        }
    }

}
