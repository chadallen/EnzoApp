import Foundation
import simd

// MARK: - EffortFitnessJoiner

/// Joins SegmentEffortModel records to their corresponding DailyFitnessModel values.
///
/// For each effort, looks up the DailyFitnessModel for effortDate - 1 day.
/// Using the prior day's values captures the athlete's form going INTO the effort,
/// before that day's riding has been absorbed into CTL/ATL.
///
/// The join returns a dictionary of effort ID → (ctlOnDay, tsbOnDay) pairs.
/// The caller (sync orchestration) writes these back to the SegmentEffortModel records.
enum EffortFitnessJoiner {

    struct JoinResult {
        let effortId: Int
        let ctlOnDay: Double
        let tsbOnDay: Double
    }

    /// Returns CTL/TSB values for each effort by joining to the DailyFitness timeline.
    ///
    /// - Parameters:
    ///   - efforts: The segment efforts to join. `effortDate` is used to look up the prior day.
    ///   - fitnessIndex: DailyFitnessModel keyed by UTC-midnight date. Build from all stored rows.
    /// - Returns: One JoinResult per effort. Efforts with no matching fitness row get CTL/TSB = 0.
    static func join(
        efforts: [SegmentEffortModel],
        fitnessIndex: [Date: DailyFitnessModel],
        calendar: Calendar = .utc
    ) -> [JoinResult] {
        efforts.map { effort in
            let effortDay = calendar.startOfDay(for: effort.effortDate)
            let priorDay  = calendar.date(byAdding: .day, value: -1, to: effortDay) ?? effortDay

            if let fitness = fitnessIndex[priorDay] {
                return JoinResult(effortId: effort.stravaEffortId, ctlOnDay: fitness.ctl, tsbOnDay: fitness.tsb)
            } else {
                return JoinResult(effortId: effort.stravaEffortId, ctlOnDay: 0, tsbOnDay: 0)
            }
        }
    }

    /// Convenience: builds the DailyFitnessModel index from an array.
    static func buildIndex(from rows: [DailyFitnessModel], calendar: Calendar = .utc) -> [Date: DailyFitnessModel] {
        Dictionary(rows.map { (calendar.startOfDay(for: $0.date), $0) },
                   uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - SegmentOLSSolver

/// Fits a per-segment OLS regression: elapsed_time = β₀ + β₁·CTL + β₂·TSB + ε.
///
/// Solved via the normal equations: β = (XᵀX)⁻¹ Xᵀy
/// Matrix inversion uses simd_double3x3 — no LAPACK required for this 3×3 case.
///
/// Expected signs:
///   β₁ (CTL coefficient) < 0  — fitter athlete → lower elapsed time
///   β₂ (TSB coefficient) < 0  — fresher athlete → lower elapsed time
///
/// isValid is set false when:
///   - n < 1 (no efforts)
///   - XᵀX determinant ≈ 0 (singular — all efforts at identical CTL/TSB)
///   - β₁ > 0 (wrong sign — fitness predicts slower time; indicates confounding)
enum SegmentOLSSolver {

    // MARK: - Input / Output

    struct EffortPoint {
        let elapsedTime: Double  // seconds — response variable (y)
        let ctlOnDay: Double     // predictor x₁
        let tsbOnDay: Double     // predictor x₂
    }

    struct FitResult {
        let beta0: Double        // intercept
        let beta1: Double        // CTL coefficient
        let beta2: Double        // TSB coefficient
        let sigmaResid: Double   // residual standard deviation (denominator = n-3)
        let prTime: Double       // all-time best elapsed_time across all efforts
        let prCTL: Double        // CTL on the day the PR was set
        let nEfforts: Int
        let ctlMin: Double
        let ctlMax: Double
        let tsbMin: Double
        let tsbMax: Double
        let isValid: Bool
    }

    // MARK: - Fit

    /// Fits the OLS model for one segment.
    ///
    /// Always returns a FitResult — isValid indicates whether the model can be used for prediction.
    /// When isValid == false, prTime and prCTL are still populated for the naive fallback string.
    static func fit(efforts: [EffortPoint]) -> FitResult {
        let n = efforts.count

        let prEffort = efforts.min(by: { $0.elapsedTime < $1.elapsedTime })
        let prTime   = prEffort?.elapsedTime ?? 0
        let prCTL    = prEffort?.ctlOnDay    ?? 0
        let ctlMin   = efforts.map { $0.ctlOnDay }.min() ?? 0
        let ctlMax   = efforts.map { $0.ctlOnDay }.max() ?? 0
        let tsbMin   = efforts.map { $0.tsbOnDay }.min() ?? 0
        let tsbMax   = efforts.map { $0.tsbOnDay }.max() ?? 0

        // Not enough data to fit a meaningful model
        guard n >= 1 else {
            return FitResult(beta0: 0, beta1: 0, beta2: 0, sigmaResid: 0,
                             prTime: prTime, prCTL: prCTL, nEfforts: n,
                             ctlMin: ctlMin, ctlMax: ctlMax, tsbMin: tsbMin, tsbMax: tsbMax,
                             isValid: false)
        }

        // Build XᵀX (3×3) and Xᵀy (3-vector) incrementally.
        // X row = [1, ctl, tsb], y = elapsedTime.
        // simd_double3x3 is column-major: columns are stored as simd_double3 vectors.
        var s00 = 0.0, s10 = 0.0, s20 = 0.0  // XᵀX column 0 (intercept column)
        var s11 = 0.0, s21 = 0.0, s22 = 0.0  // XᵀX upper triangle
        var xty0 = 0.0, xty1 = 0.0, xty2 = 0.0  // Xᵀy

        for e in efforts {
            let ctl = e.ctlOnDay
            let tsb = e.tsbOnDay
            let y   = e.elapsedTime

            s00  += 1.0
            s10  += ctl
            s20  += tsb
            s11  += ctl * ctl
            s21  += ctl * tsb
            s22  += tsb * tsb
            xty0 += y
            xty1 += ctl * y
            xty2 += tsb * y
        }

        // Assemble XᵀX (symmetric). simd_double3x3(columns:) takes column vectors.
        let xtx = simd_double3x3(columns: (
            simd_double3(s00, s10, s20),  // column 0
            simd_double3(s10, s11, s21),  // column 1
            simd_double3(s20, s21, s22)   // column 2
        ))
        let xty = simd_double3(xty0, xty1, xty2)

        // Singular matrix check — determinant near zero means collinear predictors.
        let det = xtx.determinant
        guard abs(det) > 1e-10 else {
            return FitResult(beta0: 0, beta1: 0, beta2: 0, sigmaResid: 0,
                             prTime: prTime, prCTL: prCTL, nEfforts: n,
                             ctlMin: ctlMin, ctlMax: ctlMax, tsbMin: tsbMin, tsbMax: tsbMax,
                             isValid: false)
        }

        // Solve β = (XᵀX)⁻¹ Xᵀy
        let xtxInv = xtx.inverse
        let beta   = xtxInv * xty  // simd_double3

        let beta0 = beta.x
        let beta1 = beta.y  // CTL coefficient — expected negative
        let beta2 = beta.z  // TSB coefficient — expected negative

        // Wrong-sign guard: if higher fitness predicts slower time, model is confounded.
        guard beta1 <= 0 else {
            return FitResult(beta0: beta0, beta1: beta1, beta2: beta2, sigmaResid: 0,
                             prTime: prTime, prCTL: prCTL, nEfforts: n,
                             ctlMin: ctlMin, ctlMax: ctlMax, tsbMin: tsbMin, tsbMax: tsbMax,
                             isValid: false)
        }

        // Residual standard deviation (denominator = n-3 for 3 parameters).
        let sigmaResid: Double
        if n > 3 {
            var sse = 0.0
            for e in efforts {
                let yHat = beta0 + beta1 * e.ctlOnDay + beta2 * e.tsbOnDay
                let r = e.elapsedTime - yHat
                sse += r * r
            }
            sigmaResid = sqrt(sse / Double(n - 3))
        } else {
            // n <= 3: can't compute meaningful residual variance with 3 parameters.
            // sigmaResid = 0 means the probability estimate degenerates, but isValid
            // can still be true for the extrapolation-guarded display path.
            sigmaResid = 0
        }

        return FitResult(beta0: beta0, beta1: beta1, beta2: beta2, sigmaResid: sigmaResid,
                         prTime: prTime, prCTL: prCTL, nEfforts: n,
                         ctlMin: ctlMin, ctlMax: ctlMax, tsbMin: tsbMin, tsbMax: tsbMax,
                         isValid: true)
    }
}
