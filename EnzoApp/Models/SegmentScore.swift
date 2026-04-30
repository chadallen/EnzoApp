import Foundation

/// A single past effort on a segment. Stored as JSON on SegmentEffortModel records.
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
    let strikeLabel: String      // "Strike now", "Almost there", "Worth a shot", "Getting there", "Build first"
    var isGoalSegment: Bool = false
    var isStarred: Bool = false
    var distanceMeters: Double? = nil
    var elevationDeltaMeters: Double? = nil
    var effortsJSON: String = "[]"

    // MARK: - v2 prediction fields (populated from PRPredictor after syncV2)

    /// PR probability 0.0–1.0. nil when the model could not be fit (isValid == false).
    var prProbability: Double? = nil
    /// Model's predicted elapsed time in seconds at today's CTL/TSB. nil when invalid.
    var predictedTime: Double? = nil
    /// One-sigma residual spread in seconds (used to compute ±1σ range). nil when invalid.
    var predictionSigma: Double? = nil
    /// True when today's CTL or TSB is outside the training data range used to fit the model.
    var isExtrapolating: Bool = false
    /// Human-readable naive fallback string. Always populated regardless of model validity.
    /// Format: "PR set when CTL was 52. Your current CTL is 61."
    var naiveFallback: String? = nil
    /// Number of efforts used to fit the regression model.
    var nEfforts: Int = 0

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
        {
            var s = SegmentScore(
                name: "Hawk Hill",
                prSeconds: 342,
                prDate: "2025-08-10",
                fitnessValueAtPR: 0.98,
                currentFitnessValue: 0.18,
                trendDirection: "up",
                lastEffortSeconds: 401,
                strikeScore: 0.18,
                strikeLabel: "Build first",
                isGoalSegment: true,
                distanceMeters: 2736,
                elevationDeltaMeters: 101,
                effortsJSON: #"[{"date":"2026-03-15","seconds":401},{"date":"2025-12-02","seconds":389},{"date":"2025-08-10","seconds":342},{"date":"2025-06-04","seconds":371}]"#
            )
            s.prProbability = 0.18
            s.predictedTime = 395.0
            s.predictionSigma = 22.0
            s.isExtrapolating = false
            s.naiveFallback = "PR set when CTL was 84. Your current CTL is 31."
            s.nEfforts = 4
            return s
        }(),
        {
            var s = SegmentScore(
                name: "Camino Alto Cutoff",
                prSeconds: 198,
                prDate: "2024-04-02",
                fitnessValueAtPR: 0.31,
                currentFitnessValue: 0.42,
                trendDirection: "up",
                lastEffortSeconds: 221,
                strikeScore: 0.48,
                strikeLabel: "Worth a shot"
            )
            s.prProbability = 0.48
            s.predictedTime = 210.0
            s.predictionSigma = 14.0
            s.isExtrapolating = false
            s.naiveFallback = "PR set when CTL was 28. Your current CTL is 38."
            s.nEfforts = 6
            return s
        }(),
        {
            var s = SegmentScore(
                name: "Paradise Loop Climb",
                prSeconds: 534,
                prDate: "2025-04-15",
                fitnessValueAtPR: 0.72,
                currentFitnessValue: 0.42,
                trendDirection: "up",
                lastEffortSeconds: 598,
                strikeScore: 0.22,
                strikeLabel: "Build first"
            )
            s.prProbability = nil    // invalid model — not enough varied fitness data
            s.predictedTime = nil
            s.predictionSigma = nil
            s.isExtrapolating = false
            s.naiveFallback = "PR set when CTL was 67. Your current CTL is 38."
            s.nEfforts = 2
            return s
        }(),
        {
            var s = SegmentScore(
                name: "Pantoll to Rock Spring",
                prSeconds: 1147,
                prDate: "2024-10-05",
                fitnessValueAtPR: 0.24,
                currentFitnessValue: 0.42,
                trendDirection: "up",
                lastEffortSeconds: 1198,
                strikeScore: 0.73,
                strikeLabel: "Almost there"
            )
            s.prProbability = 0.73
            s.predictedTime = 1162.0
            s.predictionSigma = 18.0
            s.isExtrapolating = true
            s.naiveFallback = "PR set when CTL was 22. Your current CTL is 38."
            s.nEfforts = 5
            return s
        }(),
        {
            var s = SegmentScore(
                name: "Bolinas Ridge descent",
                prSeconds: 445,
                prDate: "2023-09-20",
                fitnessValueAtPR: 0.18,
                currentFitnessValue: 0.42,
                trendDirection: "up",
                lastEffortSeconds: 461,
                strikeScore: 0.84,
                strikeLabel: "Strike now"
            )
            s.prProbability = 0.84
            s.predictedTime = 438.0
            s.predictionSigma = 12.0
            s.isExtrapolating = false
            s.naiveFallback = "PR set when CTL was 15. Your current CTL is 38."
            s.nEfforts = 8
            return s
        }(),
    ]
}
