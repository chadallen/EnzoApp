import Testing
import Foundation
@testable import EnzoApp

@Suite("SyncService")
struct SyncServiceTests {

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: components)!
    }

    private func makeActivity(
        sportType: String = "Ride",
        movingTime: Int = 3600,
        hasHeartrate: Bool = true,
        avgHR: Double? = 140,
        distance: Double = 40000,
        elevation: Double = 500,
        trainer: Bool = false
    ) -> SyncService.StravaActivity {
        SyncService.StravaActivity(
            id: 1,
            startDate: "2025-08-01T10:00:00Z",
            movingTime: movingTime,
            distance: distance,
            sportType: sportType,
            hasHeartrate: hasHeartrate,
            averageHeartrate: avgHR,
            totalElevationGain: elevation,
            trainer: trainer
        )
    }

    // MARK: - isQualifying()

    @Test("road ride with HR and 60 minutes qualifies")
    func roadRideQualifies() {
        let activity = makeActivity(sportType: "Ride", movingTime: 3600, hasHeartrate: true)
        #expect(SyncService.isQualifying(activity))
    }

    @Test("virtual ride qualifies")
    func virtualRideQualifies() {
        let activity = makeActivity(sportType: "VirtualRide", movingTime: 3600, hasHeartrate: true)
        #expect(SyncService.isQualifying(activity))
    }

    @Test("mountain bike ride qualifies")
    func mountainBikeRideQualifies() {
        let activity = makeActivity(sportType: "MountainBikeRide", movingTime: 3600, hasHeartrate: true)
        #expect(SyncService.isQualifying(activity))
    }

    @Test("gravel ride qualifies")
    func gravelRideQualifies() {
        let activity = makeActivity(sportType: "GravelRide", movingTime: 3600, hasHeartrate: true)
        #expect(SyncService.isQualifying(activity))
    }

    @Test("run does not qualify")
    func runDoesNotQualify() {
        let activity = makeActivity(sportType: "Run", movingTime: 3600, hasHeartrate: true)
        #expect(!SyncService.isQualifying(activity))
    }

    @Test("exactly 30 minutes qualifies")
    func exactlyThirtyMinutesQualifies() {
        let activity = makeActivity(movingTime: 1800, hasHeartrate: true)
        #expect(SyncService.isQualifying(activity))
    }

    @Test("29 minutes 59 seconds does not qualify")
    func tooShortDoesNotQualify() {
        let activity = makeActivity(movingTime: 1799, hasHeartrate: true)
        #expect(!SyncService.isQualifying(activity))
    }

    @Test("ride with no HR data does not qualify")
    func noHRDoesNotQualify() {
        let activity = makeActivity(hasHeartrate: false)
        #expect(!SyncService.isQualifying(activity))
    }

    // MARK: - computeSnapshots()

    @Test("empty rides produces empty snapshots")
    func emptyRidesProducesEmptySnapshots() {
        let result = SyncService.computeSnapshots(from: [], userId: UUID())
        #expect(result.isEmpty)
    }

    @Test("rides in one month produces one snapshot")
    func oneMonthProducesOneSnapshot() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 5),  efficiencyValue: 0.20, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 15), efficiencyValue: 0.22, durationHours: 2.0),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 25), efficiencyValue: 0.21, durationHours: 1.0),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        #expect(result.count == 1)
        #expect(result[0].month.hasPrefix("2025-08"))
    }

    @Test("rides in two distinct months produces two snapshots")
    func twoMonthsProducesTwoSnapshots() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 7, day: 10), efficiencyValue: 0.18, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 10), efficiencyValue: 0.22, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        #expect(result.count == 2)
    }

    @Test("snapshots are ordered chronologically")
    func snapshotsAreChronological() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 9, day: 10), efficiencyValue: 0.24, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 7, day: 10), efficiencyValue: 0.18, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 10), efficiencyValue: 0.21, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        #expect(result.count == 3)
        #expect(result[0].month.hasPrefix("2025-07"))
        #expect(result[1].month.hasPrefix("2025-08"))
        #expect(result[2].month.hasPrefix("2025-09"))
    }

    @Test("all fitness values are in 0.0–1.0 range")
    func fitnessValuesInRange() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 6,  day: 10), efficiencyValue: 0.15, durationHours: 1.0),
            SyncService.RideData(date: makeDate(year: 2025, month: 7,  day: 10), efficiencyValue: 0.18, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8,  day: 10), efficiencyValue: 0.25, durationHours: 2.0),
            SyncService.RideData(date: makeDate(year: 2025, month: 9,  day: 10), efficiencyValue: 0.28, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        for snapshot in result {
            #expect(snapshot.fitnessValue >= 0.0)
            #expect(snapshot.fitnessValue <= 1.0)
        }
    }

    @Test("userId is set on all rows")
    func userIdIsSet() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 10), efficiencyValue: 0.20, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        #expect(result[0].userId == userId)
    }

    @Test("month stored as YYYY-MM-01 for Postgres date type")
    func monthStoredWithDaySuffix() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 15), efficiencyValue: 0.20, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        #expect(result[0].month == "2025-08-01")
    }

    @Test("hours ridden reflects this month's rides only")
    func hoursRiddenThisMonthOnly() {
        let userId = UUID()
        let rides = [
            // July rides (should not count toward Aug hours)
            SyncService.RideData(date: makeDate(year: 2025, month: 7, day: 20), efficiencyValue: 0.18, durationHours: 3.0),
            // August rides
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 5),  efficiencyValue: 0.20, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 15), efficiencyValue: 0.22, durationHours: 2.0),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        let augSnapshot = result.first { $0.month.hasPrefix("2025-08") }
        #expect(augSnapshot != nil)
        #expect(abs((augSnapshot?.hoursRidden ?? 0) - 3.5) < 0.001)
    }

    @Test("activity count reflects this month's rides only")
    func activityCountThisMonthOnly() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 7, day: 20), efficiencyValue: 0.18, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 5),  efficiencyValue: 0.20, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 15), efficiencyValue: 0.21, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 25), efficiencyValue: 0.22, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        let aug = result.first { $0.month.hasPrefix("2025-08") }
        #expect(aug?.activityCount == 3)
    }

    @Test("trend is 'up' when recent 4-week efficiency significantly exceeds prior 4 weeks")
    func trendUp() {
        let userId = UUID()
        // End of month = March 31
        // Prior 4 weeks from March 31: Feb 1–Feb 28 range
        // Recent 4 weeks: March 3–March 31
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 2, day: 5),  efficiencyValue: 0.15, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 2, day: 15), efficiencyValue: 0.16, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 3, day: 15), efficiencyValue: 0.30, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 3, day: 25), efficiencyValue: 0.32, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        let march = result.first { $0.month.hasPrefix("2025-03") }
        #expect(march?.trendDirection == "up")
    }

    @Test("trend is 'down' when recent 4-week efficiency significantly lags prior 4 weeks")
    func trendDown() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 2, day: 5),  efficiencyValue: 0.30, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 2, day: 15), efficiencyValue: 0.32, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 3, day: 15), efficiencyValue: 0.15, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 3, day: 25), efficiencyValue: 0.16, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        let march = result.first { $0.month.hasPrefix("2025-03") }
        #expect(march?.trendDirection == "down")
    }

    @Test("single month with no prior-period rides defaults trend to flat")
    func trendFlatWithNoPriorRides() {
        let userId = UUID()
        // Only rides in the last 4 weeks of the month — no prior window data
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 20), efficiencyValue: 0.22, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        #expect(result[0].trendDirection == "flat")
    }

    @Test("avgEfficiency is set on the snapshot row")
    func avgEfficiencyIsSet() {
        let userId = UUID()
        let rides = [
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 10), efficiencyValue: 0.20, durationHours: 1.5),
            SyncService.RideData(date: makeDate(year: 2025, month: 8, day: 20), efficiencyValue: 0.24, durationHours: 1.5),
        ]
        let result = SyncService.computeSnapshots(from: rides, userId: userId)
        let avgEff = result[0].avgEfficiency
        #expect(avgEff != nil)
        #expect(avgEff! > 0)
    }
}
