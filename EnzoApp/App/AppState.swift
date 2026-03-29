import Foundation
import Observation

@Observable
@MainActor
class AppState {
    var athleteContext: AthleteContext = .preview
    var fitnessSnapshots: [FitnessSnapshot] = FitnessSnapshot.previewSnapshots
    var segments: [SegmentScore] = SegmentScore.previewSegments
    var arcMessages: [ArcMessage] = []

    // Streaming state for the in-progress Enzo response
    var isStreaming = false
    var streamingText = ""

    private let claudeService = ClaudeService()

    // MARK: - Goal setting

    func setGoal(_ segment: SegmentScore, targetDate: Date?) {
        let weeksRemaining: Int? = targetDate.map { date in
            let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
            return max(0, days / 7)
        }

        let requiredValue = segment.fitnessValueAtPR
        let newGoal = GoalContext(
            segmentName: segment.name,
            requiredFitnessLabel: AthleteContext.fitnessLabel(for: requiredValue),
            requiredFitnessValue: requiredValue,
            targetDate: targetDate,
            weeksRemaining: weeksRemaining
        )

        athleteContext = AthleteContext(
            name: athleteContext.name,
            yearsActive: athleteContext.yearsActive,
            totalActivities: athleteContext.totalActivities,
            currentFitnessLabel: athleteContext.currentFitnessLabel,
            currentFitnessValue: athleteContext.currentFitnessValue,
            trendDirection: athleteContext.trendDirection,
            peakFitnessLabel: athleteContext.peakFitnessLabel,
            peakFitnessMonth: athleteContext.peakFitnessMonth,
            daysSinceLastRide: athleteContext.daysSinceLastRide,
            goal: newGoal
        )

        segments = segments.map { seg in
            var updated = seg
            updated.isGoalSegment = seg.name == segment.name
            return updated
        }
    }

    func goalReactionStream(for segment: SegmentScore) async -> AsyncStream<String> {
        let prompt = AppState.goalReactionPrompt(segment: segment, athleteContext: athleteContext)
        let context = athleteContext.contextPayload(snapshots: fitnessSnapshots, segments: segments)
        return await claudeService.stream(userMessage: prompt, context: context)
    }

    /// Pure function — builds the Enzo prompt for reacting to a newly selected goal segment.
    /// Extracted for testability.
    static func goalReactionPrompt(segment: SegmentScore, athleteContext: AthleteContext) -> String {
        let fitnessAtPRLabel = AthleteContext.fitnessLabel(for: segment.fitnessValueAtPR)
        return "I want to set \(segment.name) as my PR goal. " +
               "I set that PR (\(segment.prFormatted)) on \(segment.prDate) " +
               "when I was at \(fitnessAtPRLabel) fitness. " +
               "My current fitness is \(athleteContext.currentFitnessLabel), trending \(athleteContext.trendDirection). " +
               "React to this goal choice — be honest about where I stand and whether a target date makes sense."
    }

    func sendMessage(_ text: String) async {
        let userMsg = ArcMessage(role: .user, content: text)
        arcMessages.append(userMsg)

        isStreaming = true
        streamingText = ""

        let context = athleteContext.contextPayload(
            snapshots: fitnessSnapshots,
            segments: segments
        )

        let tokenStream = await claudeService.stream(userMessage: text, context: context)

        for await token in tokenStream {
            streamingText += token
        }

        if !streamingText.isEmpty {
            arcMessages.append(ArcMessage(role: .enzo, content: streamingText))
        }

        streamingText = ""
        isStreaming = false
    }
}
