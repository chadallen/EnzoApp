import Testing
@testable import EnzoApp

@Suite("SegmentScore.filter")
struct SegmentFilterTests {

    @Test("empty query returns all segments")
    func emptyQueryReturnsAll() {
        let result = SegmentScore.filter(SegmentScore.previewSegments, by: "")
        #expect(result.count == SegmentScore.previewSegments.count)
    }

    @Test("matching query returns correct segment")
    func queryMatchesByName() {
        let result = SegmentScore.filter(SegmentScore.previewSegments, by: "hawk")
        #expect(result.count == 1)
        #expect(result.first?.name == "Hawk Hill")
    }

    @Test("filter is case-insensitive")
    func filterCaseInsensitive() {
        let lower = SegmentScore.filter(SegmentScore.previewSegments, by: "camino")
        let upper = SegmentScore.filter(SegmentScore.previewSegments, by: "CAMINO")
        #expect(lower.count == upper.count)
        #expect(lower.first?.name == upper.first?.name)
    }

    @Test("non-matching query returns empty")
    func noMatchReturnsEmpty() {
        let result = SegmentScore.filter(SegmentScore.previewSegments, by: "zzz_no_match")
        #expect(result.isEmpty)
    }

    @Test("partial name match works")
    func partialMatchWorks() {
        let result = SegmentScore.filter(SegmentScore.previewSegments, by: "loop")
        #expect(result.contains(where: { $0.name == "Paradise Loop Climb" }))
    }
}
