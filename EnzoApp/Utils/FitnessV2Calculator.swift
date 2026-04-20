import Foundation

// MARK: - LTHREstimator

/// Estimates Lactate Threshold Heart Rate (LTHR) from activity history.
///
/// Uses the 95th percentile of average HR from rides between 20–90 minutes.
/// This duration window captures tempo and threshold efforts without requiring
/// a lab test or explicit test protocol.
///
/// No minimum sample count — works with any number of qualifying rides >= 1.
/// Returns nil only when there are no rides with HR data in the 20–90 min range.
enum LTHREstimator {

    /// Input type — only the fields needed for LTHR estimation.
    struct ActivityInput {
        let movingTime: Int       // seconds
        let avgHeartRate: Double? // nil if no HR data
    }

    /// Estimates LTHR from activity history.
    ///
    /// Returns nil if no qualifying rides exist (no rides with HR in the 20–90 min window).
    /// With even one qualifying ride, the 95th percentile of avg HR is returned
    /// (which equals that ride's HR for n=1 — a reasonable starting estimate).
    static func estimate(from activities: [ActivityInput]) -> Double? {
        let qualifyingHR: [Double] = activities.compactMap { a in
            guard let hr = a.avgHeartRate else { return nil }
            let minutes = Double(a.movingTime) / 60.0
            guard minutes >= 20, minutes <= 90 else { return nil }
            return hr
        }
        guard !qualifyingHR.isEmpty else { return nil }
        let sorted = qualifyingHR.sorted()
        let index = Int((Double(sorted.count - 1) * 0.95).rounded())
        return sorted[index]
    }
}

// MARK: - TSSCalculator

/// Computes Training Stress Score (TSS) for a single activity.
///
/// TSS quantifies the training load of one session on a 0–400 scale.
/// 100 TSS ≈ a maximal 1-hour effort (IF=1.0).
///
/// Priority order:
///   1. Power-based: `(hours × (watts/FTP)²) × 100` — requires device_watts and a set FTP
///   2. HR-based:    `(hours × (avgHR/LTHR)²) × 100` — requires HR and estimated LTHR
///
/// Returns nil if neither path is available. Callers should treat nil as 0 contribution
/// to daily training load (activity is counted as a rest day for CTL/ATL purposes).
///
/// Cap of 400 guards against sensor errors or corrupted data.
enum TSSCalculator {

    static let cap: Double = 400

    /// Returns TSS for one activity, or nil if neither power nor HR data is available.
    ///
    /// - Parameters:
    ///   - movingTime: Duration in seconds.
    ///   - avgHeartRate: Average HR from Strava. nil if not recorded.
    ///   - avgWatts: Average power. Should only be passed when Strava's device_watts == true.
    ///   - lthr: Estimated LTHR from LTHREstimator. nil if not yet computed.
    ///   - ftp: User-entered FTP from UserDefaults. nil if not set.
    static func compute(
        movingTime: Int,
        avgHeartRate: Double?,
        avgWatts: Double?,
        lthr: Double?,
        ftp: Double?
    ) -> Double? {
        let hours = Double(movingTime) / 3600.0

        // Priority 1 — power-based (more accurate when a power meter is used)
        if let watts = avgWatts, let ftp, ftp > 0 {
            return min(hours * pow(watts / ftp, 2) * 100, cap)
        }

        // Priority 2 — HR-based (covers most athletes without power meters)
        if let hr = avgHeartRate, let lthr, lthr > 0 {
            return min(hours * pow(hr / lthr, 2) * 100, cap)
        }

        return nil
    }
}
