import Foundation

struct GoalContext {
    let segmentName: String
    let requiredFitnessLabel: String   // "Strong", "Epic", etc.
    let requiredFitnessValue: Double   // 0.0–1.0 internal
    let targetDate: Date?
    let weeksRemaining: Int?
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
            weeksRemaining: nil
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
