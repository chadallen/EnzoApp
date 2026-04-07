import Foundation

struct GoalContext {
    let segmentName: String
    let requiredFitnessLabel: String   // "Strong", "Epic", etc.
    let requiredFitnessValue: Double   // 0.0–1.0 internal
    let targetDate: Date?
    let weeksRemaining: Int?
    let daysRemaining: Int?
}

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
    let goal: GoalContext

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

    /// Assembles a live AthleteContext from fetched snapshots and an optional goal row.
    /// Pure function — no network, fully testable.
    ///
    /// - Parameters:
    ///   - name: Athlete display name.
    ///   - snapshots: All fetched FitnessSnapshot rows, any order.
    ///   - goalRow: Active GoalRow, or nil if no goal is set.
    ///   - lastActivityDate: Most recent qualifying ride date, used for days_since_last_ride.
    static func build(
        name: String,
        snapshots: [FitnessSnapshot],
        goalRow: GoalRow?,
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

        // Reconstruct GoalContext from persisted GoalRow, or use a placeholder.
        let goal: GoalContext = {
            guard let row = goalRow,
                  let segmentName = row.targetSegmentName else {
                return GoalContext(
                    segmentName: "",
                    requiredFitnessLabel: currentLabel,
                    requiredFitnessValue: currentValue,
                    targetDate: nil,
                    weeksRemaining: nil,
                    daysRemaining: nil
                )
            }
            let requiredValue = row.requiredFitnessValue ?? currentValue
            let requiredLabel = row.requiredFitnessLabel ?? fitnessLabel(for: requiredValue)
            var targetDate: Date? = nil
            var weeksRemaining: Int? = nil
            var daysRemaining: Int? = nil
            if let dateStr = row.targetDate {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone(identifier: "UTC")
                targetDate = f.date(from: dateStr)
                if let td = targetDate {
                    let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: td).day ?? 0)
                    daysRemaining = days
                    weeksRemaining = days / 7
                }
            }
            return GoalContext(
                segmentName: segmentName,
                requiredFitnessLabel: requiredLabel,
                requiredFitnessValue: requiredValue,
                targetDate: targetDate,
                weeksRemaining: weeksRemaining,
                daysRemaining: daysRemaining
            )
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
            daysSinceLastRide: daysSinceLastRide,
            goal: goal
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
        daysSinceLastRide: 3,
        goal: GoalContext(
            segmentName: "Hawk Hill",
            requiredFitnessLabel: "Strong",
            requiredFitnessValue: 0.70,
            targetDate: nil,
            weeksRemaining: nil,
            daysRemaining: nil
        )
    )

    static let previewBriefing = """
You peaked last August — 30 hours in a month, your best in years. September dropped \
off sharply, which happens. You've been Recovering since the new year but you're \
trending up now. Hawk Hill needs you at Strong, so there's real ground to cover — \
but your history shows you can move fitness fast when you're consistent.
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
        var goalDict: [String: Any] = [
            "type": "segment_pr",
            "segment_name": goal.segmentName,
            "required_fitness_label": goal.requiredFitnessLabel,
            "current_fitness_label": currentFitnessLabel,
            "has_date": goal.targetDate != nil
        ]
        if let weeks = goal.weeksRemaining {
            goalDict["weeks_remaining"] = weeks
        }

        let fitnessHistory: [[String: Any]] = snapshots.map { s in
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
                "strike_label": seg.strikeLabel,
                "is_goal_segment": seg.isGoalSegment
            ]
        }

        var payload: [String: Any] = [
            "athlete": [
                "name": name,
                "years_active": yearsActive,
                "current_fitness_label": currentFitnessLabel,
                "trend_direction": trendDirection
            ] as [String: Any],
            "goal": goalDict,
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
