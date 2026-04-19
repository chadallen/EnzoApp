import Testing
import SwiftUI
@testable import EnzoApp

@Suite("strikeColor")
struct StrikeScoreDonutTests {

    @Test("Score >= 0.80 maps to enzoGoal")
    func strikeNowColor() {
        #expect(strikeColor(for: 0.80) == .enzoGoal)
        #expect(strikeColor(for: 0.90) == .enzoGoal)
        #expect(strikeColor(for: 1.00) == .enzoGoal)
    }

    @Test("Score 0.65..<0.80 maps to enzoChartPrimary")
    func almostThereColor() {
        #expect(strikeColor(for: 0.65) == .enzoChartPrimary)
        #expect(strikeColor(for: 0.72) == .enzoChartPrimary)
        #expect(strikeColor(for: 0.799) == .enzoChartPrimary)
    }

    @Test("Score 0.45..<0.65 maps to enzoAmber")
    func worthAShotColor() {
        #expect(strikeColor(for: 0.45) == .enzoAmber)
        #expect(strikeColor(for: 0.55) == .enzoAmber)
        #expect(strikeColor(for: 0.649) == .enzoAmber)
    }

    @Test("Score < 0.45 maps to enzoSecondary")
    func lowerTierColor() {
        #expect(strikeColor(for: 0.00) == .enzoSecondary)
        #expect(strikeColor(for: 0.25) == .enzoSecondary)
        #expect(strikeColor(for: 0.449) == .enzoSecondary)
    }

    @Test("Boundary at 0.80 is enzoGoal, just below is enzoChartPrimary")
    func boundaryAt80() {
        #expect(strikeColor(for: 0.800) == .enzoGoal)
        #expect(strikeColor(for: 0.799) == .enzoChartPrimary)
    }

    @Test("Boundary at 0.65 is enzoChartPrimary, just below is enzoAmber")
    func boundaryAt65() {
        #expect(strikeColor(for: 0.650) == .enzoChartPrimary)
        #expect(strikeColor(for: 0.649) == .enzoAmber)
    }

    @Test("Boundary at 0.45 is enzoAmber, just below is enzoSecondary")
    func boundaryAt45() {
        #expect(strikeColor(for: 0.450) == .enzoAmber)
        #expect(strikeColor(for: 0.449) == .enzoSecondary)
    }
}
