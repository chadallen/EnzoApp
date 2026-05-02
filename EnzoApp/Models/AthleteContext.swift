import Foundation

struct AthleteContext {
    let name: String
    let yearsActive: Int
    let totalActivities: Int
    let currentFitnessLabel: String
    let currentFitnessValue: Double    // 0.0–1.0 internal, never shown to user
    let trendDirection: String         // "up", "flat", "down"
    let peakFitnessLabel: String
    let peakFitnessMonth: String
    let daysSinceLastRide: Int

    // MARK: - Fitness label utility

    static func fitnessLabel(for value: Double) -> String {
        switch value {
        case 0.85...: return "Epic"
        case 0.65..<0.85: return "Strong"
        case 0.45..<0.65: return "Building"
        case 0.25..<0.45: return "Baseline"
        default: return "Recovering"
        }
    }

    // MARK: - Factory: build from local store data

    /// Assembles a live AthleteContext from fetched snapshots.
    /// Pure function — no network, fully testable.
    ///
    /// - Parameters:
    ///   - name: Athlete display name.
    ///   - snapshots: All fetched FitnessSnapshot rows, any order.
    ///   - lastActivityDate: Most recent qualifying ride date, used for days_since_last_ride.
    static func build(
        name: String,
        snapshots: [FitnessSnapshot],
        lastActivityDate: Date?
    ) -> AthleteContext {
        let sorted = snapshots.sorted { $0.month < $1.month }

        // Current fitness = most recent snapshot; fall back to zero if no data yet.
        let current = sorted.last
        let currentValue = current?.value ?? 0.0
        let currentLabel = current?.label ?? "Recovering"
        let currentTrend = current?.trend ?? "flat"

        // Peak = snapshot with highest fitness value.
        let peak = sorted.max(by: { $0.value < $1.value })
        let peakLabel = peak?.label ?? "Recovering"
        let peakMonth = peak.map { formatPeakMonth($0.month) } ?? "—"

        // yearsActive: from first snapshot month to today.
        let yearsActive: Int = {
            guard let first = sorted.first,
                  let firstDate = monthDate(from: first.month) else { return 0 }
            let components = Calendar.current.dateComponents([.year], from: firstDate, to: Date())
            return max(components.year ?? 0, 1)
        }()

        // totalActivities: sum of all snapshot ride counts.
        let totalActivities = sorted.reduce(0) { $0 + $1.rides }

        // days_since_last_ride: from lastActivityDate to today, or 0 if unknown.
        let daysSinceLastRide: Int = {
            guard let last = lastActivityDate else { return 0 }
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            return max(days, 0)
        }()

        return AthleteContext(
            name: name,
            yearsActive: yearsActive,
            totalActivities: totalActivities,
            currentFitnessLabel: currentLabel,
            currentFitnessValue: currentValue,
            trendDirection: currentTrend,
            peakFitnessLabel: peakLabel,
            peakFitnessMonth: peakMonth,
            daysSinceLastRide: daysSinceLastRide
        )
    }

    // MARK: - Hardcoded preview data (Section 18)

    static let preview = AthleteContext(
        name: "Chad",
        yearsActive: 11,
        totalActivities: 654,
        currentFitnessLabel: "Recovering",
        currentFitnessValue: 0.18,
        trendDirection: "up",
        peakFitnessLabel: "Epic",
        peakFitnessMonth: "August 2025",
        daysSinceLastRide: 3
    )

    static let previewBriefing = """
You peaked last August — 30 hours in a month, your best in years. September dropped \
off sharply, which happens. You've been Recovering since the new year but you're \
trending up now.
"""

    static let previewLookahead = """
It's been a few days. Nothing lost yet — your fitness doesn't move that fast. \
When you're ready, aim for two or three rides this week. Nothing heroic. Just get back on the bike.
"""

    static let previewChartContext = "Your peak was last August — your best in years. September dropped off sharply. You've been building back since October."

    // MARK: - Private helpers

    private static func formatPeakMonth(_ month: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: month) else { return month }
        let display = DateFormatter()
        display.dateFormat = "MMMM yyyy"
        return display.string(from: date)
    }

    private static func monthDate(from month: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: month)
    }

    // MARK: - Claude context payload

    // Builds the JSON string sent to Claude with each user message.
    // Matches the structure in spec Section 5.
    func contextPayload(snapshots: [FitnessSnapshot], segments: [SegmentScore]) -> String {
        let fitnessHistory: [[String: Any]] = snapshots.sorted { $0.month < $1.month }.map { s in
            [
                "month": s.month,
                "hours": s.hours,
                "fitness_label": s.label,
                "trend_direction": s.trend,
                "activity_count": s.rides
            ]
        }

        let peakSnapshot = snapshots.max(by: { $0.value < $1.value })
        var peakDict: [String: Any] = [:]
        if let peak = peakSnapshot {
            peakDict = [
                "month": peak.month,
                "label": peak.label
            ]
        }

        let topSegments: [[String: Any]] = segments.map { seg in
            [
                "name": seg.name,
                "pr_seconds": seg.prSeconds,
                "pr_date": seg.prDate,
                "fitness_at_pr": AthleteContext.fitnessLabel(for: seg.fitnessValueAtPR),
                "current_fitness": AthleteContext.fitnessLabel(for: seg.currentFitnessValue),
                "trend_direction": seg.trendDirection,
                "strike_score": seg.strikeScore,
                "strike_label": seg.strikeLabel
            ]
        }

        var payload: [String: Any] = [
            "athlete": [
                "name": name,
                "years_active": yearsActive,
                "current_fitness_label": currentFitnessLabel,
                "trend_direction": trendDirection
            ] as [String: Any],
            "fitness_history": fitnessHistory,
            "top_segments": topSegments,
            "recent_weeks": [[String: Any]](),   // populated in Step 10 (webhooks)
            "days_since_last_ride": daysSinceLastRide
        ]
        if !peakDict.isEmpty {
            payload["peak_fitness"] = peakDict
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
            let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}
