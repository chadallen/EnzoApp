import Testing
import Foundation
@testable import EnzoApp

// MARK: - Helpers

/// Creates an ActivityModel with a UTC-midnight date for a given year/month/day.
private func makeActivity(
    id: Int,
    year: Int, month: Int, day: Int,
    tss: Double
) -> ActivityModel {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 0
    components.minute = 0
    components.second = 0
    let date = Calendar.utc.date(from: components)!
    return ActivityModel(
        stravaId: id,
        date: date,
        movingTime: 3600,
        avgHeartRate: nil,
        avgWatts: nil,
        tss: tss
    )
}

/// Convenience: returns the UTC-midnight Date for a given year/month/day.
private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.utc.date(from: components)!
}

// MARK: - DailyFitnessBuilder Tests

@Suite("DailyFitnessBuilder")
struct DailyFitnessBuilderTests {

    // MARK: startDate == endDate

    @Test("startDate == endDate produces exactly one row")
    func startEqualsEndProducesOneRow() {
        let date = utcDate(year: 2024, month: 6, day: 1)
        let rows = DailyFitnessBuilder.build(
            from: [],
            startCTL: 0,
            startATL: 0,
            startDate: date,
            endDate: date
        )
        #expect(rows.count == 1)
        #expect(rows[0].date == date)
    }

    // MARK: Empty activities → rest days only

    @Test("empty activities produces rest-day rows with decaying CTL/ATL from non-zero start")
    func emptyActivitiesProducesRows() {
        let start = utcDate(year: 2024, month: 1, day: 1)
        let end   = utcDate(year: 2024, month: 1, day: 3)

        // Start with non-zero CTL/ATL to verify decay is happening
        let rows = DailyFitnessBuilder.build(
            from: [],
            startCTL: 42.0,
            startATL: 7.0,
            startDate: start,
            endDate: end
        )
        #expect(rows.count == 3)

        // On a rest day tss=0, CTL += (0 - CTL)/42 → CTL decreases
        // Day 1: CTL = 42 + (0-42)/42 = 42 - 1 = 41
        #expect(rows[0].ctl < 42.0)
        #expect(rows[1].ctl < rows[0].ctl)
        #expect(rows[2].ctl < rows[1].ctl)

        // ATL decays faster
        #expect(rows[0].atl < 7.0)
        #expect(rows[1].atl < rows[0].atl)
    }

    // MARK: Correct day ordering

    @Test("output dates are monotonically increasing")
    func datesMonotonicallyIncreasing() {
        let start = utcDate(year: 2024, month: 3, day: 10)
        let end   = utcDate(year: 2024, month: 3, day: 15)

        let rows = DailyFitnessBuilder.build(
            from: [],
            startCTL: 0,
            startATL: 0,
            startDate: start,
            endDate: end
        )
        #expect(rows.count == 6)
        for i in 1..<rows.count {
            #expect(rows[i].date > rows[i - 1].date)
        }
    }

    // MARK: CTL/ATL update formula

    @Test("single activity on one day: CTL and ATL update correctly via EMA formula")
    func singleActivityCTLATLUpdate() {
        // Start at CTL=0, ATL=0.
        // Activity of 100 TSS on day 1.
        // After day 1:
        //   TSB = 0 - 0 = 0  (prior-day values)
        //   CTL += (100 - 0) / 42 ≈ 2.381
        //   ATL += (100 - 0) / 7  ≈ 14.286

        let day1 = utcDate(year: 2024, month: 5, day: 1)
        let activity = makeActivity(id: 1, year: 2024, month: 5, day: 1, tss: 100)

        let rows = DailyFitnessBuilder.build(
            from: [activity],
            startCTL: 0,
            startATL: 0,
            startDate: day1,
            endDate: day1
        )

        #expect(rows.count == 1)
        let expectedCTL = 0.0 + (100.0 - 0.0) / 42.0
        let expectedATL = 0.0 + (100.0 - 0.0) / 7.0
        #expect(abs(rows[0].ctl - expectedCTL) < 0.001)
        #expect(abs(rows[0].atl - expectedATL) < 0.001)
    }

    // MARK: TSB = CTL_prev - ATL_prev

    @Test("TSB on a given day equals prior day's CTL minus prior day's ATL")
    func tsbEqualsPriorDayCTLMinusATL() {
        // Two days. Day 1 has 80 TSS. Check Day 2 TSB = Day1.CTL - Day1.ATL.
        let day1 = utcDate(year: 2024, month: 4, day: 10)
        let day2 = utcDate(year: 2024, month: 4, day: 11)
        let activity = makeActivity(id: 1, year: 2024, month: 4, day: 10, tss: 80)

        let rows = DailyFitnessBuilder.build(
            from: [activity],
            startCTL: 20.0,
            startATL: 15.0,
            startDate: day1,
            endDate: day2
        )

        #expect(rows.count == 2)

        // Day 2 TSB must equal Day 1's post-update CTL and ATL (the values going INTO day 2).
        let expectedTSB = rows[0].ctl - rows[0].atl
        #expect(abs(rows[1].tsb - expectedTSB) < 0.0001)
    }

    @Test("TSB on day 1 equals startCTL minus startATL (prior-day = seed values)")
    func day1TSBEqualsSeeds() {
        let day1 = utcDate(year: 2024, month: 7, day: 1)
        let rows = DailyFitnessBuilder.build(
            from: [],
            startCTL: 50.0,
            startATL: 30.0,
            startDate: day1,
            endDate: day1
        )
        #expect(rows.count == 1)
        // TSB = startCTL - startATL before any update
        #expect(abs(rows[0].tsb - (50.0 - 30.0)) < 0.0001)
    }

    // MARK: CTL/ATL decay on rest days

    @Test("rest days reduce both CTL and ATL compared to a loaded day")
    func restDayDecayLowerThanLoadedDay() {
        // Day with 100 TSS should produce higher CTL/ATL than a rest day from same start.
        let day = utcDate(year: 2024, month: 8, day: 1)
        let activity = makeActivity(id: 1, year: 2024, month: 8, day: 1, tss: 100)

        let loadedRows = DailyFitnessBuilder.build(
            from: [activity],
            startCTL: 40.0,
            startATL: 40.0,
            startDate: day,
            endDate: day
        )
        let restRows = DailyFitnessBuilder.build(
            from: [],
            startCTL: 40.0,
            startATL: 40.0,
            startDate: day,
            endDate: day
        )

        #expect(loadedRows[0].ctl > restRows[0].ctl)
        #expect(loadedRows[0].atl > restRows[0].atl)
    }

    // MARK: Multiple activities on the same day

    @Test("multiple activities on the same day have their TSS summed")
    func multipleActivitiesSameDay() {
        let day = utcDate(year: 2024, month: 9, day: 15)
        // Three activities on the same day: 50 + 30 + 20 = 100 TSS total
        let activities = [
            makeActivity(id: 1, year: 2024, month: 9, day: 15, tss: 50),
            makeActivity(id: 2, year: 2024, month: 9, day: 15, tss: 30),
            makeActivity(id: 3, year: 2024, month: 9, day: 15, tss: 20),
        ]

        let summedRows = DailyFitnessBuilder.build(
            from: activities,
            startCTL: 0,
            startATL: 0,
            startDate: day,
            endDate: day
        )
        let singleRows = DailyFitnessBuilder.build(
            from: [makeActivity(id: 99, year: 2024, month: 9, day: 15, tss: 100)],
            startCTL: 0,
            startATL: 0,
            startDate: day,
            endDate: day
        )

        #expect(abs(summedRows[0].ctl - singleRows[0].ctl) < 0.001)
        #expect(abs(summedRows[0].atl - singleRows[0].atl) < 0.001)
    }

    // MARK: Calendar.utc

    @Test("Calendar.utc has zero UTC offset (is UTC timezone)")
    func calendarUTCTimezone() {
        // TimeZone.identifier may return "UTC" or "GMT" depending on platform.
        // secondsFromGMT() == 0 is the authoritative check.
        #expect(Calendar.utc.timeZone.secondsFromGMT() == 0)
    }

    @Test("Calendar.utc uses Gregorian identifier")
    func calendarUTCIsGregorian() {
        #expect(Calendar.utc.identifier == .gregorian)
    }
}
