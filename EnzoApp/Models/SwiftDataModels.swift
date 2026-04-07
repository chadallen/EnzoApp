import Foundation
import SwiftData

// MARK: - FitnessSnapshotModel

@Model
final class FitnessSnapshotModel {
    /// First of month, UTC midnight — unique per user (single-user device, no user_id needed).
    @Attribute(.unique) var month: Date
    var fitnessValue: Double
    var fitnessLabel: String
    var trendDirection: String
    var hoursRidden: Double
    var activityCount: Int
    var avgEfficiency: Double

    init(month: Date, fitnessValue: Double, fitnessLabel: String,
         trendDirection: String, hoursRidden: Double,
         activityCount: Int, avgEfficiency: Double) {
        self.month = month
        self.fitnessValue = fitnessValue
        self.fitnessLabel = fitnessLabel
        self.trendDirection = trendDirection
        self.hoursRidden = hoursRidden
        self.activityCount = activityCount
        self.avgEfficiency = avgEfficiency
    }

    convenience init(from row: FitnessSnapshotRow) {
        self.init(
            month: row.monthDate,
            fitnessValue: row.fitnessValue,
            fitnessLabel: row.fitnessLabel,
            trendDirection: row.trendDirection,
            hoursRidden: row.hoursRidden ?? 0,
            activityCount: row.activityCount ?? 0,
            avgEfficiency: row.avgEfficiency ?? 0
        )
    }

    func toSnapshot() -> FitnessSnapshot {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "UTC")
        let monthStr = f.string(from: month)
        return FitnessSnapshot(
            month: monthStr,
            label: fitnessLabel,
            value: fitnessValue,
            hours: hoursRidden,
            rides: activityCount,
            trend: trendDirection
        )
    }
}

// MARK: - SegmentScoreModel

@Model
final class SegmentScoreModel {
    @Attribute(.unique) var stravaSegmentId: Int
    var segmentName: String
    var prSeconds: Int
    var prAchievedAt: String      // "YYYY-MM-DD" — kept as String for display convenience
    var fitnessValueAtPr: Double
    var currentFitnessValue: Double
    var trendDirection: String
    var lastEffortSeconds: Int
    var lastEffortDate: String    // "YYYY-MM-DD"
    var strikeScore: Double
    var strikeLabel: String
    var distanceMeters: Double
    var elevationDeltaMeters: Double

    init(stravaSegmentId: Int, segmentName: String, prSeconds: Int,
         prAchievedAt: String, fitnessValueAtPr: Double, currentFitnessValue: Double,
         trendDirection: String, lastEffortSeconds: Int, lastEffortDate: String,
         strikeScore: Double, strikeLabel: String, distanceMeters: Double,
         elevationDeltaMeters: Double) {
        self.stravaSegmentId = stravaSegmentId
        self.segmentName = segmentName
        self.prSeconds = prSeconds
        self.prAchievedAt = prAchievedAt
        self.fitnessValueAtPr = fitnessValueAtPr
        self.currentFitnessValue = currentFitnessValue
        self.trendDirection = trendDirection
        self.lastEffortSeconds = lastEffortSeconds
        self.lastEffortDate = lastEffortDate
        self.strikeScore = strikeScore
        self.strikeLabel = strikeLabel
        self.distanceMeters = distanceMeters
        self.elevationDeltaMeters = elevationDeltaMeters
    }

    convenience init(from row: SegmentScoreRow) {
        self.init(
            stravaSegmentId: Int(row.stravaSegmentId),
            segmentName: row.segmentName ?? "",
            prSeconds: row.prSeconds ?? 0,
            prAchievedAt: row.prAchievedAt ?? "",
            fitnessValueAtPr: row.fitnessValueAtPr ?? 0,
            currentFitnessValue: row.currentFitnessValue ?? 0,
            trendDirection: row.trendDirection ?? "flat",
            lastEffortSeconds: row.lastEffortSeconds ?? 0,
            lastEffortDate: row.lastEffortDate ?? "",
            strikeScore: row.strikeScore ?? 0,
            strikeLabel: row.strikeLabel ?? "",
            distanceMeters: row.distanceMeters ?? 0,
            elevationDeltaMeters: row.elevationDeltaMeters ?? 0
        )
    }

    func toSegmentScore() -> SegmentScore {
        SegmentScore(
            name: segmentName,
            prSeconds: prSeconds,
            prDate: prAchievedAt,
            fitnessValueAtPR: fitnessValueAtPr,
            currentFitnessValue: currentFitnessValue,
            trendDirection: trendDirection,
            lastEffortSeconds: lastEffortSeconds,
            strikeScore: strikeScore,
            strikeLabel: strikeLabel,
            distanceMeters: distanceMeters > 0 ? distanceMeters : nil,
            elevationDeltaMeters: elevationDeltaMeters != 0 ? elevationDeltaMeters : nil
        )
    }
}

// MARK: - GoalModel

@Model
final class GoalModel {
    var rawDescription: String
    var claudeInterpretation: String?
    var goalType: String
    var targetSegmentId: Int?
    var targetSegmentName: String
    var targetDate: Date?
    var targetValue: Double?
    var requiredFitnessLabel: String
    var requiredFitnessValue: Double
    var isActive: Bool
    var createdAt: Date

    init(rawDescription: String, goalType: String, targetSegmentName: String,
         targetDate: Date?, requiredFitnessLabel: String, requiredFitnessValue: Double,
         isActive: Bool) {
        self.rawDescription = rawDescription
        self.claudeInterpretation = nil
        self.goalType = goalType
        self.targetSegmentId = nil
        self.targetSegmentName = targetSegmentName
        self.targetDate = targetDate
        self.targetValue = nil
        self.requiredFitnessLabel = requiredFitnessLabel
        self.requiredFitnessValue = requiredFitnessValue
        self.isActive = isActive
        self.createdAt = Date()
    }

    /// Converts to GoalRow so AthleteContext.build() can remain unchanged.
    func toGoalRow() -> GoalRow {
        var targetDateStr: String? = nil
        if let date = targetDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            targetDateStr = f.string(from: date)
        }
        return GoalRow(
            id: nil,
            userId: nil,
            rawDescription: rawDescription,
            claudeInterpretation: claudeInterpretation,
            goalType: goalType,
            targetSegmentId: targetSegmentId.map { Int64($0) },
            targetSegmentName: targetSegmentName,
            targetDate: targetDateStr,
            targetValue: targetValue,
            requiredFitnessLabel: requiredFitnessLabel,
            requiredFitnessValue: requiredFitnessValue,
            isActive: isActive
        )
    }
}

// MARK: - Shared ModelContainer

extension ModelContainer {
    static let enzo: ModelContainer = {
        let schema = Schema([
            FitnessSnapshotModel.self,
            SegmentScoreModel.self,
            GoalModel.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()
}
