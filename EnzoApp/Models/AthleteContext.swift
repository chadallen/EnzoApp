import Foundation

struct GoalContext {
    let segmentName: String
    let requiredFitnessScore: Double
    let targetDate: Date?
    let weeksRemaining: Int?
    let gap: Double  // requiredFitnessScore - currentFitnessScore
}

struct AthleteContext {
    let name: String
    let yearsActive: Int
    let totalActivities: Int
    let currentFitnessScore: Double
    let currentFitnessLabel: String
    let peakFitnessScore: Double
    let peakFitnessMonth: String
    let daysSinceLastRide: Int
    let goal: GoalContext

    // MARK: - Fitness label utility

    static func fitnessLabel(for score: Double) -> String {
        switch score {
        case 80...: return "Peak shape"
        case 60..<80: return "Strong base"
        case 40..<60: return "Building"
        case 20..<40: return "Coming back"
        default: return "Early days"
        }
    }

    // MARK: - Hardcoded preview data (Section 18)

    static let preview = AthleteContext(
        name: "Chad",
        yearsActive: 11,
        totalActivities: 654,
        currentFitnessScore: 20,
        currentFitnessLabel: "Coming back",
        peakFitnessScore: 100,
        peakFitnessMonth: "August 2025",
        daysSinceLastRide: 3,
        goal: GoalContext(
            segmentName: "Hawk Hill",
            requiredFitnessScore: 72,
            targetDate: nil,
            weeksRemaining: nil,
            gap: 52
        )
    )

    static let previewBriefing = """
You peaked last August — 30 hours in a month, your best in years. September dropped off sharply, which happens. You've been in the 20s since the new year. Hawk Hill will need you closer to where you were in spring 2025, so there's real ground to cover. The good news is your history shows you can move fitness quickly when you're consistent.
"""

    static let previewLookahead = """
It's been a few days. Nothing lost yet — your fitness doesn't move that fast. When you're ready, aim for two or three rides this week. Nothing heroic. Just get back on the bike.
"""

    static let previewChartContext = "Your peak was last August — your best in years. September dropped off sharply. You've been building back since October."

    // MARK: - Claude context payload

    // Builds the JSON string sent to Claude with each user message.
    // Matches the structure in spec Section 5.
    func contextPayload(snapshots: [FitnessSnapshot], segments: [SegmentScore]) -> String {
        var goalDict: [String: Any] = [
            "type": "segment_pr",
            "segment_name": goal.segmentName,
            "required_fitness_score": goal.requiredFitnessScore,
            "current_fitness_score": currentFitnessScore,
            "gap": goal.gap,
            "has_date": goal.targetDate != nil
        ]
        if let weeks = goal.weeksRemaining {
            goalDict["weeks_remaining"] = weeks
        }

        let fitnessHistory: [[String: Any]] = snapshots.map { s in
            [
                "month": s.month,
                "hours": s.hours,
                "fitness_score": s.score,
                "fitness_label": AthleteContext.fitnessLabel(for: s.score),
                "activity_count": s.rides
            ]
        }

        let peakSnapshot = snapshots.max(by: { $0.score < $1.score })
        var peakDict: [String: Any] = [:]
        if let peak = peakSnapshot {
            peakDict = [
                "month": peak.month,
                "score": peak.score,
                "label": AthleteContext.fitnessLabel(for: peak.score)
            ]
        }

        let topSegments: [[String: Any]] = segments.map { seg in
            [
                "name": seg.name,
                "pr_seconds": seg.prSeconds,
                "pr_date": seg.prDate,
                "fitness_at_pr": seg.fitnessAtPR,
                "current_fitness": seg.currentFitness,
                "delta": seg.fitnessDelta,
                "strike_score": seg.strikeScore,
                "is_goal_segment": seg.isGoalSegment
            ]
        }

        var payload: [String: Any] = [
            "athlete": [
                "name": name,
                "years_active": yearsActive,
                "total_activities": totalActivities,
                "current_fitness_score": currentFitnessScore,
                "current_fitness_label": currentFitnessLabel
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
