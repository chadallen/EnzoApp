import Testing
import Foundation
@testable import EnzoApp

// MARK: - FindSegments pure-function tests
//
// Tests for AppState.buildSuggestedSegments — the pure algorithm that identifies
// frequently-ridden unstarred segments. No SwiftData required.

@Suite("AppState — buildSuggestedSegments")
struct FindSegmentsTests {

    // MARK: - Helpers

    private func seg(_ id: Int, name: String, starred: Bool) -> AppState.SegmentInput {
        AppState.SegmentInput(segmentId: id, name: name, isStarred: starred)
    }

    private func effort(_ segId: Int, time: Double) -> AppState.EffortInput {
        AppState.EffortInput(segmentId: segId, elapsedTime: time)
    }

    // MARK: - Basic inclusion

    @Test("Returns segments ridden 3 or more times that are not starred")
    func basicSuggestion() {
        let segments = [seg(1, name: "Hill Climb", starred: false)]
        let efforts = [
            effort(1, time: 300),
            effort(1, time: 290),
            effort(1, time: 310),
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.count == 1)
        #expect(result[0].name == "Hill Climb")
        #expect(result[0].effortCount == 3)
        #expect(result[0].bestTimeSeconds == 290)
    }

    // MARK: - Threshold filtering

    @Test("Excludes segments ridden fewer than 3 times")
    func belowThreshold() {
        let segments = [seg(1, name: "Short Segment", starred: false)]
        let efforts = [
            effort(1, time: 120),
            effort(1, time: 115),
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.isEmpty)
    }

    @Test("Includes segments ridden exactly 3 times")
    func exactlyAtThreshold() {
        let segments = [seg(1, name: "Threshold Segment", starred: false)]
        let efforts = [
            effort(1, time: 200),
            effort(1, time: 195),
            effort(1, time: 210),
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.count == 1)
    }

    // MARK: - Starred filtering

    @Test("Excludes starred segments even if ridden many times")
    func starredExcluded() {
        let segments = [seg(1, name: "Starred Segment", starred: true)]
        let efforts = [
            effort(1, time: 400),
            effort(1, time: 380),
            effort(1, time: 420),
            effort(1, time: 395),
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.isEmpty)
    }

    @Test("Correctly separates starred and unstarred when both are present")
    func mixedStarredAndUnstarred() {
        let segments = [
            seg(1, name: "Starred Seg", starred: true),
            seg(2, name: "Unstarred Seg", starred: false),
        ]
        let efforts = [
            effort(1, time: 300), effort(1, time: 310), effort(1, time: 305),  // starred — excluded
            effort(2, time: 200), effort(2, time: 195), effort(2, time: 210),  // unstarred — included
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.count == 1)
        #expect(result[0].segmentId == 2)
    }

    // MARK: - Name lookup

    @Test("Skips segments with no matching StarredSegmentModel (no name available)")
    func orphanEffortSkipped() {
        let segments: [AppState.SegmentInput] = []  // no segment models at all
        let efforts = [
            effort(99, time: 100), effort(99, time: 110), effort(99, time: 105),
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.isEmpty)
    }

    // MARK: - Best time

    @Test("bestTimeSeconds is the minimum elapsed time, rounded to nearest second")
    func bestTimeIsMinimum() {
        let segments = [seg(1, name: "Seg", starred: false)]
        let efforts = [
            effort(1, time: 300.7),
            effort(1, time: 289.4),
            effort(1, time: 310.0),
        ]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result[0].bestTimeSeconds == 289)  // 289.4 rounds to 289
    }

    // MARK: - Sorting

    @Test("Results are sorted by effortCount descending")
    func sortedByEffortCountDescending() {
        let segments = [
            seg(1, name: "Seg A", starred: false),  // 3 efforts
            seg(2, name: "Seg B", starred: false),  // 5 efforts
            seg(3, name: "Seg C", starred: false),  // 4 efforts
        ]
        var efforts: [AppState.EffortInput] = []
        for _ in 0..<3 { efforts.append(effort(1, time: 300)) }
        for _ in 0..<5 { efforts.append(effort(2, time: 200)) }
        for _ in 0..<4 { efforts.append(effort(3, time: 250)) }

        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: efforts)
        #expect(result.count == 3)
        #expect(result[0].segmentId == 2)  // 5 efforts
        #expect(result[1].segmentId == 3)  // 4 efforts
        #expect(result[2].segmentId == 1)  // 3 efforts
    }

    // MARK: - Empty inputs

    @Test("Returns empty when no efforts exist")
    func noEfforts() {
        let segments = [seg(1, name: "Seg", starred: false)]
        let result = AppState.buildSuggestedSegments(segmentModels: segments, effortRecords: [])
        #expect(result.isEmpty)
    }

    @Test("Returns empty when no segment models exist")
    func noSegmentModels() {
        let efforts = [effort(1, time: 100), effort(1, time: 110), effort(1, time: 120)]
        let result = AppState.buildSuggestedSegments(segmentModels: [], effortRecords: efforts)
        #expect(result.isEmpty)
    }
}
