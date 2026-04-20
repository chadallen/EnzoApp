import Foundation

// MARK: - PRPredictor

/// Computes PR probability for a segment given today's fitness values.
///
/// Uses the fitted SegmentFitnessModel to predict elapsed time at today's CTL/TSB,
/// then estimates PR probability as P(predicted effort beats PR) via the normal CDF.
///
/// Probability interpretation: the fraction of efforts at today's fitness level
/// that would be fast enough to beat the current PR, given the model's historical
/// residual spread.
///
/// Display rules (consumed by UI layer):
///   isValid == false     → show only naiveFallback, hide probability
///   isExtrapolating      → show probability with "limited confidence" caveat
///   otherwise            → show probability normally
enum PRPredictor {

    // MARK: - Result

    struct PredictionResult {
        /// Estimated PR probability 0.0–1.0. Meaningful only when isValid == true.
        let probability: Double

        /// Model's predicted elapsed time in seconds at today's CTL/TSB.
        let predictedTime: Double

        /// One-sigma faster bound (ŷ - σ) — lower elapsed time.
        let lowerBound: Double

        /// One-sigma slower bound (ŷ + σ) — higher elapsed time.
        let upperBound: Double

        /// All-time PR elapsed time in seconds (from SegmentFitnessModel).
        let prTime: Double

        /// False when the model could not be fit (wrong-sign β, singular matrix, n < 1).
        /// Show only naiveFallback when false.
        let isValid: Bool

        /// True when today's CTL or TSB is outside the training data range.
        /// Show probability with a "limited confidence" caveat when true.
        let isExtrapolating: Bool

        /// Number of efforts used to fit the model.
        let nEfforts: Int

        /// Always populated regardless of isValid.
        /// Format: "PR set when CTL was 52. Your current CTL is 61."
        let naiveFallback: String
    }

    // MARK: - Predict

    /// Computes a PredictionResult for a segment given today's fitness.
    ///
    /// - Parameters:
    ///   - model: The fitted SegmentFitnessModel for this segment.
    ///   - ctlToday: Current CTL from today's DailyFitnessModel row.
    ///   - tsbToday: Current TSB from today's DailyFitnessModel row.
    static func predict(
        model: SegmentFitnessModel,
        ctlToday: Double,
        tsbToday: Double
    ) -> PredictionResult {
        let naiveFallback = "PR set when CTL was \(Int(model.prCTL.rounded())). Your current CTL is \(Int(ctlToday.rounded()))."

        // Extrapolation check: flag when today's values are meaningfully outside
        // the range of data used to fit the model.
        let ctlExtrapolating = ctlToday > model.ctlMax * 1.1 || ctlToday < model.ctlMin * 0.9
        let tsbExtrapolating = tsbToday > model.tsbMax + 20   || tsbToday < model.tsbMin - 20
        let isExtrapolating  = ctlExtrapolating || tsbExtrapolating

        guard model.isValid else {
            return PredictionResult(
                probability: 0,
                predictedTime: 0,
                lowerBound: 0,
                upperBound: 0,
                prTime: model.prTime,
                isValid: false,
                isExtrapolating: isExtrapolating,
                nEfforts: model.nEfforts,
                naiveFallback: naiveFallback
            )
        }

        // Point prediction
        let yHat = model.beta0 + model.beta1 * ctlToday + model.beta2 * tsbToday

        // PR probability: P(this effort beats the PR)
        // = P(effort < prTime) = Φ((prTime - ŷ) / σ)
        // Using Darwin's erf() — no external dependency.
        let probability: Double
        if model.sigmaResid > 0 {
            let z = (model.prTime - yHat) / model.sigmaResid
            probability = 0.5 * (1.0 + erf(z / sqrt(2.0)))
        } else {
            // sigmaResid == 0 (n <= 3): predict deterministically — above/below PR.
            probability = yHat < model.prTime ? 1.0 : 0.0
        }

        return PredictionResult(
            probability: min(max(probability, 0), 1),
            predictedTime: yHat,
            lowerBound: yHat - model.sigmaResid,
            upperBound: yHat + model.sigmaResid,
            prTime: model.prTime,
            isValid: true,
            isExtrapolating: isExtrapolating,
            nEfforts: model.nEfforts,
            naiveFallback: naiveFallback
        )
    }
}
