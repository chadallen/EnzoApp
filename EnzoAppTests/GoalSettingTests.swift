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

@Suite("AppState.goalReactionPrompt")
struct GoalReactionPromptTests {

    @Test("prompt includes segment name")
    func promptIncludesSegmentName() {
        let segment = SegmentScore.previewSegments[0] // Hawk Hill
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: .preview)
        #expect(prompt.contains("Hawk Hill"))
    }

    @Test("prompt includes formatted PR time")
    func promptIncludesPRTime() {
        let segment = SegmentScore.previewSegments[0] // 5:42
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: .preview)
        #expect(prompt.contains(segment.prFormatted))
    }

    @Test("prompt includes fitness label at PR time")
    func promptIncludesFitnessAtPR() {
        let segment = SegmentScore.previewSegments[0] // fitnessValueAtPR: 0.98 → "Epic"
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: .preview)
        #expect(prompt.contains("Epic"))
    }

    @Test("prompt includes current fitness label")
    func promptIncludesCurrentFitness() {
        let segment = SegmentScore.previewSegments[0]
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: .preview)
        #expect(prompt.contains(AthleteContext.preview.currentFitnessLabel))
    }

    @Test("prompt includes trend direction")
    func promptIncludesTrend() {
        let segment = SegmentScore.previewSegments[0]
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: .preview)
        #expect(prompt.contains(AthleteContext.preview.trendDirection))
    }
}
