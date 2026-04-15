import Foundation

actor ClaudeService {

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"
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
        - Always use their actual numbers and labels. Never give advice that could apply to anyone.
        - Fitness is described using these labels only: Epic, Strong, Building, Baseline, Recovering.
        - Segment readiness uses: Strike now, Almost there, Worth a shot, Getting there, Build first.
        - Frame everything relative to their personal history and their goal.
        - Don't reference power, FTP, or watts unless the athlete brings it up.
        - A suggestion is not a plan. Make that clear when offering workouts.

        Format:
        - 2-4 sentences for simple questions.
        - Up to 3 short paragraphs for complex ones.
        - No bullet points in conversational responses.
        - Bullet points only for workout suggestions, and keep them loose.
        - No exclamation marks.
        """

    // Returns an AsyncStream of text tokens as they arrive from the API.
    // Yields a single error sentinel string on failure so the caller can surface it.
    // history: prior ArcMessages in this conversation (oldest first). Context is prepended
    // to the first user message; userMessage is appended as the latest user turn.
    func stream(userMessage: String, context: String, history: [ArcMessage] = []) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let messages = buildMessages(userMessage: userMessage, context: context, history: history)

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
                        "messages": messages
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

    // Builds the messages array for the API call.
    // Context is embedded in the first user message of the conversation.
    private func buildMessages(userMessage: String, context: String, history: [ArcMessage]) -> [[String: Any]] {
        if history.isEmpty {
            return [
                ["role": "user", "content": "Athlete context:\n\(context)\n\nUser: \(userMessage)"]
            ]
        }

        var messages: [[String: Any]] = []
        for (i, msg) in history.enumerated() {
            let role = msg.role == .user ? "user" : "assistant"
            let content: String
            if i == 0 && msg.role == .user {
                content = "Athlete context:\n\(context)\n\nUser: \(msg.content)"
            } else {
                content = msg.content
            }
            messages.append(["role": role, "content": content])
        }
        messages.append(["role": "user", "content": userMessage])
        return messages
    }
}
