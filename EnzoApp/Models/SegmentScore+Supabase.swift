import Foundation

/// Codable DTO for segment score data.
/// Converts to/from the `SegmentScore` domain model.
/// Note: `stravaSegmentId` is not on the domain model.
/// SyncService provides it from the Strava API when writing rows.
struct SegmentScoreRow: Codable {
    var id: UUID?
    var userId: UUID?
    var stravaSegmentId: Int64
    var segmentName: String?
    var prSeconds: Int?
    /// PostgreSQL `date` format: "YYYY-MM-DD"
    var prAchievedAt: String?
    var fitnessValueAtPr: Double?
    var currentFitnessValue: Double?
    var trendDirection: String?
    var lastEffortSeconds: Int?
    var lastEffortDate: String?
    var strikeScore: Double?
    var strikeLabel: String?
    var distanceMeters: Double?
    var elevationDeltaMeters: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case stravaSegmentId = "strava_segment_id"
        case segmentName = "segment_name"
        case prSeconds = "pr_seconds"
        case prAchievedAt = "pr_achieved_at"
        case fitnessValueAtPr = "fitness_value_at_pr"
        case currentFitnessValue = "current_fitness_value"
        case trendDirection = "trend_direction"
        case lastEffortSeconds = "last_effort_seconds"
        case lastEffortDate = "last_effort_date"
        case strikeScore = "strike_score"
        case strikeLabel = "strike_label"
        case distanceMeters = "distance_meters"
        case elevationDeltaMeters = "elevation_delta_meters"
    }

    // MARK: - Conversion to domain model

    func toSegmentScore() -> SegmentScore {
        SegmentScore(
            name: segmentName ?? "",
            prSeconds: prSeconds ?? 0,
            prDate: prAchievedAt ?? "",
            fitnessValueAtPR: fitnessValueAtPr ?? 0,
            currentFitnessValue: currentFitnessValue ?? 0,
            trendDirection: trendDirection ?? "flat",
            lastEffortSeconds: lastEffortSeconds ?? 0,
            strikeScore: strikeScore ?? 0,
            strikeLabel: strikeLabel ?? "Not quite ready",
            distanceMeters: distanceMeters,
            elevationDeltaMeters: elevationDeltaMeters
        )
    }
}
