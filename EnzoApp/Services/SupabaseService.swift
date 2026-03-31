import Foundation

enum SupabaseError: Error {
    case invalidURL
    case httpError(Int, String?)
    case decodingFailed
    case emptyResponse
}

actor SupabaseService {

    private var baseURL: String { Config.supabaseURL + "/rest/v1" }
    private var apiKey: String { Config.supabaseAnonKey }

    // MARK: - Fitness Snapshots

    func fetchFitnessSnapshots(userId: UUID) async throws -> [FitnessSnapshotRow] {
        let urlString = "\(baseURL)/fitness_snapshots?user_id=eq.\(userId.uuidString.lowercased())&order=month.asc"
        return try await get(urlString: urlString)
    }

    func upsertFitnessSnapshot(_ row: FitnessSnapshotRow) async throws -> FitnessSnapshotRow {
        // on_conflict tells Supabase which unique constraint to use for merge-duplicates resolution.
        let urlString = "\(baseURL)/fitness_snapshots?on_conflict=user_id,month"
        return try await upsert(urlString: urlString, row: row)
    }

    // MARK: - Segment Scores

    func fetchSegmentScores(userId: UUID) async throws -> [SegmentScoreRow] {
        let urlString = "\(baseURL)/segment_scores?user_id=eq.\(userId.uuidString.lowercased())"
        return try await get(urlString: urlString)
    }

    func upsertSegmentScore(_ row: SegmentScoreRow) async throws -> SegmentScoreRow {
        // on_conflict tells Supabase which unique constraint to use for merge-duplicates resolution.
        let urlString = "\(baseURL)/segment_scores?on_conflict=user_id,strava_segment_id"
        return try await upsert(urlString: urlString, row: row)
    }

    // MARK: - Users

    func createUser(stravaAthleteId: Int64, displayName: String) async throws -> UUID {
        struct UserRow: Codable {
            let stravaAthleteId: Int64
            let displayName: String

            enum CodingKeys: String, CodingKey {
                case stravaAthleteId = "strava_athlete_id"
                case displayName = "display_name"
            }
        }

        struct UserRowResponse: Decodable {
            let id: UUID
        }

        let urlString = "\(baseURL)/users?on_conflict=strava_athlete_id"
        var request = try makeRequest(urlString: urlString)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(UserRow(stravaAthleteId: stravaAthleteId, displayName: displayName))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
            throw SupabaseError.httpError(statusCode, body)
        }

        do {
            let rows = try JSONDecoder().decode([UserRowResponse].self, from: data)
            guard let first = rows.first else { throw SupabaseError.emptyResponse }
            return first.id
        } catch {
            throw SupabaseError.decodingFailed
        }
    }

    /// Looks up a user's Supabase UUID by their Strava athlete ID.
    /// Used as a fallback when the UUID wasn't cached in Keychain (e.g. authenticated before Step 7).
    func fetchUserId(stravaAthleteId: Int64) async throws -> UUID? {
        let urlString = "\(baseURL)/users?strava_athlete_id=eq.\(stravaAthleteId)&limit=1"
        struct UserRow: Decodable { let id: UUID }
        let rows: [UserRow] = try await get(urlString: urlString)
        return rows.first?.id
    }

    /// Returns the athlete's display name and last activity date for context assembly.
    func fetchUserProfile(userId: UUID) async throws -> UserProfile {
        let urlString = "\(baseURL)/users?id=eq.\(userId.uuidString.lowercased())&limit=1"
        let rows: [UserProfileRow] = try await get(urlString: urlString)
        guard let row = rows.first else { throw SupabaseError.emptyResponse }
        return UserProfile(
            displayName: row.displayName ?? "Athlete",
            lastActivityDate: row.lastActivityDate.flatMap { Self.dateFormatter.date(from: $0) }
        )
    }

    /// Updates last_activity_date on the users row after a sync.
    func updateLastActivityDate(userId: UUID, date: Date) async throws {
        struct Patch: Encodable {
            let lastActivityDate: String
            enum CodingKeys: String, CodingKey { case lastActivityDate = "last_activity_date" }
        }
        let urlString = "\(baseURL)/users?id=eq.\(userId.uuidString.lowercased())"
        var request = try makeRequest(urlString: urlString)
        request.httpMethod = "PATCH"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(Patch(lastActivityDate: Self.dateFormatter.string(from: date)))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SupabaseError.httpError(code, nil)
        }
    }

    struct UserProfile {
        let displayName: String
        let lastActivityDate: Date?
    }

    private struct UserProfileRow: Decodable {
        let displayName: String?
        let lastActivityDate: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case lastActivityDate = "last_activity_date"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Goals

    func fetchActiveGoal(userId: UUID) async throws -> GoalRow? {
        let urlString = "\(baseURL)/goals?user_id=eq.\(userId.uuidString.lowercased())&is_active=eq.true&limit=1"
        let rows: [GoalRow] = try await get(urlString: urlString)
        return rows.first
    }

    func upsertGoal(_ row: GoalRow) async throws -> GoalRow {
        let urlString = "\(baseURL)/goals"
        return try await upsert(urlString: urlString, row: row)
    }

    /// Deactivates all current active goals for the user, then inserts a new active goal.
    /// Uses a separate insert-only struct to avoid sending a null `id` field (which would
    /// conflict with PostgreSQL's NOT NULL constraint on the auto-generated primary key).
    func saveGoal(
        userId: UUID,
        segmentName: String,
        targetDate: Date?,
        requiredFitnessLabel: String,
        requiredFitnessValue: Double
    ) async throws {
        // Deactivate existing active goals
        let deactivateURL = "\(baseURL)/goals?user_id=eq.\(userId.uuidString.lowercased())&is_active=eq.true"
        var deactivateReq = try makeRequest(urlString: deactivateURL)
        deactivateReq.httpMethod = "PATCH"
        deactivateReq.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        deactivateReq.httpBody = try JSONEncoder().encode(["is_active": false])
        _ = try? await URLSession.shared.data(for: deactivateReq)

        // Insert new active goal (no id field — Supabase auto-generates it)
        struct GoalInsert: Encodable {
            let userId: String
            let rawDescription: String
            let goalType: String
            let targetSegmentName: String
            let targetDate: String?
            let requiredFitnessLabel: String
            let requiredFitnessValue: Double
            let isActive: Bool
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case rawDescription = "raw_description"
                case goalType = "goal_type"
                case targetSegmentName = "target_segment_name"
                case targetDate = "target_date"
                case requiredFitnessLabel = "required_fitness_label"
                case requiredFitnessValue = "required_fitness_value"
                case isActive = "is_active"
            }
        }

        let insert = GoalInsert(
            userId: userId.uuidString.lowercased(),
            rawDescription: segmentName,
            goalType: "segment_pr",
            targetSegmentName: segmentName,
            targetDate: targetDate.map { Self.dateFormatter.string(from: $0) },
            requiredFitnessLabel: requiredFitnessLabel,
            requiredFitnessValue: requiredFitnessValue,
            isActive: true
        )

        let urlString = "\(baseURL)/goals"
        var request = try makeRequest(urlString: urlString)
        request.httpMethod = "POST"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(insert)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SupabaseError.httpError(code, nil)
        }
    }

    // MARK: - Private helpers

    private func makeRequest(urlString: String) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw SupabaseError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func get<T: Decodable>(urlString: String) async throws -> [T] {
        var request = try makeRequest(urlString: urlString)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
            throw SupabaseError.httpError(statusCode, body)
        }

        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            throw SupabaseError.decodingFailed
        }
    }

    private func upsert<T: Codable>(urlString: String, row: T) async throws -> T {
        var request = try makeRequest(urlString: urlString)
        request.httpMethod = "POST"
        // merge-duplicates resolves unique constraint conflicts (upsert behavior)
        // return=representation returns the full inserted/updated row including server-assigned id
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(row)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
            throw SupabaseError.httpError(statusCode, body)
        }

        do {
            let rows = try JSONDecoder().decode([T].self, from: data)
            guard let first = rows.first else { throw SupabaseError.emptyResponse }
            return first
        } catch {
            throw SupabaseError.decodingFailed
        }
    }
}
