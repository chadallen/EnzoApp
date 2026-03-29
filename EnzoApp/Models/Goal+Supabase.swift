import Foundation

/// Codable DTO for the `goals` Supabase table.
/// `GoalContext` is the lean in-memory domain struct; `GoalRow` is the full DB representation.
struct GoalRow: Codable {
    var id: UUID?
    var userId: UUID?
    var rawDescription: String
    var claudeInterpretation: String?
    var goalType: String
    var targetSegmentId: Int64?
    var targetSegmentName: String?
    /// PostgreSQL `date` format: "YYYY-MM-DD"
    var targetDate: String?
    /// Optional target time in seconds (aspirational)
    var targetValue: Double?
    var requiredFitnessLabel: String?
    var requiredFitnessValue: Double?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case rawDescription = "raw_description"
        case claudeInterpretation = "claude_interpretation"
        case goalType = "goal_type"
        case targetSegmentId = "target_segment_id"
        case targetSegmentName = "target_segment_name"
        case targetDate = "target_date"
        case targetValue = "target_value"
        case requiredFitnessLabel = "required_fitness_label"
        case requiredFitnessValue = "required_fitness_value"
        case isActive = "is_active"
    }
}
