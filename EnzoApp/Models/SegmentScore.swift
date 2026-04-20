import Foundation

/// A single past effort on a segment. Stored as JSON in SegmentScoreModel.effortsJSON.
/// Reverse-chronological order (newest first). Capped at 20 per segment during sync.
struct EffortRecord: Codable, Identifiable {
    let date: String    // "yyyy-MM-dd"
    let seconds: Int

    var id: String { "\(date)-\(seconds)" }
}

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
    var distanceMeters: Double? = nil
    var elevationDeltaMeters: Double? = nil
    var effortsJSON: String = "[]"

    var id: String { name }

    /// Decoded effort history, newest first. Empty if no data or malformed JSON.
    var efforts: [EffortRecord] {
        guard let data = effortsJSON.data(using: .utf8),
              let records = try? JSONDecoder().decode([EffortRecord].self, from: data)
        else { return [] }
        return records
    }

    var prFormatted: String {
        let mins = prSeconds / 60
        let secs = prSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var fitnessDelta: Double {
        currentFitnessValue - fitnessValueAtPR
    }

    // MARK: - Search filtering

    /// Case-insensitive substring filter on segment name. Empty query returns all.
    static func filter(_ segments: [SegmentScore], by query: String) -> [SegmentScore] {
        guard !query.isEmpty else { return segments }
        return segments.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Hardcoded preview data (Section 18)

    nonisolated(unsafe) static let previewSegments: [SegmentScore] = [
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
            isGoalSegment: true,
            distanceMeters: 2736,
            elevationDeltaMeters: 101,
            effortsJSON: #"[{"date":"2026-03-15","seconds":401},{"date":"2025-12-02","seconds":389},{"date":"2025-08-10","seconds":342},{"date":"2025-06-04","seconds":371}]"#
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
