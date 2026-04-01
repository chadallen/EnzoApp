import Foundation

/// Pure static functions for computing segment strike scores.
/// No network, no state — all inputs explicit, all outputs deterministic.
///
/// - Note: The 100-activity limit in Phase 2 sync is a placeholder for the proof of concept.
///   Production will require proper rate-limit batching across the full activity history.
enum SegmentScorer {

    // MARK: - Constants

    static let strikeNowThreshold: Double = 0.80
    static let almostThereThreshold: Double = 0.65
    static let worthAShotThreshold: Double = 0.45
    static let gettingThereThreshold: Double = 0.25

    // MARK: - Strike score (0.0–1.0)

    /// Computes how ready the athlete is to beat their PR on a given segment.
    ///
    /// Formula:
    /// 1. base = clamp(0.75 + fitnessDelta, 0, 1)
    ///    — at parity (delta=0) → 0.75 baseline
    ///    — well above PR fitness → approaches 1.0
    ///    — well below PR fitness → approaches 0.0
    /// 2. prAgeBonus: up to +0.15 for PRs set 3+ years ago (linear, fully continuous)
    /// 3. effortGapModifier: −0.20 to +0.10 based on how close last effort was to PR pace
    ///
    /// - Parameters:
    ///   - fitnessValueAtPR: Athlete's fitness (0.0–1.0) when PR was set.
    ///   - currentFitnessValue: Athlete's current fitness (0.0–1.0).
    ///   - prDate: Date PR was set ("yyyy-MM-dd") — used for age bonus.
    ///   - lastEffortSeconds: Most recent elapsed time on this segment.
    ///   - prSeconds: PR elapsed time on this segment.
    /// - Returns: Strike score clamped to 0.0–1.0.
    static func strikeScore(
        fitnessValueAtPR: Double,
        currentFitnessValue: Double,
        prDate: String,
        lastEffortSeconds: Int,
        prSeconds: Int
    ) -> Double {
        let delta = currentFitnessValue - fitnessValueAtPR
        let base = min(max(0.75 + delta, 0), 1)

        // Option B: PR age bonus — older PRs are more beatable as fitness evolves.
        // Scales linearly from 0 (set today) to +0.15 (set 3+ years ago).
        let prAgeBonus: Double
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let prParsedDate = formatter.date(from: prDate) {
            let daysSincePR = Calendar.current.dateComponents([.day], from: prParsedDate, to: Date()).day ?? 0
            prAgeBonus = min(Double(max(daysSincePR, 0)) / 1095.0, 1.0) * 0.15
        } else {
            prAgeBonus = 0
        }

        // Option C: effort gap modifier — how close to PR pace on most recent ride.
        // Negative ratio (slower than PR) reduces score; positive (faster) adds up to +0.10.
        let effortGapModifier: Double
        if prSeconds > 0 {
            let gapRatio = Double(lastEffortSeconds - prSeconds) / Double(prSeconds)
            effortGapModifier = min(max(-gapRatio * 0.5, -0.20), 0.10)
        } else {
            effortGapModifier = 0
        }

        return min(max(base + prAgeBonus + effortGapModifier, 0), 1)
    }

    // MARK: - Strike label

    /// Maps a strike score to a user-facing readiness label.
    static func strikeLabel(for score: Double) -> String {
        switch score {
        case strikeNowThreshold...:                          return "Strike now"
        case almostThereThreshold..<strikeNowThreshold:     return "Almost there"
        case worthAShotThreshold..<almostThereThreshold:    return "Worth a shot"
        case gettingThereThreshold..<worthAShotThreshold:   return "Getting there"
        default:                                             return "Build first"
        }
    }

    // MARK: - Required fitness label

    /// Returns the minimum fitness label the athlete needs to have a realistic
    /// shot at beating their PR. One tier below the label at which the PR was set.
    ///
    /// Rationale: you don't need to exactly match your peak to challenge a PR —
    /// being one tier below is close enough to make a run at it worthwhile.
    static func requiredFitnessLabel(fitnessValueAtPR: Double) -> String {
        let prLabel = FitnessCalculator.fitnessLabel(for: fitnessValueAtPR)
        switch prLabel {
        case "Epic":      return "Strong"
        case "Strong":    return "Building"
        case "Building":  return "Baseline"
        default:          return "Recovering"
        }
    }

}
