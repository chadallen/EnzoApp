import Foundation

/// Codable DTO for fitness snapshot data.
/// Converts to/from the `FitnessSnapshot` domain model.
struct FitnessSnapshotRow: Codable, Sendable {
    var id: UUID?
    var userId: UUID?
    /// PostgreSQL `date` format: "YYYY-MM-DD" (always stored as first of month)
    var month: String
    var hoursRidden: Double?
    var activityCount: Int?
    var avgEfficiency: Double?
    var fitnessValue: Double
    var fitnessLabel: String
    var trendDirection: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case month
        case hoursRidden = "hours_ridden"
        case activityCount = "activity_count"
        case avgEfficiency = "avg_efficiency"
        case fitnessValue = "fitness_value"
        case fitnessLabel = "fitness_label"
        case trendDirection = "trend_direction"
    }

    // MARK: - Conversion from domain model

    nonisolated init(snapshot: FitnessSnapshot, userId: UUID? = nil) {
        self.id = nil
        self.userId = userId
        self.month = snapshot.month + "-01"   // "2025-08" → "2025-08-01"
        self.hoursRidden = snapshot.hours
        self.activityCount = snapshot.rides
        self.avgEfficiency = nil
        self.fitnessValue = snapshot.value
        self.fitnessLabel = snapshot.label
        self.trendDirection = snapshot.trend
    }

    /// Parses the "YYYY-MM-DD" month string into a UTC Date for use with SwiftData.
    var monthDate: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: month) ?? .distantPast
    }

    // MARK: - Conversion to domain model

    func toSnapshot() -> FitnessSnapshot {
        // "2025-08-01" → "2025-08"
        let monthPrefix = String(month.prefix(7))
        return FitnessSnapshot(
            month: monthPrefix,
            label: fitnessLabel,
            value: fitnessValue,
            hours: hoursRidden ?? 0,
            rides: activityCount ?? 0,
            trend: trendDirection
        )
    }
}
