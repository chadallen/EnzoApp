import Testing
import Foundation
@testable import EnzoApp

@Suite("SegmentScorer")
struct SegmentScorerTests {

    // MARK: - Strike score edge cases

    // Shared helper: parity score with a known-old PR date and at-PR-pace last effort.
    // prDate "2020-01-01" is 5+ years old → full +0.15 age bonus. lastEffortSeconds == prSeconds → 0 gap modifier.
    private func parityScore(atPRFitness: Double = 0.50, currentFitness: Double = 0.50) -> Double {
        SegmentScorer.strikeScore(
            fitnessValueAtPR: atPRFitness,
            currentFitnessValue: currentFitness,
            prDate: "2020-01-01",
            lastEffortSeconds: 300,
            prSeconds: 300
        )
    }

    @Test("Score near 1.0 when current fitness far exceeds PR fitness")
    func highScoreWhenFitterThanPR() {
        let score = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.20,
            currentFitnessValue: 0.90,
            prDate: "2020-01-01",
            lastEffortSeconds: 300,
            prSeconds: 300
        )
        #expect(score >= 0.90)
    }

    @Test("Score near 0.0 when current fitness far below PR fitness")
    func lowScoreWhenLessFitThanPR() {
        let score = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.95,
            currentFitnessValue: 0.10,
            prDate: "2024-01-01",
            lastEffortSeconds: 300,
            prSeconds: 300
        )
        #expect(score <= 0.10)
    }

    @Test("Score is 0.75 at exact fitness parity with same-day PR and at-pace last effort")
    func parityBaselineIsSameDay() {
        // Same-day PR (age bonus ≈ 0), last effort at PR pace (gap modifier = 0) → exactly 0.75
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let score = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50,
            currentFitnessValue: 0.50,
            prDate: today,
            lastEffortSeconds: 300,
            prSeconds: 300
        )
        #expect(score >= 0.74 && score <= 0.76)
    }

    @Test("Score is always in 0.0–1.0 range")
    func scoreAlwaysInRange() {
        let cases: [(Double, Double)] = [
            (0.0, 0.0),
            (1.0, 1.0),
            (0.0, 1.0),
            (1.0, 0.0),
            (0.5, 0.5),
        ]
        for (atPR, current) in cases {
            let score = SegmentScorer.strikeScore(
                fitnessValueAtPR: atPR,
                currentFitnessValue: current,
                prDate: "2020-01-01",
                lastEffortSeconds: 300,
                prSeconds: 300
            )
            #expect(score >= 0.0)
            #expect(score <= 1.0)
        }
    }

    // MARK: - PR age bonus

    @Test("Old PR scores higher than recent PR at same fitness")
    func oldPRScoresHigher() {
        let old = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2020-01-01", lastEffortSeconds: 300, prSeconds: 300
        )
        let recent = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2025-01-01", lastEffortSeconds: 300, prSeconds: 300
        )
        #expect(old > recent)
    }

    @Test("PR age bonus caps at +0.15 for 3+ year old PRs")
    func prAgeBonusCaps() {
        let threeYears = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2022-01-01", lastEffortSeconds: 300, prSeconds: 300
        )
        let fiveYears = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2020-01-01", lastEffortSeconds: 300, prSeconds: 300
        )
        // Both should be at or near the cap — difference should be tiny
        #expect(abs(threeYears - fiveYears) < 0.02)
    }

    // MARK: - Effort gap modifier

    @Test("Slower last effort reduces score")
    func slowerEffortReducesScore() {
        let atPace = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2020-01-01", lastEffortSeconds: 300, prSeconds: 300
        )
        let slower = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2020-01-01", lastEffortSeconds: 360, prSeconds: 300  // 20% slower
        )
        #expect(slower < atPace)
    }

    @Test("Effort gap modifier caps at -0.20 for very slow efforts")
    func effortGapCapNegative() {
        let verySlow = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2020-01-01", lastEffortSeconds: 900, prSeconds: 300  // 3× slower
        )
        let extremelySlow = SegmentScorer.strikeScore(
            fitnessValueAtPR: 0.50, currentFitnessValue: 0.50,
            prDate: "2020-01-01", lastEffortSeconds: 1500, prSeconds: 300  // 5× slower
        )
        #expect(abs(verySlow - extremelySlow) < 0.02)
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
