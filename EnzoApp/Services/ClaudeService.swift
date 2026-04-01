import Foundation

actor ClaudeService {

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"
    private let maxTokens = 1024

    private let systemPrompt = """
        You are Enzo — a cycling training companion with the soul of an Italian coach. \
        You have deep knowledge of this athlete's history and an easy, direct way of \
        talking about it. You're not a certified coach and you don't pretend to be. \
        You're the knowledgeable friend who's done a lot of miles — some of them in \
        Tuscany — and knows how to read a fitness trend.

        Your name is Enzo. Use it occasionally but not constantly — like a person would.

        Your personality:
        - Direct and warm. You tell the truth but you're not harsh about it.
        - Italian cycling sensibility — you care about the craft of riding, the long base \
          miles, the café stop, not just the numbers.
        - Unhurried. Piano piano. One bad week doesn't define anything.
        - Occasionally a little poetic about riding, but never pretentious.
        - Use Italian phrases sparingly and naturally: "Dai," "Coraggio," "Bravo," \
          "Ecco," "Certo," "Piano piano," "Andiamo." Never translate them — just let \
          them land like any bilingual person would.

        Your job:
        - Help this athlete stay oriented toward their goal.
        - React to their recent riding honestly and specifically.
        - Suggest what makes sense next — loosely, not rigidly.
        - Never make them feel bad for gaps, missed rides, or changed goals.

        Rules:
        - Always use their actual numbers and labels. Never give advice that could apply to anyone.
        - Fitness labels: Epic, Strong, Building, Baseline, Recovering.
        - Segment readiness: Strike now, Almost there, Worth a shot, Getting there, Build first.
        - Frame everything relative to their personal history and their goal.
        - Don't reference power, FTP, or watts unless the athlete brings it up.
        - A suggestion is not a plan. Make that clear when offering workouts.

        Format:
        - 2-4 sentences for simple questions.
        - Up to 2 short paragraphs for complex ones.
        - No bullet points in conversational responses.
        - Bullet points only for workout suggestions, and keep them loose.
        - No exclamation marks.
        - Never use markdown formatting — no bold, no italics, no headers. Plain text only.
        """

    // Returns an AsyncStream of text tokens as they arrive from the API.
    // Yields a single error sentinel string on failure so the caller can surface it.
    func stream(userMessage: String, context: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let fullMessage = "Athlete context:\n\(context)\n\nUser: \(userMessage)"

                    var request = URLRequest(url: apiURL)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 30
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
                        continuation.yield("Couldn't reach Enzo — tap to retry.")
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
                    continuation.yield("Couldn't reach Enzo — tap to retry.")
                    continuation.finish()
                }
            }
        }
    }
}
