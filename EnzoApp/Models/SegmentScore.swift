import Foundation

struct SegmentScore: Identifiable, Hashable {
    let name: String
    let prSeconds: Int
    let prDate: String           // "2025-08-10"
    let fitnessValueAtPR: Double // 0.0–1.0
    let currentFitnessValue: Double // 0.0–1.0
    let trendDirection: String   // "up", "flat", "down"
    let lastEffortSeconds: Int
    let strikeScore: Double      // 0.0–1.0
    let strikeLabel: String      // "No brainer", "Worth a shot", "Not quite ready"
    var isGoalSegment: Bool = false

    var id: String { name }

    var prFormatted: String {
        let mins = prSeconds / 60
        let secs = prSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var fitnessDelta: Double {
        currentFitnessValue - fitnessValueAtPR
    }

    // MARK: - Hardcoded preview data (Section 18)

    static let previewSegments: [SegmentScore] = [
        SegmentScore(
            name: "Hawk Hill",
            prSeconds: 342,
            prDate: "2025-08-10",
            fitnessValueAtPR: 0.98,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 401,
            strikeScore: 0.18,
            strikeLabel: "Not quite ready",
            isGoalSegment: true
        ),
        SegmentScore(
            name: "Camino Alto Cutoff",
            prSeconds: 198,
            prDate: "2024-04-02",
            fitnessValueAtPR: 0.31,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 221,
            strikeScore: 0.48,
            strikeLabel: "Worth a shot"
        ),
        SegmentScore(
            name: "Paradise Loop Climb",
            prSeconds: 534,
            prDate: "2025-04-15",
            fitnessValueAtPR: 0.72,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 598,
            strikeScore: 0.22,
            strikeLabel: "Not quite ready"
        ),
        SegmentScore(
            name: "Pantoll to Rock Spring",
            prSeconds: 1147,
            prDate: "2024-10-05",
            fitnessValueAtPR: 0.24,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 1198,
            strikeScore: 0.46,
            strikeLabel: "Worth a shot"
        ),
        SegmentScore(
            name: "Bolinas Ridge descent",
            prSeconds: 445,
            prDate: "2023-09-20",
            fitnessValueAtPR: 0.18,
            currentFitnessValue: 0.18,
            trendDirection: "up",
            lastEffortSeconds: 461,
            strikeScore: 0.52,
            strikeLabel: "Worth a shot"
        ),
    ]
}
