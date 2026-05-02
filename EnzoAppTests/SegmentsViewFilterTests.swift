import Testing
import Foundation
@testable import EnzoApp

// MARK: - Helpers

private func makeSegment(
    name: String,
    isStarred: Bool,
    strikeLabel: String = "Worth a shot",
    strikeScore: Double = 0.5,
    prProbability: Double? = 0.5,
    prDate: String = "2025-01-01"
) -> SegmentScore {
    var s = SegmentScore(
        name: name,
        prSeconds: 300,
        prDate: prDate,
        fitnessValueAtPR: 0.5,
        currentFitnessValue: 0.5,
        trendDirection: "flat",
        lastEffortSeconds: 310,
        strikeScore: strikeScore,
        strikeLabel: strikeLabel
    )
    s.isStarred = isStarred
    s.prProbability = prProbability
    return s
}

@Suite("SegmentsView — starred filter")
struct SegmentsViewFilterTests {

    // MARK: - sortedSegments logic (starred-only base)

    @Test("Only starred segments pass the isStarred filter")
    func starredFilterExcludesUnstarred() {
        let segments = [
            makeSegment(name: "Starred A", isStarred: true),
            makeSegment(name: "Unstarred B", isStarred: false),
            makeSegment(name: "Starred C", isStarred: true),
        ]
        let result = segments.filter { $0.isStarred }
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.isStarred })
        #expect(!result.contains(where: { $0.name == "Unstarred B" }))
    }

    @Test("Starred filter on empty list returns empty")
    func starredFilterEmptyList() {
        let segments: [SegmentScore] = []
        let result = segments.filter { $0.isStarred }
        #expect(result.isEmpty)
    }

    @Test("Starred filter when no segments are starred returns empty")
    func starredFilterNoneStarred() {
        let segments = [
            makeSegment(name: "A", isStarred: false),
            makeSegment(name: "B", isStarred: false),
        ]
        let result = segments.filter { $0.isStarred }
        #expect(result.isEmpty)
    }

    @Test("Starred filter when all segments are starred returns all")
    func starredFilterAllStarred() {
        let segments = [
            makeSegment(name: "A", isStarred: true),
            makeSegment(name: "B", isStarred: true),
            makeSegment(name: "C", isStarred: true),
        ]
        let result = segments.filter { $0.isStarred }
        #expect(result.count == 3)
    }

    // MARK: - filteredSegments logic (starred + search)

    @Test("Search only finds matches within starred segments")
    func searchWithinStarredOnly() {
        let segments = [
            makeSegment(name: "Hawk Hill", isStarred: true),
            makeSegment(name: "Hawk Descent", isStarred: false),   // unstarred — must not appear
            makeSegment(name: "Camino Alto", isStarred: true),
        ]
        let starred = segments.filter { $0.isStarred }
        let result = SegmentScore.filter(starred, by: "Hawk")
        #expect(result.count == 1)
        #expect(result[0].name == "Hawk Hill")
    }

    @Test("Search returns all starred segments when query is empty")
    func emptyQueryReturnsAllStarred() {
        let segments = [
            makeSegment(name: "A", isStarred: true),
            makeSegment(name: "B", isStarred: false),
            makeSegment(name: "C", isStarred: true),
        ]
        let starred = segments.filter { $0.isStarred }
        let result = SegmentScore.filter(starred, by: "")
        #expect(result.count == 2)
    }

    @Test("Search is case-insensitive within starred segments")
    func searchCaseInsensitiveWithinStarred() {
        let segments = [
            makeSegment(name: "Pantoll Climb", isStarred: true),
            makeSegment(name: "pantoll descent", isStarred: true),
            makeSegment(name: "Pantoll Fire Road", isStarred: false),
        ]
        let starred = segments.filter { $0.isStarred }
        let result = SegmentScore.filter(starred, by: "pantoll")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.name.localizedCaseInsensitiveContains("pantoll") })
    }

    @Test("Search returns empty when no starred segments match query")
    func searchNoStarredMatchesReturnsEmpty() {
        let segments = [
            makeSegment(name: "Hawk Hill", isStarred: true),
            makeSegment(name: "Bolinas Ridge", isStarred: false), // would match but unstarred
        ]
        let starred = segments.filter { $0.isStarred }
        let result = SegmentScore.filter(starred, by: "Bolinas")
        #expect(result.isEmpty)
    }

    // MARK: - Sort stability within starred set

    @Test("PR probability sort orders starred segments highest first")
    func prProbabilitySortWithinStarred() {
        let segments = [
            makeSegment(name: "Low", isStarred: true, prProbability: 0.2),
            makeSegment(name: "High", isStarred: true, prProbability: 0.9),
            makeSegment(name: "Mid", isStarred: true, prProbability: 0.5),
        ]
        let starred = segments.filter { $0.isStarred }
        let sorted = starred.sorted { ($0.prProbability ?? $0.strikeScore) > ($1.prProbability ?? $1.strikeScore) }
        #expect(sorted[0].name == "High")
        #expect(sorted[1].name == "Mid")
        #expect(sorted[2].name == "Low")
    }
}
