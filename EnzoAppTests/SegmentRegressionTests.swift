import Testing
import Foundation
@testable import EnzoApp

// MARK: - Helpers

private typealias Effort = SegmentOLSSolver.EffortPoint

/// Builds a SegmentFitnessModel from an OLS FitResult for use in PRPredictor tests.
/// Uses segmentId = 1 and fittedAt = now.
private func makeSegmentModel(from fit: SegmentOLSSolver.FitResult) -> SegmentFitnessModel {
    SegmentFitnessModel(
        segmentId: 1,
        beta0: fit.beta0,
        beta1: fit.beta1,
        beta2: fit.beta2,
        sigmaResid: fit.sigmaResid,
        prTime: fit.prTime,
        prCTL: fit.prCTL,
        nEfforts: fit.nEfforts,
        ctlMin: fit.ctlMin,
        ctlMax: fit.ctlMax,
        tsbMin: fit.tsbMin,
        tsbMax: fit.tsbMax,
        isValid: fit.isValid,
        fittedAt: Date()
    )
}

/// Returns a SegmentFitnessModel with explicit field values (for invalid-model tests).
private func makeInvalidModel(
    prTime: Double = 300,
    prCTL: Double = 50,
    ctlMin: Double = 40,
    ctlMax: Double = 60,
    tsbMin: Double = -10,
    tsbMax: Double = 10
) -> SegmentFitnessModel {
    SegmentFitnessModel(
        segmentId: 1,
        beta0: 0, beta1: 0, beta2: 0,
        sigmaResid: 0,
        prTime: prTime,
        prCTL: prCTL,
        nEfforts: 0,
        ctlMin: ctlMin, ctlMax: ctlMax,
        tsbMin: tsbMin, tsbMax: tsbMax,
        isValid: false,
        fittedAt: Date()
    )
}

// MARK: - SegmentOLSSolver Tests

@Suite("SegmentOLSSolver")
struct SegmentOLSTests {

    // MARK: Known-answer test

    @Test("known linear relationship y = 300 - 2*CTL - 0.5*TSB recovers correct coefficients")
    func knownAnswerTest() {
        // 10 synthetic effort points on y = 300 - 2*CTL - 0.5*TSB
        // Varied CTL and TSB to ensure non-singular matrix.
        let data: [(ctl: Double, tsb: Double)] = [
            (40, -5), (45, 0), (50, 5), (55, 10), (60, -10),
            (42, 3), (48, -8), (53, 7), (58, -3), (62, 1),
        ]
        let efforts = data.map { d in
            Effort(elapsedTime: 300 - 2 * d.ctl - 0.5 * d.tsb, ctlOnDay: d.ctl, tsbOnDay: d.tsb)
        }

        let fit = SegmentOLSSolver.fit(efforts: efforts)

        #expect(fit.isValid)
        #expect(abs(fit.beta0 - 300.0) < 0.001)
        #expect(abs(fit.beta1 - (-2.0)) < 0.001)
        #expect(abs(fit.beta2 - (-0.5)) < 0.001)
        // Perfect fit → residuals ≈ 0
        #expect(fit.sigmaResid < 0.001)
    }

    // MARK: Wrong-sign guard

    @Test("wrong-sign guard: beta1 > 0 (higher CTL → longer time) sets isValid false")
    func wrongSignGuard() {
        // Construct data where higher CTL predicts longer elapsed time (wrong sign).
        // Vary TSB slightly to avoid a singular matrix — the wrong-sign guard fires after the
        // singular-matrix guard, so we need a non-singular XᵀX to reach it.
        let efforts = [
            Effort(elapsedTime: 200, ctlOnDay: 30, tsbOnDay: -2),
            Effort(elapsedTime: 250, ctlOnDay: 50, tsbOnDay:  0),
            Effort(elapsedTime: 300, ctlOnDay: 70, tsbOnDay:  2),
            Effort(elapsedTime: 350, ctlOnDay: 90, tsbOnDay: -1),
            Effort(elapsedTime: 400, ctlOnDay: 110, tsbOnDay: 1),
        ]
        let fit = SegmentOLSSolver.fit(efforts: efforts)
        #expect(!fit.isValid)
        #expect(fit.beta1 > 0)
    }

    // MARK: Singular matrix guard

    @Test("singular matrix: all efforts at identical CTL and TSB returns isValid false")
    func singularMatrixGuard() {
        let efforts = [
            Effort(elapsedTime: 300, ctlOnDay: 50, tsbOnDay: 5),
            Effort(elapsedTime: 290, ctlOnDay: 50, tsbOnDay: 5),
            Effort(elapsedTime: 310, ctlOnDay: 50, tsbOnDay: 5),
            Effort(elapsedTime: 305, ctlOnDay: 50, tsbOnDay: 5),
        ]
        let fit = SegmentOLSSolver.fit(efforts: efforts)
        #expect(!fit.isValid)
    }

    // MARK: n = 0

    @Test("n=0 efforts returns isValid false")
    func noEffortsInvalid() {
        let fit = SegmentOLSSolver.fit(efforts: [])
        #expect(!fit.isValid)
        #expect(fit.nEfforts == 0)
    }

    // MARK: prTime and prCTL

    @Test("prTime is the minimum elapsedTime across all efforts")
    func prTimeIsMinimum() {
        let data: [(ctl: Double, tsb: Double)] = [
            (40, -5), (45, 0), (50, 5), (55, 10), (60, -10), (65, 2),
        ]
        let efforts = data.map { d in
            Effort(elapsedTime: 300 - 2 * d.ctl - 0.5 * d.tsb, ctlOnDay: d.ctl, tsbOnDay: d.tsb)
        }
        let fit = SegmentOLSSolver.fit(efforts: efforts)
        let manualMin = efforts.map { $0.elapsedTime }.min()!
        #expect(abs(fit.prTime - manualMin) < 0.001)
    }

    @Test("prCTL is the CTL of the effort with the minimum elapsedTime")
    func prCTLIsCtlOfFastestEffort() {
        let data: [(ctl: Double, tsb: Double)] = [
            (40, -5), (45, 0), (50, 5), (55, 10), (60, -10), (65, 2),
        ]
        let efforts = data.map { d in
            Effort(elapsedTime: 300 - 2 * d.ctl - 0.5 * d.tsb, ctlOnDay: d.ctl, tsbOnDay: d.tsb)
        }
        let fit = SegmentOLSSolver.fit(efforts: efforts)
        let fastestEffort = efforts.min(by: { $0.elapsedTime < $1.elapsedTime })!
        #expect(abs(fit.prCTL - fastestEffort.ctlOnDay) < 0.001)
    }

    // MARK: nEfforts, ctlMin/Max, tsbMin/Max

    @Test("FitResult metadata is populated from effort array")
    func metadataPopulated() {
        let data: [(ctl: Double, tsb: Double)] = [
            (40, -10), (50, 0), (60, 10), (70, 5), (80, -5),
        ]
        let efforts = data.map { d in
            Effort(elapsedTime: 300 - 2 * d.ctl - 0.5 * d.tsb, ctlOnDay: d.ctl, tsbOnDay: d.tsb)
        }
        let fit = SegmentOLSSolver.fit(efforts: efforts)
        #expect(fit.nEfforts == 5)
        #expect(fit.ctlMin == 40)
        #expect(fit.ctlMax == 80)
        #expect(fit.tsbMin == -10)
        #expect(fit.tsbMax == 10)
    }
}

// MARK: - EffortFitnessJoiner Tests

@Suite("EffortFitnessJoiner")
struct EffortFitnessJoinerTests {

    private func makeEffort(id: Int, year: Int, month: Int, day: Int) -> SegmentEffortModel {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let date = Calendar.utc.date(from: components)!
        return SegmentEffortModel(
            stravaEffortId: id,
            segmentId: 1,
            effortDate: date,
            elapsedTime: 300
        )
    }

    private func makeFitnessRow(year: Int, month: Int, day: Int,
                                ctl: Double, tsb: Double) -> DailyFitnessModel {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let date = Calendar.utc.date(from: components)!
        return DailyFitnessModel(date: date, ctl: ctl, atl: 0, tsb: tsb)
    }

    @Test("effort joins to prior day's fitness row")
    func effortJoinsToPriorDay() {
        // Effort on May 15 → should join to May 14 fitness row
        let effort = makeEffort(id: 1, year: 2024, month: 5, day: 15)
        let may14Row = makeFitnessRow(year: 2024, month: 5, day: 14, ctl: 55.0, tsb: 3.0)

        let index = EffortFitnessJoiner.buildIndex(from: [may14Row])
        let results = EffortFitnessJoiner.join(efforts: [effort], fitnessIndex: index)

        #expect(results.count == 1)
        #expect(results[0].effortId == 1)
        #expect(abs(results[0].ctlOnDay - 55.0) < 0.001)
        #expect(abs(results[0].tsbOnDay - 3.0) < 0.001)
    }

    @Test("effort with no matching prior day fitness row gets CTL/TSB = 0")
    func effortNoMatchGetsZero() {
        let effort = makeEffort(id: 42, year: 2024, month: 6, day: 1)
        let results = EffortFitnessJoiner.join(efforts: [effort], fitnessIndex: [:])

        #expect(results.count == 1)
        #expect(results[0].ctlOnDay == 0)
        #expect(results[0].tsbOnDay == 0)
    }

    @Test("multiple efforts each join to their own prior day")
    func multipleEffortsJoinCorrectly() {
        let effort1 = makeEffort(id: 1, year: 2024, month: 7, day: 10)
        let effort2 = makeEffort(id: 2, year: 2024, month: 7, day: 20)

        let row9  = makeFitnessRow(year: 2024, month: 7, day: 9,  ctl: 48.0, tsb: -2.0)
        let row19 = makeFitnessRow(year: 2024, month: 7, day: 19, ctl: 62.0, tsb: 5.0)

        let index = EffortFitnessJoiner.buildIndex(from: [row9, row19])
        let results = EffortFitnessJoiner.join(efforts: [effort1, effort2], fitnessIndex: index)

        let r1 = results.first(where: { $0.effortId == 1 })!
        let r2 = results.first(where: { $0.effortId == 2 })!

        #expect(abs(r1.ctlOnDay - 48.0) < 0.001)
        #expect(abs(r2.ctlOnDay - 62.0) < 0.001)
    }
}

// MARK: - PRPredictor Tests

@Suite("PRPredictor")
struct PRPredictorTests {

    // A valid model built from synthetic data: y = 300 - 2*CTL - 0.5*TSB
    // with 10 efforts (n > 3, so sigmaResid > 0 from real residual spread if perturbed).
    // Here we use a perfect-fit scenario and inject a non-zero sigmaResid manually.
    private func makeValidModel(
        beta0: Double = 300,
        beta1: Double = -2,
        beta2: Double = -0.5,
        sigmaResid: Double = 15,
        prTime: Double = 220,
        prCTL: Double = 55,
        ctlMin: Double = 40,
        ctlMax: Double = 70,
        tsbMin: Double = -10,
        tsbMax: Double = 10
    ) -> SegmentFitnessModel {
        SegmentFitnessModel(
            segmentId: 1,
            beta0: beta0, beta1: beta1, beta2: beta2,
            sigmaResid: sigmaResid,
            prTime: prTime, prCTL: prCTL,
            nEfforts: 10,
            ctlMin: ctlMin, ctlMax: ctlMax,
            tsbMin: tsbMin, tsbMax: tsbMax,
            isValid: true,
            fittedAt: Date()
        )
    }

    // MARK: Extrapolation flag

    @Test("isExtrapolating true when ctlToday > ctlMax * 1.1")
    func extrapolatingCTLHigh() {
        let model = makeValidModel(ctlMax: 70)
        // 70 * 1.1 = 77 → ctlToday = 78 should extrapolate
        let result = PRPredictor.predict(model: model, ctlToday: 78, tsbToday: 0)
        #expect(result.isExtrapolating)
    }

    @Test("isExtrapolating true when tsbToday > tsbMax + 20")
    func extrapolatingTSBHigh() {
        let model = makeValidModel(tsbMax: 10)
        // tsbMax + 20 = 30 → tsbToday = 31 should extrapolate
        let result = PRPredictor.predict(model: model, ctlToday: 55, tsbToday: 31)
        #expect(result.isExtrapolating)
    }

    @Test("within range: isExtrapolating false")
    func withinRangeNotExtrapolating() {
        let model = makeValidModel(ctlMin: 40, ctlMax: 70, tsbMin: -10, tsbMax: 10)
        // ctlToday=55 is between 40 and 70*1.1=77; tsbToday=5 is between -10-20=-30 and 10+20=30
        let result = PRPredictor.predict(model: model, ctlToday: 55, tsbToday: 5)
        #expect(!result.isExtrapolating)
    }

    // MARK: isValid == false model

    @Test("isValid false model returns probability 0 and isValid false in result")
    func invalidModelReturnsProbabilityZero() {
        let model = makeInvalidModel(prTime: 300, prCTL: 50)
        let result = PRPredictor.predict(model: model, ctlToday: 55, tsbToday: 5)
        #expect(!result.isValid)
        #expect(result.probability == 0)
    }

    // MARK: naiveFallback

    @Test("naiveFallback always populated with correct format")
    func naiveFallbackFormat() {
        let model = makeValidModel(prCTL: 52)
        let result = PRPredictor.predict(model: model, ctlToday: 61, tsbToday: 0)
        // prCTL.rounded() = 52, ctlToday.rounded() = 61
        #expect(result.naiveFallback == "PR set when CTL was 52. Your current CTL is 61.")
    }

    @Test("naiveFallback populated even when model is invalid")
    func naiveFallbackPopulatedWhenInvalid() {
        let model = makeInvalidModel(prCTL: 48)
        let result = PRPredictor.predict(model: model, ctlToday: 70, tsbToday: 0)
        #expect(result.naiveFallback == "PR set when CTL was 48. Your current CTL is 70.")
    }

    @Test("naiveFallback rounds CTL values to nearest integer")
    func naiveFallbackRoundsValues() {
        let model = makeValidModel(prCTL: 52.7)
        let result = PRPredictor.predict(model: model, ctlToday: 61.3, tsbToday: 0)
        // 52.7.rounded() = 53, 61.3.rounded() = 61
        #expect(result.naiveFallback == "PR set when CTL was 53. Your current CTL is 61.")
    }

    // MARK: Probability bounds

    @Test("probability is always clamped to [0, 1]")
    func probabilityAlwaysInBounds() {
        let model = makeValidModel()
        // Very far above PR performance → probability should not exceed 1
        let highResult = PRPredictor.predict(model: model, ctlToday: 120, tsbToday: 50)
        #expect(highResult.probability >= 0)
        #expect(highResult.probability <= 1)

        // Very poor fitness → probability should not go below 0
        let lowResult = PRPredictor.predict(model: model, ctlToday: 5, tsbToday: -50)
        #expect(lowResult.probability >= 0)
        #expect(lowResult.probability <= 1)
    }

    // MARK: Probability at parity (ŷ == prTime → probability == 0.5)

    @Test("when predicted time equals PR time probability is 0.5")
    func probabilityAtParity() {
        // Model: y = 300 - 2*CTL - 0.5*TSB, sigmaResid = 15, prTime = 220
        // We want yHat == prTime = 220.
        // 300 - 2*CTL - 0.5*0 = 220 → CTL = (300 - 220)/2 = 40
        let model = makeValidModel(
            beta0: 300, beta1: -2, beta2: -0.5,
            sigmaResid: 15,
            prTime: 220
        )
        let result = PRPredictor.predict(model: model, ctlToday: 40, tsbToday: 0)
        // ŷ = 300 - 2*40 - 0.5*0 = 300 - 80 = 220 = prTime → z = 0 → Φ(0) = 0.5
        #expect(abs(result.probability - 0.5) < 0.001)
    }

    // MARK: sigmaResid == 0 deterministic branch

    @Test("sigmaResid 0 with predicted time below PR gives probability 1.0")
    func sigmaZeroBelowPRProbabilityOne() {
        // With sigmaResid=0 and yHat < prTime → probability = 1.0
        let model = makeValidModel(
            beta0: 300, beta1: -2, beta2: -0.5,
            sigmaResid: 0,
            prTime: 220
        )
        // CTL=50 → yHat = 300 - 100 = 200 < 220 = prTime
        let result = PRPredictor.predict(model: model, ctlToday: 50, tsbToday: 0)
        #expect(result.probability == 1.0)
    }

    @Test("sigmaResid 0 with predicted time above PR gives probability 0.0")
    func sigmaZeroAbovePRProbabilityZero() {
        // With sigmaResid=0 and yHat > prTime → probability = 0.0
        let model = makeValidModel(
            beta0: 300, beta1: -2, beta2: -0.5,
            sigmaResid: 0,
            prTime: 220
        )
        // CTL=20 → yHat = 300 - 40 = 260 > 220 = prTime
        let result = PRPredictor.predict(model: model, ctlToday: 20, tsbToday: 0)
        #expect(result.probability == 0.0)
    }

    // MARK: predictedTime, lowerBound, upperBound

    @Test("predictedTime, lowerBound, upperBound are set correctly")
    func boundsAreCorrect() {
        let model = makeValidModel(
            beta0: 300, beta1: -2, beta2: -0.5,
            sigmaResid: 15
        )
        // CTL=55, TSB=5 → yHat = 300 - 110 - 2.5 = 187.5
        let result = PRPredictor.predict(model: model, ctlToday: 55, tsbToday: 5)
        let expectedYHat = 300.0 - 2.0 * 55.0 - 0.5 * 5.0
        #expect(abs(result.predictedTime - expectedYHat) < 0.001)
        #expect(abs(result.lowerBound - (expectedYHat - 15)) < 0.001)
        #expect(abs(result.upperBound - (expectedYHat + 15)) < 0.001)
    }

    // MARK: nEfforts passthrough

    @Test("nEfforts from model is passed through to result")
    func nEffortsPassthrough() {
        let model = makeValidModel()  // nEfforts = 10
        let result = PRPredictor.predict(model: model, ctlToday: 55, tsbToday: 0)
        #expect(result.nEfforts == 10)
    }

    // MARK: prTime passthrough

    @Test("prTime from model is passed through to result")
    func prTimePassthrough() {
        let model = makeValidModel(prTime: 243)
        let result = PRPredictor.predict(model: model, ctlToday: 55, tsbToday: 0)
        #expect(result.prTime == 243)
    }
}
