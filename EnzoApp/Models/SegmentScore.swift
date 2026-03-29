import Foundation

struct SegmentScore: Identifiable, Hashable {
    let name: String
    let prSeconds: Int
    let prDate: String        // "2025-08-10"
    let fitnessAtPR: Double
    let currentFitness: Double
    let strikeScore: Double
    var isGoalSegment: Bool = false

    var id: String { name }

    var prFormatted: String {
        let mins = prSeconds / 60
        let secs = prSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var strikeLabel: String {
        switch strikeScore {
        case 0.7...: return "Strike now"
        case 0.4..<0.7: return "Getting close"
        default: return "Not yet"
        }
    }

    var fitnessDelta: Double {
        currentFitness - fitnessAtPR
    }

    // MARK: - Hardcoded preview data (Section 18)

    static let previewSegments: [SegmentScore] = [
        SegmentScore(
            name: "Hawk Hill",
            prSeconds: 342,
            prDate: "2025-08-10",
            fitnessAtPR: 98,
            currentFitness: 20,
            strikeScore: 0.18,
            isGoalSegment: true
        ),
        SegmentScore(
            name: "Camino Alto Cutoff",
            prSeconds: 198,
            prDate: "2024-04-02",
            fitnessAtPR: 31,
            currentFitness: 20,
            strikeScore: 0.44
        ),
        SegmentScore(
            name: "Paradise Loop Climb",
            prSeconds: 534,
            prDate: "2025-04-15",
            fitnessAtPR: 72,
            currentFitness: 20,
            strikeScore: 0.22
        ),
        SegmentScore(
            name: "Pantoll to Rock Spring",
            prSeconds: 1147,
            prDate: "2024-10-05",
            fitnessAtPR: 24,
            currentFitness: 20,
            strikeScore: 0.48
        ),
        SegmentScore(
            name: "Bolinas Ridge Descent",
            prSeconds: 445,
            prDate: "2023-09-20",
            fitnessAtPR: 18,
            currentFitness: 20,
            strikeScore: 0.71
        ),
    ]
}
