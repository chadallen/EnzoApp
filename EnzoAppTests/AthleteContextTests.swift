import Testing
import Foundation
@testable import EnzoApp

@Suite("AthleteContext")
struct AthleteContextTests {

    // MARK: - fitnessLabel(for:)

    @Test("fitnessLabel returns correct string for each band")
    func fitnessLabelBands() {
        #expect(AthleteContext.fitnessLabel(for: 1.00) == "Epic")
        #expect(AthleteContext.fitnessLabel(for: 0.85) == "Epic")
        #expect(AthleteContext.fitnessLabel(for: 0.84) == "Strong")
        #expect(AthleteContext.fitnessLabel(for: 0.65) == "Strong")
        #expect(AthleteContext.fitnessLabel(for: 0.64) == "Building")
        #expect(AthleteContext.fitnessLabel(for: 0.45) == "Building")
        #expect(AthleteContext.fitnessLabel(for: 0.44) == "Baseline")
        #expect(AthleteContext.fitnessLabel(for: 0.25) == "Baseline")
        #expect(AthleteContext.fitnessLabel(for: 0.24) == "Recovering")
        #expect(AthleteContext.fitnessLabel(for: 0.00) == "Recovering")
    }

    // MARK: - build(name:snapshots:lastActivityDate:)

    private static let sampleSnapshots: [FitnessSnapshot] = [
        FitnessSnapshot(month: "2024-01", label: "Baseline",  value: 0.30, hours: 10, rides: 5,  trend: "flat"),
        FitnessSnapshot(month: "2024-06", label: "Strong",    value: 0.70, hours: 20, rides: 10, trend: "up"),
        FitnessSnapshot(month: "2024-08", label: "Epic",      value: 0.90, hours: 30, rides: 14, trend: "up"),
        FitnessSnapshot(month: "2025-01", label: "Building",  value: 0.55, hours: 15, rides: 8,  trend: "flat"),
        FitnessSnapshot(month: "2025-06", label: "Baseline",  value: 0.35, hours: 12, rides: 6,  trend: "down"),
    ]

    @Test("build uses most recent snapshot for current fitness")
    func buildCurrentFitness() {
        let ctx = AthleteContext.build(
            name: "Chad",
            snapshots: Self.sampleSnapshots,
            lastActivityDate: nil
        )
        #expect(ctx.currentFitnessLabel == "Baseline")
        #expect(abs(ctx.currentFitnessValue - 0.35) < 0.001)
        #expect(ctx.trendDirection == "down")
    }

    @Test("build identifies peak fitness snapshot")
    func buildPeakFitness() {
        let ctx = AthleteContext.build(
            name: "Chad",
            snapshots: Self.sampleSnapshots,
            lastActivityDate: nil
        )
        #expect(ctx.peakFitnessLabel == "Epic")
        #expect(ctx.peakFitnessMonth.contains("2024"))
    }

    @Test("build sums totalActivities from all snapshots")
    func buildTotalActivities() {
        let ctx = AthleteContext.build(
            name: "Chad",
            snapshots: Self.sampleSnapshots,
            lastActivityDate: nil
        )
        #expect(ctx.totalActivities == 5 + 10 + 14 + 8 + 6)   // 43
    }

    @Test("build computes days_since_last_ride from lastActivityDate")
    func buildDaysSinceLastRide() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let ctx = AthleteContext.build(
            name: "Chad",
            snapshots: Self.sampleSnapshots,
            lastActivityDate: threeDaysAgo
        )
        #expect(ctx.daysSinceLastRide >= 3)
        #expect(ctx.daysSinceLastRide <= 4)   // allow for rounding
    }

    @Test("build returns 0 days_since_last_ride when lastActivityDate is nil")
    func buildDaysSinceNil() {
        let ctx = AthleteContext.build(
            name: "Chad",
            snapshots: Self.sampleSnapshots,
            lastActivityDate: nil
        )
        #expect(ctx.daysSinceLastRide == 0)
    }

    @Test("build with no snapshots returns safe defaults")
    func buildEmptySnapshots() {
        let ctx = AthleteContext.build(
            name: "Chad",
            snapshots: [],
            lastActivityDate: nil
        )
        #expect(ctx.currentFitnessLabel == "Recovering")
        #expect(ctx.currentFitnessValue == 0.0)
        #expect(ctx.totalActivities == 0)
    }

    // MARK: - contextPayload(snapshots:segments:)

    @Test("contextPayload produces valid JSON")
    func contextPayloadValidJSON() {
        let json = AthleteContext.preview.contextPayload(
            snapshots: FitnessSnapshot.previewSnapshots,
            segments: SegmentScore.previewSegments
        )
        let data = json.data(using: .utf8)
        #expect(data != nil)
        let parsed = (data != nil) ? (try? JSONSerialization.jsonObject(with: data!)) : nil
        #expect(parsed != nil)
    }

    @Test("contextPayload includes athlete name")
    func contextPayloadIncludesName() {
        let json = AthleteContext.preview.contextPayload(
            snapshots: FitnessSnapshot.previewSnapshots,
            segments: []
        )
        #expect(json.contains("\"Chad\""))
    }

    @Test("contextPayload fitness_history is chronologically ordered")
    func contextPayloadHistoryOrder() throws {
        let json = AthleteContext.preview.contextPayload(
            snapshots: FitnessSnapshot.previewSnapshots.shuffled(),
            segments: []
        )
        let data = try #require(json.data(using: .utf8))
        let raw = try JSONSerialization.jsonObject(with: data)
        let parsed = try #require(raw as? [String: Any])
        let history = try #require(parsed["fitness_history"] as? [[String: Any]])
        let months = history.compactMap { $0["month"] as? String }
        #expect(months == months.sorted())
    }

    @Test("contextPayload includes days_since_last_ride")
    func contextPayloadDaysSinceLastRide() {
        let json = AthleteContext.preview.contextPayload(
            snapshots: [],
            segments: []
        )
        #expect(json.contains("days_since_last_ride"))
    }

    @Test("contextPayload includes peak_fitness when snapshots are non-empty")
    func contextPayloadPeakFitness() {
        let json = AthleteContext.preview.contextPayload(
            snapshots: FitnessSnapshot.previewSnapshots,
            segments: []
        )
        #expect(json.contains("peak_fitness"))
    }
}
