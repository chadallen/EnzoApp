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
