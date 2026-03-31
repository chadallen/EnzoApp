import Testing
import Foundation
@testable import EnzoApp

@Suite("SegmentScorer")
struct SegmentScorerTests {

    // MARK: - Strike score edge cases

    @Test("Score near 1.0 when current fitness far exceeds PR fitness")
    func highScoreWhenFitterThanPR() {
        let score = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.20,
            currentFitnessValue: 0.90,
            trendDirection: "flat",
            prDate: "2020-01-01"
        )
        #expect(score >= 0.90)
    }

    @Test("Score near 0.0 when current fitness far below PR fitness")
    func lowScoreWhenLessFitThanPR() {
        let score = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.95,
            currentFitnessValue: 0.10,
            trendDirection: "flat",
            prDate: "2020-01-01"
        )
        #expect(score <= 0.10)
    }

    @Test("Score is 0.75 at exact fitness parity with flat trend")
    func parityScoreIsSeventyFive() {
        let score = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50,
            currentFitnessValue: 0.50,
            trendDirection: "flat",
            prDate: "2020-01-01"
        )
        #expect(score == 0.75)
    }

    @Test("Score is always in 0.0–1.0 range")
    func scoreAlwaysInRange() {
        let cases: [(Double, Double, String)] = [
            (0.0, 0.0, "flat"),
            (1.0, 1.0, "up"),
            (0.0, 1.0, "up"),
            (1.0, 0.0, "down"),
            (0.5, 0.5, "flat"),
        ]
        for (atPR, current, trend) in cases {
            let score = SegmentScorer.strikeScore(
                fitnessValueAtPR: atPR,
                currentFitnessValue: current,
                trendDirection: trend,
                prDate: "2020-01-01"
            )
            #expect(score >= 0.0)
            #expect(score <= 1.0)
        }
    }

    // MARK: - Trend modifier

    @Test("Upward trend increases score vs flat")
    func upTrendIncreasesScore() {
        let flat = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            trendDirection: "flat", prDate: "2020-01-01"
        )
        let up = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            trendDirection: "up", prDate: "2020-01-01"
        )
        #expect(up > flat)
    }

    @Test("Downward trend decreases score vs flat")
    func downTrendDecreasesScore() {
        let flat = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            trendDirection: "flat", prDate: "2020-01-01"
        )
        let down = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            trendDirection: "down", prDate: "2020-01-01"
        )
        #expect(down < flat)
    }

    // MARK: - Strike label

    @Test("Strike now label for score >= 0.80")
    func strikeNowLabel() {
        #expect(SegmentScorer.strikeLabel(for: 0.80) == "Strike now")
        #expect(SegmentScorer.strikeLabel(for: 0.90) == "Strike now")
        #expect(SegmentScorer.strikeLabel(for: 1.00) == "Strike now")
    }

    @Test("Almost there label for score 0.65–0.80")
    func almostThereLabel() {
        #expect(SegmentScorer.strikeLabel(for: 0.65) == "Almost there")
        #expect(SegmentScorer.strikeLabel(for: 0.72) == "Almost there")
        #expect(SegmentScorer.strikeLabel(for: 0.799) == "Almost there")
    }

    @Test("Worth a shot label for score 0.45–0.65")
    func worthAShotLabel() {
        #expect(SegmentScorer.strikeLabel(for: 0.45) == "Worth a shot")
        #expect(SegmentScorer.strikeLabel(for: 0.55) == "Worth a shot")
        #expect(SegmentScorer.strikeLabel(for: 0.649) == "Worth a shot")
    }

    @Test("Getting there label for score 0.25–0.45")
    func gettingThereLabel() {
        #expect(SegmentScorer.strikeLabel(for: 0.25) == "Getting there")
        #expect(SegmentScorer.strikeLabel(for: 0.35) == "Getting there")
        #expect(SegmentScorer.strikeLabel(for: 0.449) == "Getting there")
    }

    @Test("Build first label for score < 0.25")
    func buildFirstLabel() {
        #expect(SegmentScorer.strikeLabel(for: 0.00) == "Build first")
        #expect(SegmentScorer.strikeLabel(for: 0.10) == "Build first")
        #expect(SegmentScorer.strikeLabel(for: 0.249) == "Build first")
    }

    // MARK: - Required fitness label

    @Test("Epic PR requires Strong fitness")
    func epicRequiresStrong() {
        // fitnessValueAtPR > 0.85 = Epic
        #expect(SegmentScorer.requiredFitnessLabel(fitnessValueAtPR: 0.90) == "Strong")
    }

    @Test("Strong PR requires Building fitness")
    func strongRequiresBuilding() {
        // 0.65–0.85 = Strong
        #expect(SegmentScorer.requiredFitnessLabel(fitnessValueAtPR: 0.75) == "Building")
    }

    @Test("Building PR requires Baseline fitness")
    func buildingRequiresBaseline() {
        // 0.45–0.65 = Building
        #expect(SegmentScorer.requiredFitnessLabel(fitnessValueAtPR: 0.55) == "Baseline")
    }

    @Test("Baseline PR requires Recovering fitness")
    func baselineRequiresRecovering() {
        // 0.25–0.45 = Baseline
        #expect(SegmentScorer.requiredFitnessLabel(fitnessValueAtPR: 0.35) == "Recovering")
    }

    @Test("Recovering PR requires Recovering fitness")
    func recoveringRequiresRecovering() {
        // < 0.25 = Recovering
        #expect(SegmentScorer.requiredFitnessLabel(fitnessValueAtPR: 0.10) == "Recovering")
    }
}
