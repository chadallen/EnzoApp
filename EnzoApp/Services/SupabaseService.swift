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
        let urlString = "\(baseURL)/fitness_snapshots"
        return try await upsert(urlString: urlString, row: row)
    }

    // MARK: - Segment Scores

    func fetchSegmentScores(userId: UUID) async throws -> [SegmentScoreRow] {
        let urlString = "\(baseURL)/segment_scores?user_id=eq.\(userId.uuidString.lowercased())"
        return try await get(urlString: urlString)
    }

    func upsertSegmentScore(_ row: SegmentScoreRow) async throws -> SegmentScoreRow {
        let urlString = "\(baseURL)/segment_scores"
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

        let urlString = "\(baseURL)/users"
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
