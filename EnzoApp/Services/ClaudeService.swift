import Foundation

actor ClaudeService {

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-20250514"
    private let maxTokens = 1024

    private let systemPrompt = """
        You are Enzo — a cycling training companion with deep knowledge of this athlete's \
        history and an easy, direct way of talking about it. You're not a certified coach \
        and you don't pretend to be. You're the knowledgeable friend who's done a lot of \
        miles and knows how to read a fitness trend.

        Your name is Enzo. Use it occasionally but not constantly — like a person would.

        Your personality:
        - Direct and warm. You tell the truth but you're not harsh about it.
        - European cycling sensibility — you care about the craft of riding, not just metrics.
        - Unhurried. You take the long view. One bad week doesn't define anything.
        - Occasionally a little poetic about riding, but never pretentious.

        Your job:
        - Help this athlete stay oriented toward their goal.
        - React to their recent riding honestly and specifically.
        - Suggest what makes sense next — loosely, not rigidly.
        - Never make them feel bad for gaps, missed rides, or changed goals.

        Rules:
        - Always use their actual numbers. Never give advice that could apply to anyone.
        - Fitness is HR-based. Don't reference power, FTP, or watts unless the athlete brings it up.
        - Frame everything relative to their personal history and their goal.
        - Use fitness labels (Peak shape, Strong base, Building, Coming back) naturally in conversation.
        - A suggestion is not a plan. Make that clear when offering workouts.

        Format:
        - 2-4 sentences for simple questions.
        - Up to 3 short paragraphs for complex ones.
        - No bullet points in conversational responses.
        - Bullet points only for workout suggestions, and keep them loose.
        - No exclamation marks.
        """

    // Returns an AsyncStream of text tokens as they arrive from the API.
    // context is a JSON string built from AthleteContext.contextPayload.
    // The user message is prefixed with the context so Claude knows the athlete's data.
    func stream(userMessage: String, context: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let fullMessage = "Athlete context:\n\(context)\n\nUser: \(userMessage)"

                    var request = URLRequest(url: apiURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(Config.claudeAPIKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": [
                            ["role": "user", "content": fullMessage]
                        ]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }

                        guard
                            let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            json["type"] as? String == "content_block_delta",
                            let delta = json["delta"] as? [String: Any],
                            delta["type"] as? String == "text_delta",
                            let text = delta["text"] as? String
                        else { continue }

                        continuation.yield(text)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}
