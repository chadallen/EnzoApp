import Testing
import Foundation
@testable import EnzoApp

// MARK: - LTHREstimator Tests

@Suite("LTHREstimator")
struct LTHREstimatorTests {

    typealias Input = LTHREstimator.ActivityInput

    // MARK: p95 index behaviour

    @Test("p95 with 1 sample returns that sample")
    func p95OneSample() {
        let activities = [Input(movingTime: 2400, avgHeartRate: 155.0)]  // 40 min
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == 155.0)
    }

    @Test("p95 with 3 samples returns correct index")
    func p95ThreeSamples() {
        // sorted = [140, 150, 160], index = Int((2 * 0.95).rounded()) = Int(1.9.rounded()) = 2
        // → 160
        let activities = [
            Input(movingTime: 2400, avgHeartRate: 150.0),
            Input(movingTime: 2700, avgHeartRate: 160.0),
            Input(movingTime: 3000, avgHeartRate: 140.0),
        ]
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == 160.0)
    }

    @Test("p95 with 10 samples returns correct index")
    func p95TenSamples() {
        // HR values 141–150, sorted ascending.
        // index = Int((9 * 0.95).rounded()) = Int(8.55.rounded()) = 9 → sorted[9] = 150
        let activities = (1...10).map { i in
            Input(movingTime: 2400, avgHeartRate: Double(140 + i))  // 141, 142, ..., 150
        }
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == 150.0)
    }

    // MARK: nil cases

    @Test("no rides with HR in 20-90 min range returns nil")
    func noQualifyingRidesReturnsNil() {
        // Empty array — no activities at all
        let result = LTHREstimator.estimate(from: [])
        #expect(result == nil)
    }

    @Test("rides with HR but all outside the 20-90 min window returns nil")
    func allOutsideWindowReturnsNil() {
        let activities = [
            Input(movingTime: 1100, avgHeartRate: 155.0),  // 18.3 min — too short
            Input(movingTime: 5500, avgHeartRate: 160.0),  // 91.7 min — too long
        ]
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == nil)
    }

    @Test("rides with no HR data returns nil")
    func noHRDataReturnsNil() {
        let activities = [
            Input(movingTime: 2400, avgHeartRate: nil),
            Input(movingTime: 3000, avgHeartRate: nil),
        ]
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == nil)
    }

    // MARK: mixed qualifying / non-qualifying

    @Test("mix of qualifying and non-qualifying — only qualifying rides used")
    func mixedQualifyingAndNot() {
        let activities = [
            Input(movingTime: 900,  avgHeartRate: 180.0),  // 15 min — disqualified
            Input(movingTime: 2400, avgHeartRate: 155.0),  // 40 min — qualifies
            Input(movingTime: 2700, avgHeartRate: 158.0),  // 45 min — qualifies
            Input(movingTime: 6000, avgHeartRate: 130.0),  // 100 min — disqualified
            Input(movingTime: 3000, avgHeartRate: nil),    // 50 min but no HR — disqualified
        ]
        // qualifying HR: [155, 158], sorted = [155, 158]
        // index = Int((1 * 0.95).rounded()) = Int(0.95.rounded()) = 1 → 158
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == 158.0)
    }

    @Test("exactly 20-minute ride qualifies (inclusive lower bound)")
    func exactlyTwentyMinutesQualifies() {
        let activities = [Input(movingTime: 1200, avgHeartRate: 150.0)]  // exactly 20 min
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == 150.0)
    }

    @Test("exactly 90-minute ride qualifies (inclusive upper bound)")
    func exactlyNinetyMinutesQualifies() {
        let activities = [Input(movingTime: 5400, avgHeartRate: 162.0)]  // exactly 90 min
        let result = LTHREstimator.estimate(from: activities)
        #expect(result == 162.0)
    }
}

// MARK: - TSSCalculator Tests

@Suite("TSSCalculator")
struct TSSCalculatorTests {

    // MARK: Power path

    @Test("power path: correct formula hours * (watts/ftp)^2 * 100")
    func powerPathFormula() {
        // 1 hour @ 200w, FTP 250w → 1.0 * (200/250)^2 * 100 = 1.0 * 0.64 * 100 = 64.0
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: nil,
            avgWatts: 200,
            lthr: nil,
            ftp: 250
        )
        #expect(result != nil)
        #expect(abs(result! - 64.0) < 0.001)
    }

    // MARK: HR path

    @Test("HR path: correct formula hours * (hr/lthr)^2 * 100")
    func hrPathFormula() {
        // 2 hours @ avgHR 150, LTHR 170 → 2.0 * (150/170)^2 * 100
        let expected = 2.0 * pow(150.0 / 170.0, 2) * 100
        let result = TSSCalculator.compute(
            movingTime: 7200,
            avgHeartRate: 150,
            avgWatts: nil,
            lthr: 170,
            ftp: nil
        )
        #expect(result != nil)
        #expect(abs(result! - expected) < 0.001)
    }

    // MARK: Priority

    @Test("power takes priority when both watts and HR are available")
    func powerPriorityOverHR() {
        // Power path: 1h @ 250w, FTP 250 → 100.0 TSS
        // HR path: 1h @ 140 HR, LTHR 175 → much less
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: 140,
            avgWatts: 250,
            lthr: 175,
            ftp: 250
        )
        // Should be exactly 100.0 (power path), not the HR-path value
        #expect(result != nil)
        #expect(abs(result! - 100.0) < 0.001)
    }

    @Test("watts present but FTP nil falls through to HR path")
    func wattsPresentFTPNilFallsToHR() {
        // No FTP → can't use power path. HR + LTHR → use HR path.
        // 1h @ HR 150, LTHR 160 → (150/160)^2 * 100
        let expected = pow(150.0 / 160.0, 2) * 100
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: 150,
            avgWatts: 200,
            lthr: 160,
            ftp: nil
        )
        #expect(result != nil)
        #expect(abs(result! - expected) < 0.001)
    }

    // MARK: Cap at 400

    @Test("cap at 400: high-power long ride is clamped")
    func capAt400() {
        // 10 hours @ 200w, FTP 100 → 10 * 4 * 100 = 4000 → clamped to 400
        let result = TSSCalculator.compute(
            movingTime: 36000,
            avgHeartRate: nil,
            avgWatts: 200,
            lthr: nil,
            ftp: 100
        )
        #expect(result != nil)
        #expect(result! == TSSCalculator.cap)
        #expect(result! == 400.0)
    }

    // MARK: nil cases

    @Test("no watts and no HR returns nil")
    func noWattsNoHRReturnsNil() {
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: nil,
            avgWatts: nil,
            lthr: 165,
            ftp: 250
        )
        #expect(result == nil)
    }

    @Test("HR present but LTHR nil returns nil")
    func hrPresentLTHRNilReturnsNil() {
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: 150,
            avgWatts: nil,
            lthr: nil,
            ftp: nil
        )
        #expect(result == nil)
    }

    @Test("zero FTP treats power path as unavailable and falls through to HR")
    func zeroFTPFallsToHR() {
        // FTP = 0 is guarded, so should fall through to HR path
        let expected = pow(150.0 / 170.0, 2) * 100
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: 150,
            avgWatts: 200,
            lthr: 170,
            ftp: 0
        )
        #expect(result != nil)
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("zero LTHR treats HR path as unavailable and returns nil")
    func zeroLTHRReturnsNil() {
        let result = TSSCalculator.compute(
            movingTime: 3600,
            avgHeartRate: 150,
            avgWatts: nil,
            lthr: 0,
            ftp: nil
        )
        #expect(result == nil)
    }
}
