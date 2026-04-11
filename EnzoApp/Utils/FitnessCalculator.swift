import Foundation

/// Pure static functions for computing fitness values from Strava ride data.
/// No network, no state — all inputs explicit, all outputs deterministic.
enum FitnessCalculator {

    // MARK: - Constants

    /// Minimum ride duration (minutes) to qualify for efficiency computation.
    nonisolated(unsafe) static let minimumDurationMinutes: Double = 30

    /// Cycling sport types accepted for fitness computation.
    nonisolated(unsafe) static let cyclingTypes: Set<String> = [
        "Ride", "VirtualRide", "MountainBikeRide", "GravelRide", "EMountainBikeRide"
    ]

    // MARK: - Per-ride efficiency

    /// Computes the cardiac efficiency for a single ride.
    ///
    /// Formula: `(distanceKm + elevationGainM * 0.01) / (durationHours * avgHR)`
    /// GravelRide gets a 1.15× adjusted-distance bonus.
    ///
    /// Returns `nil` if the ride is too short or has no valid HR.
    nonisolated static func efficiency(
        distanceKm: Double,
        elevationGainM: Double,
        sportType: String,
        durationHours: Double,
        avgHR: Int
    ) -> Double? {
        guard durationHours * 60 >= minimumDurationMinutes else { return nil }
        guard avgHR > 0 else { return nil }

        var adjustedDistance = distanceKm + (elevationGainM * 0.01)
        if sportType == "GravelRide" { adjustedDistance *= 1.15 }

        return adjustedDistance / (durationHours * Double(avgHR))
    }

    // MARK: - Percentile helper

    /// Returns the value at the given percentile (0–100) using linear interpolation.
    ///
    /// Used for normalization to avoid outlier months (illness, minimal riding) compressing
    /// the fitness scale. Pass the full set of all-time ride efficiencies.
    nonisolated static func percentile(_ p: Int, of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let index = Double(p) / 100.0 * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }

    // MARK: - Fitness value (0.0–1.0, internal only)

    /// Normalizes a 2-month rolling average efficiency to a 0.0–1.0 fitness value.
    ///
    /// - Parameters:
    ///   - recentEfficiencies: All qualifying ride efficiencies in the 2-month window.
    ///   - allTimeMin: Personal all-time minimum ride efficiency.
    ///   - allTimeMax: Personal all-time maximum ride efficiency.
    /// - Returns: Clamped fitness value 0.0–1.0. Returns 0 if empty, 0.5 if min == max.
    nonisolated static func fitnessValue(
        recentEfficiencies: [Double],
        allTimeMin: Double,
        allTimeMax: Double
    ) -> Double {
        guard !recentEfficiencies.isEmpty else { return 0 }
        guard allTimeMax > allTimeMin else { return 0.5 }
        let avg = recentEfficiencies.reduce(0, +) / Double(recentEfficiencies.count)
        return min(max((avg - allTimeMin) / (allTimeMax - allTimeMin), 0), 1)
    }

    // MARK: - Trend direction

    /// Minimum absolute efficiency change to register as a trend.
    /// Calibrated against real data (efficiency range ~0.10–0.28): ±0.008 ≈ 4–8% relative change.
    nonisolated(unsafe) static let trendThreshold: Double = 0.008

    /// Compares average efficiency in the most recent 4 weeks vs the prior 4 weeks.
    ///
    /// - Returns: `"up"` if change > trendThreshold, `"down"` if change < -trendThreshold, `"flat"` otherwise.
    nonisolated static func trendDirection(recentFourWeeks: Double, priorFourWeeks: Double) -> String {
        let change = recentFourWeeks - priorFourWeeks
        if change > trendThreshold { return "up" }
        if change < -trendThreshold { return "down" }
        return "flat"
    }

    // MARK: - User-facing fitness label

    /// Maps a 0.0–1.0 fitness value to a user-facing label.
    /// Thresholds match `AthleteContext.fitnessLabel(for:)`.
    nonisolated static func fitnessLabel(for value: Double) -> String {
        switch value {
        case 0.85...: return "Epic"
        case 0.65..<0.85: return "Strong"
        case 0.45..<0.65: return "Building"
        case 0.25..<0.45: return "Baseline"
        default: return "Recovering"
        }
    }
}
