import Foundation

/// Pure static functions for computing segment strike scores.
/// No network, no state — all inputs explicit, all outputs deterministic.
///
/// - Note: The 100-activity limit in Phase 2 sync is a placeholder for the proof of concept.
///   Production will require proper rate-limit batching across the full activity history.
enum SegmentScorer {

    // MARK: - Constants

    /// Strike score threshold for "No brainer" label.
    static let noBrainerThreshold: Double = 0.70

    /// Strike score threshold for "Worth a shot" label (lower bound).
    static let worthAShotThreshold: Double = 0.45

    // MARK: - Strike score (0.0–1.0)

    /// Computes how ready the athlete is to beat their PR on a given segment.
    ///
    /// Formula:
    /// 1. base = clamp(0.5 + fitnessDelta × 0.8, 0, 1)
    ///    — at parity (delta=0) → 0.5 "Worth a shot"
    ///    — well above PR fitness → approaches 1.0
    ///    — well below PR fitness → approaches 0.0
    /// 2. trendBonus: +0.05 for "up", -0.05 for "down"
    ///
    /// - Parameters:
    ///   - fitnessValueAtPR: Athlete's fitness (0.0–1.0) when PR was set.
    ///   - currentFitnessValue: Athlete's current fitness (0.0–1.0).
    ///   - trendDirection: "up", "flat", or "down".
    ///   - prDate: Unused — kept for call-site compatibility during transition.
    /// - Returns: Strike score clamped to 0.0–1.0.
    static func strikeScore(
        fitnessValueAtPR: Double,
        currentFitnessValue: Double,
        trendDirection: String,
        prDate: String
    ) -> Double {
        let delta = currentFitnessValue - fitnessValueAtPR
        var score = min(max(0.5 + delta * 0.8, 0), 1)

        switch trendDirection {
        case "up":   score += 0.05
        case "down": score -= 0.05
        default:     break
        }

        return min(max(score, 0), 1)
    }

    // MARK: - Strike label

    /// Maps a strike score to a user-facing readiness label.
    static func strikeLabel(for score: Double) -> String {
        switch score {
        case noBrainerThreshold...: return "No brainer"
        case worthAShotThreshold..<noBrainerThreshold: return "Worth a shot"
        default: return "Not quite ready"
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
