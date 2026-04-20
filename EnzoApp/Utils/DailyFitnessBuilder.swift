import Foundation
import SwiftData

// MARK: - DailyFitnessBuilder

/// Builds and extends the CTL/ATL/TSB daily fitness timeline from a set of ActivityModel records.
///
/// The Performance Management Chart (PMC) model:
///   CTL (Chronic Training Load, 42-day EMA) = fitness
///   ATL (Acute Training Load,  7-day EMA)   = fatigue
///   TSB (Training Stress Balance)            = CTL - ATL = form / readiness
///
/// TSB is computed from the *prior* day's CTL and ATL, representing the athlete's
/// form going *into* a training day — before that day's load is absorbed.
///
/// Every calendar day from the oldest activity to today receives a row.
/// Rest days (tss = 0) cause CTL and ATL to naturally decay — they must not be skipped.
///
/// Usage: call `build(from:into:)` from the sync orchestration layer (AppState/SyncService).
/// This type is a pure static namespace — no state, fully testable.
enum DailyFitnessBuilder {

    // MARK: - Input type

    /// The daily TSS contribution from one or more activities on a single calendar day.
    struct DayInput {
        let date: Date    // calendar date (time component ignored — normalized to midnight UTC)
        let tss: Double   // sum of TSS for all activities on this date
    }

    // MARK: - Build

    /// Builds `DailyFitnessModel` rows for every calendar day from `startDate` to `endDate`.
    ///
    /// - Parameters:
    ///   - activities: All `ActivityModel` records to include. Dates are normalized to UTC midnight.
    ///   - startCTL: Initial CTL value (0.0 for a full rebuild; last known CTL for incremental).
    ///   - startATL: Initial ATL value (0.0 for a full rebuild; last known ATL for incremental).
    ///   - startDate: First day to generate a row for. For a full build, pass the date of the
    ///                oldest activity. For incremental, pass the day after the last stored row.
    ///   - endDate: Last day to generate a row for (inclusive). Pass `Date()` for today.
    ///   - calendar: Calendar to use for day iteration. Defaults to UTC Gregorian.
    /// - Returns: One `DailyFitnessModel` per calendar day in [startDate, endDate], in order.
    static func build(
        from activities: [ActivityModel],
        startCTL: Double = 0,
        startATL: Double = 0,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .utc
    ) -> [DailyFitnessModel] {
        // Index TSS by calendar day (UTC midnight) so we can look up each day's load in O(1).
        let tssByDay = buildTSSIndex(activities: activities, calendar: calendar)

        // Enumerate every calendar day in [startDate, endDate].
        let days = enumerateDays(from: startDate, to: endDate, calendar: calendar)
        guard !days.isEmpty else { return [] }

        var results: [DailyFitnessModel] = []
        results.reserveCapacity(days.count)

        var ctl = startCTL
        var atl = startATL

        for day in days {
            let tss = tssByDay[day] ?? 0.0

            // TSB = form going INTO this day — use prior-day CTL/ATL before updating.
            let tsb = ctl - atl

            // EMA update: CTL decays over 42 days, ATL over 7 days.
            ctl += (tss - ctl) / 42.0
            atl += (tss - atl) / 7.0

            results.append(DailyFitnessModel(date: day, ctl: ctl, atl: atl, tsb: tsb))
        }

        return results
    }

    // MARK: - Oldest activity date helper

    /// Returns the UTC-midnight date of the oldest activity, or nil if the array is empty.
    static func oldestActivityDate(from activities: [ActivityModel], calendar: Calendar = .utc) -> Date? {
        guard let oldest = activities.map({ $0.date }).min() else { return nil }
        return calendar.startOfDay(for: oldest)
    }

    // MARK: - Private helpers

    /// Groups activity TSS values by their UTC calendar day (midnight Date).
    /// Days with multiple activities sum their TSS contributions.
    private static func buildTSSIndex(activities: [ActivityModel], calendar: Calendar) -> [Date: Double] {
        var index: [Date: Double] = [:]
        for activity in activities {
            guard activity.tss > 0 else { continue }
            let day = calendar.startOfDay(for: activity.date)
            index[day, default: 0] += activity.tss
        }
        return index
    }

    /// Returns an array of UTC-midnight Dates for every calendar day in [start, end], inclusive.
    private static func enumerateDays(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay   = calendar.startOfDay(for: end)
        guard startDay <= endDay else { return [] }

        var days: [Date] = []
        var current = startDay
        while current <= endDay {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }
}

// MARK: - Calendar convenience

extension Calendar {
    /// UTC Gregorian calendar — used throughout the fitness timeline so dates are timezone-stable.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
