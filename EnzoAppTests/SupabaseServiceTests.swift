import Foundation
import Testing
@testable import EnzoApp

// MARK: - FitnessSnapshotRow unit tests

@Suite("FitnessSnapshotRow")
struct FitnessSnapshotRowTests {

    @Test("encodes to snake_case column names")
    func codingKeysAreSnakeCase() throws {
        let snapshot = FitnessSnapshot(month: "2025-08", label: "Epic", value: 1.0, hours: 30.4, rides: 13, trend: "up")
        let row = FitnessSnapshotRow(snapshot: snapshot)
        let data = try JSONEncoder().encode(row)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["fitness_label"] as? String == "Epic")
        #expect(json["fitness_value"] as? Double == 1.0)
        #expect(json["hours_ridden"] as? Double == 30.4)
        #expect(json["activity_count"] as? Int == 13)
        #expect(json["trend_direction"] as? String == "up")
        #expect(json["month"] as? String == "2025-08-01")
    }

    @Test("month converts yyyy-MM to yyyy-MM-01 for legacy Postgres format")
    func monthConversion() {
        let snapshot = FitnessSnapshot(month: "2026-03", label: "Recovering", value: 0.18, hours: 6.4, rides: 6, trend: "up")
        let row = FitnessSnapshotRow(snapshot: snapshot)
        #expect(row.month == "2026-03-01")
    }

    @Test("toSnapshot() restores all domain model fields")
    func roundTripDomainConversion() {
        let original = FitnessSnapshot(month: "2025-08", label: "Epic", value: 1.0, hours: 30.4, rides: 13, trend: "up")
        let row = FitnessSnapshotRow(snapshot: original)
        let restored = row.toSnapshot()

        #expect(restored.month == original.month)
        #expect(restored.label == original.label)
        #expect(restored.value == original.value)
        #expect(restored.hours == original.hours)
        #expect(restored.rides == original.rides)
        #expect(restored.trend == original.trend)
    }

    @Test("toSnapshot() trims date suffix from month column")
    func toSnapshotTrimsSuffix() {
        var row = FitnessSnapshotRow(snapshot: FitnessSnapshot(month: "2025-04", label: "Strong", value: 0.72, hours: 22.1, rides: 8, trend: "up"))
        row.month = "2025-04-01"
        let snapshot = row.toSnapshot()
        #expect(snapshot.month == "2025-04")
    }

    @Test("monthDate parses yyyy-MM-dd string to UTC Date")
    func monthDateParsing() {
        let row = FitnessSnapshotRow(snapshot: FitnessSnapshot(month: "2025-08", label: "Epic", value: 1.0, hours: 30.4, rides: 13, trend: "up"))
        #expect(row.month == "2025-08-01")
        #expect(row.monthDate != .distantPast)
    }
}

// MARK: - SegmentScoreRow unit tests

@Suite("SegmentScoreRow")
struct SegmentScoreRowTests {

    @Test("encodes to snake_case column names")
    func codingKeysAreSnakeCase() throws {
        let row = SegmentScoreRow(
            id: nil,
            userId: nil,
            stravaSegmentId: 12345,
            segmentName: "Hawk Hill",
            prSeconds: 342,
            prAchievedAt: "2025-08-10",
            fitnessValueAtPr: 0.98,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 401,
            lastEffortDate: nil,
            strikeScore: 0.18,
            strikeLabel: "Not quite ready"
        )
        let data = try JSONEncoder().encode(row)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["strava_segment_id"] as? Int == 12345)
        #expect(json["segment_name"] as? String == "Hawk Hill")
        #expect(json["pr_seconds"] as? Int == 342)
        #expect(json["fitness_value_at_pr"] as? Double == 0.98)
        #expect(json["strike_label"] as? String == "Not quite ready")
    }

    @Test("toSegmentScore() produces valid domain model")
    func toDomainConversion() {
        let row = SegmentScoreRow(
            id: nil,
            userId: nil,
            stravaSegmentId: 12345,
            segmentName: "Hawk Hill",
            prSeconds: 342,
            prAchievedAt: "2025-08-10",
            fitnessValueAtPr: 0.98,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 401,
            lastEffortDate: nil,
            strikeScore: 0.18,
            strikeLabel: "Not quite ready"
        )
        let segment = row.toSegmentScore()

        #expect(segment.name == "Hawk Hill")
        #expect(segment.prSeconds == 342)
        #expect(segment.strikeLabel == "Not quite ready")
        #expect(segment.fitnessValueAtPR == 0.98)
    }
}

// MARK: - GoalRow unit tests

@Suite("GoalRow")
struct GoalRowTests {

    @Test("encodes to snake_case column names")
    func codingKeysAreSnakeCase() throws {
        let row = GoalRow(
            id: nil,
            userId: nil,
            rawDescription: "PR Hawk Hill",
            claudeInterpretation: nil,
            goalType: "segment_pr",
            targetSegmentId: nil,
            targetSegmentName: "Hawk Hill",
            targetDate: nil,
            targetValue: nil,
            requiredFitnessLabel: "Strong",
            requiredFitnessValue: 0.70,
            isActive: true
        )
        let data = try JSONEncoder().encode(row)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["raw_description"] as? String == "PR Hawk Hill")
        #expect(json["goal_type"] as? String == "segment_pr")
        #expect(json["target_segment_name"] as? String == "Hawk Hill")
        #expect(json["required_fitness_label"] as? String == "Strong")
        #expect(json["required_fitness_value"] as? Double == 0.70)
        #expect(json["is_active"] as? Bool == true)
    }
}
