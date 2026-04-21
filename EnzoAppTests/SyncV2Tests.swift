import Testing
import Foundation
@testable import EnzoApp

// MARK: - SyncV2 pure-function tests
//
// Tests for the pure static helpers introduced in AppState for the v2 sync pipeline.
// Network-bound steps (fetchActivitiesV2, etc.) are not tested here — they require
// live credentials and are verified via manual QA or integration tests.

@Suite("AppState — strikeLabelV2")
struct StrikeLabelV2Tests {

    @Test("probability ≥ 0.80 → Strike now")
    func strikeNow() {
        #expect(AppState.strikeLabelV2(for: 0.80) == "Strike now")
        #expect(AppState.strikeLabelV2(for: 0.95) == "Strike now")
        #expect(AppState.strikeLabelV2(for: 1.00) == "Strike now")
    }

    @Test("0.65 ≤ probability < 0.80 → Almost there")
    func almostThere() {
        #expect(AppState.strikeLabelV2(for: 0.65) == "Almost there")
        #expect(AppState.strikeLabelV2(for: 0.75) == "Almost there")
        #expect(AppState.strikeLabelV2(for: 0.799) == "Almost there")
    }

    @Test("0.45 ≤ probability < 0.65 → Worth a shot")
    func worthAShot() {
        #expect(AppState.strikeLabelV2(for: 0.45) == "Worth a shot")
        #expect(AppState.strikeLabelV2(for: 0.55) == "Worth a shot")
        #expect(AppState.strikeLabelV2(for: 0.649) == "Worth a shot")
    }

    @Test("0.25 ≤ probability < 0.45 → Getting there")
    func gettingThere() {
        #expect(AppState.strikeLabelV2(for: 0.25) == "Getting there")
        #expect(AppState.strikeLabelV2(for: 0.35) == "Getting there")
        #expect(AppState.strikeLabelV2(for: 0.449) == "Getting there")
    }

    @Test("probability < 0.25 → Build first")
    func buildFirst() {
        #expect(AppState.strikeLabelV2(for: 0.00) == "Build first")
        #expect(AppState.strikeLabelV2(for: 0.10) == "Build first")
        #expect(AppState.strikeLabelV2(for: 0.249) == "Build first")
    }

    @Test("label thresholds are closed on left boundary")
    func leftBoundaries() {
        // Each threshold should produce the higher tier label exactly at the boundary.
        #expect(AppState.strikeLabelV2(for: 0.80) == "Strike now")
        #expect(AppState.strikeLabelV2(for: 0.65) == "Almost there")
        #expect(AppState.strikeLabelV2(for: 0.45) == "Worth a shot")
        #expect(AppState.strikeLabelV2(for: 0.25) == "Getting there")
    }
}
