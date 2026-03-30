import Testing
@testable import EnzoApp

@Suite("FitnessCalculator")
struct FitnessCalculatorTests {

    // MARK: - efficiency()

    @Test("lower HR for same effort produces higher efficiency")
    func efficiencyInverseWithHR() {
        let lowHR = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 500,
            sportType: "Ride", durationHours: 1.5, avgHR: 120
        )
        let highHR = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 500,
            sportType: "Ride", durationHours: 1.5, avgHR: 160
        )
        #expect(lowHR != nil && highHR != nil)
        #expect(lowHR! > highHR!)
    }

    @Test("gravel ride applies 1.15x adjusted-distance bonus")
    func gravelBonus() {
        let road = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 0,
            sportType: "Ride", durationHours: 1.5, avgHR: 140
        )
        let gravel = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 0,
            sportType: "GravelRide", durationHours: 1.5, avgHR: 140
        )
        #expect(road != nil && gravel != nil)
        #expect(abs(gravel! / road! - 1.15) < 0.0001)
    }

    @Test("elevation gain increases adjusted distance and efficiency")
    func elevationAddsToEfficiency() {
        let flat = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 0,
            sportType: "Ride", durationHours: 1.5, avgHR: 140
        )
        let hilly = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 1000,
            sportType: "Ride", durationHours: 1.5, avgHR: 140
        )
        #expect(flat != nil && hilly != nil)
        #expect(hilly! > flat!)
    }

    @Test("returns nil for ride under 30 minutes")
    func shortRideReturnsNil() {
        // 24 minutes = 0.4 hours
        let result = FitnessCalculator.efficiency(
            distanceKm: 20, elevationGainM: 100,
            sportType: "Ride", durationHours: 0.4, avgHR: 140
        )
        #expect(result == nil)
    }

    @Test("returns nil when avgHR is zero")
    func zeroHRReturnsNil() {
        let result = FitnessCalculator.efficiency(
            distanceKm: 30, elevationGainM: 200,
            sportType: "Ride", durationHours: 1.5, avgHR: 0
        )
        #expect(result == nil)
    }

    @Test("exactly 30-minute ride qualifies")
    func exactlyThirtyMinutesQualifies() {
        let result = FitnessCalculator.efficiency(
            distanceKm: 15, elevationGainM: 100,
            sportType: "Ride", durationHours: 0.5, avgHR: 135
        )
        #expect(result != nil)
        #expect(result! > 0)
    }

    @Test("efficiency formula is correct for a known input")
    func efficiencyFormula() {
        // distanceKm=40, elevationGainM=500 → adjustedDistance = 40 + 5 = 45
        // efficiency = 45 / (1.5 * 140) = 45 / 210 ≈ 0.2143
        let result = FitnessCalculator.efficiency(
            distanceKm: 40, elevationGainM: 500,
            sportType: "Ride", durationHours: 1.5, avgHR: 140
        )
        #expect(result != nil)
        #expect(abs(result! - 45.0 / 210.0) < 0.0001)
    }

    // MARK: - fitnessValue()

    @Test("fitness value stays within 0.0–1.0 range")
    func fitnessValueInRange() {
        let efficiencies = [0.15, 0.20, 0.18, 0.22, 0.25]
        let value = FitnessCalculator.fitnessValue(
            recentEfficiencies: efficiencies,
            allTimeMin: 0.10,
            allTimeMax: 0.30
        )
        #expect(value >= 0.0)
        #expect(value <= 1.0)
    }

    @Test("fitness value clamps to 1.0 when avg exceeds all-time max")
    func fitnessValueClampsHigh() {
        let value = FitnessCalculator.fitnessValue(
            recentEfficiencies: [0.35, 0.40],
            allTimeMin: 0.10,
            allTimeMax: 0.30
        )
        #expect(value == 1.0)
    }

    @Test("fitness value clamps to 0.0 when avg is below all-time min")
    func fitnessValueClampsLow() {
        let value = FitnessCalculator.fitnessValue(
            recentEfficiencies: [0.05, 0.08],
            allTimeMin: 0.10,
            allTimeMax: 0.30
        )
        #expect(value == 0.0)
    }

    @Test("empty efficiencies returns 0.0")
    func emptyEfficienciesReturnsZero() {
        let value = FitnessCalculator.fitnessValue(
            recentEfficiencies: [],
            allTimeMin: 0.10,
            allTimeMax: 0.30
        )
        #expect(value == 0.0)
    }

    @Test("min equals max returns 0.5")
    func minEqualsMaxReturnsHalf() {
        let value = FitnessCalculator.fitnessValue(
            recentEfficiencies: [0.20],
            allTimeMin: 0.20,
            allTimeMax: 0.20
        )
        #expect(value == 0.5)
    }

    @Test("fitness value normalizes midpoint to 0.5")
    func fitnessValueMidpoint() {
        // avg = 0.20, min = 0.10, max = 0.30 → (0.20 - 0.10) / (0.30 - 0.10) = 0.5
        let value = FitnessCalculator.fitnessValue(
            recentEfficiencies: [0.20],
            allTimeMin: 0.10,
            allTimeMax: 0.30
        )
        #expect(abs(value - 0.5) < 0.0001)
    }

    // MARK: - trendDirection()

    @Test("returns 'up' when recent avg exceeds prior by more than 0.05")
    func trendDirectionUp() {
        let result = FitnessCalculator.trendDirection(
            recentFourWeeks: 0.25,
            priorFourWeeks: 0.18
        )
        #expect(result == "up")
    }

    @Test("returns 'down' when recent avg is more than 0.05 below prior")
    func trendDirectionDown() {
        let result = FitnessCalculator.trendDirection(
            recentFourWeeks: 0.15,
            priorFourWeeks: 0.22
        )
        #expect(result == "down")
    }

    @Test("returns 'flat' when change is within ±0.05")
    func trendDirectionFlat() {
        let result = FitnessCalculator.trendDirection(
            recentFourWeeks: 0.20,
            priorFourWeeks: 0.21
        )
        #expect(result == "flat")
    }

    @Test("returns 'flat' at exact 0.05 boundary")
    func trendDirectionAtBoundary() {
        let result = FitnessCalculator.trendDirection(
            recentFourWeeks: 0.25,
            priorFourWeeks: 0.20  // change = exactly 0.05, not > 0.05
        )
        #expect(result == "flat")
    }

    // MARK: - fitnessLabel()

    @Test("labels each fitness band correctly")
    func fitnessLabelBands() {
        #expect(FitnessCalculator.fitnessLabel(for: 1.0)  == "Epic")
        #expect(FitnessCalculator.fitnessLabel(for: 0.90) == "Epic")
        #expect(FitnessCalculator.fitnessLabel(for: 0.85) == "Epic")    // ≥ 0.85
        #expect(FitnessCalculator.fitnessLabel(for: 0.84) == "Strong")
        #expect(FitnessCalculator.fitnessLabel(for: 0.75) == "Strong")
        #expect(FitnessCalculator.fitnessLabel(for: 0.65) == "Strong")  // ≥ 0.65
        #expect(FitnessCalculator.fitnessLabel(for: 0.64) == "Building")
        #expect(FitnessCalculator.fitnessLabel(for: 0.55) == "Building")
        #expect(FitnessCalculator.fitnessLabel(for: 0.45) == "Building") // ≥ 0.45
        #expect(FitnessCalculator.fitnessLabel(for: 0.44) == "Baseline")
        #expect(FitnessCalculator.fitnessLabel(for: 0.35) == "Baseline")
        #expect(FitnessCalculator.fitnessLabel(for: 0.25) == "Baseline") // ≥ 0.25
        #expect(FitnessCalculator.fitnessLabel(for: 0.24) == "Recovering")
        #expect(FitnessCalculator.fitnessLabel(for: 0.10) == "Recovering")
        #expect(FitnessCalculator.fitnessLabel(for: 0.0)  == "Recovering")
    }

    // MARK: - cyclingTypes

    @Test("cycling types set contains all expected sport types")
    func cyclingTypesContainsExpected() {
        let expected = ["Ride", "VirtualRide", "MountainBikeRide", "GravelRide", "EMountainBikeRide"]
        for type in expected {
            #expect(FitnessCalculator.cyclingTypes.contains(type))
        }
    }

    @Test("cycling types set excludes non-cycling activities")
    func cyclingTypesExcludesNonCycling() {
        let nonCycling = ["Run", "Swim", "Walk", "WeightTraining", "Yoga", "Hike"]
        for type in nonCycling {
            #expect(!FitnessCalculator.cyclingTypes.contains(type))
        }
    }
}
