import Testing
import Foundation
@testable import EnzoApp

@Suite("EffortRecord")
struct EffortRecordTests {

    @Test("Encodes and decodes a non-empty array correctly")
    func jsonRoundTrip() throws {
        let records = [
            EffortRecord(date: "2025-04-01", seconds: 342),
            EffortRecord(date: "2025-03-15", seconds: 358),
        ]
        let data = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([EffortRecord].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].date == "2025-04-01")
        #expect(decoded[0].seconds == 342)
        #expect(decoded[1].date == "2025-03-15")
        #expect(decoded[1].seconds == 358)
    }

    @Test("Empty array round-trips to empty array")
    func emptyRoundTrip() throws {
        let records: [EffortRecord] = []
        let data = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([EffortRecord].self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test("SegmentScore.efforts returns empty for malformed JSON")
    func malformedJSONReturnsEmpty() {
        var score = SegmentScore.previewSegments[1]  // Camino Alto — no effortsJSON set
        score.effortsJSON = "not valid json {{{"
        #expect(score.efforts.isEmpty)
    }

    @Test("SegmentScore.efforts returns empty for default empty array")
    func defaultJSONReturnsEmpty() {
        var score = SegmentScore.previewSegments[1]
        score.effortsJSON = "[]"
        #expect(score.efforts.isEmpty)
    }

    @Test("SegmentScore.efforts decodes the preview segment's efforts")
    func previewSegmentEfforts() {
        let score = SegmentScore.previewSegments[0]  // Hawk Hill with 4 efforts
        #expect(score.efforts.count == 4)
        #expect(score.efforts[0].date == "2026-03-15")  // newest first
        #expect(score.efforts[2].seconds == 342)        // PR effort
    }

    @Test("PR effort identified by matching seconds to prSeconds")
    func prEffortIdentification() {
        let score = SegmentScore.previewSegments[0]  // prSeconds = 342
        let prEffort = score.efforts.first(where: { $0.seconds == score.prSeconds })
        #expect(prEffort != nil)
        #expect(prEffort?.date == "2025-08-10")
    }
}
