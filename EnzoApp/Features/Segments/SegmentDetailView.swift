import SwiftUI

struct SegmentDetailView: View {
    let segment: SegmentScore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Goal-setting state
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()

    // Enzo chat state — session-scoped, cleared on view disappear
    @State private var messages: [ArcMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingText = ""

    private var pillColor: Color {
        switch segment.strikeScore {
        case 0.80...: return .enzoGoal
        case 0.65..<0.80: return .enzoChartPrimary
        case 0.45..<0.65: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    private var strikeLine: String {
        switch segment.strikeScore {
        case 0.80...:
            return "You're fit and trending in the right direction. A good window to go after it."
        case 0.65..<0.80:
            return "Close — a little more consistency and the timing will be right."
        case 0.45..<0.65:
            return "Getting there. Worth targeting once you've built a bit more fitness."
        default:
            return "Not quite there yet. Worth targeting once you've built more fitness."
        }
    }

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        statsCard
                        readinessCard

                        if segment.isGoalSegment {
                            goalBadge
                        } else {
                            goalSettingCard
                        }

                        // Ask Enzo button — shown until the first message is sent
                        if messages.isEmpty && !isStreaming {
                            askEnzoButton
                        }

                        // Streaming in-progress response
                        if isStreaming && !streamingText.isEmpty {
                            ArcMessageView(message: ArcMessage(role: .enzo, content: streamingText))
                                .padding(.horizontal)
                                .id("streaming")
                        }

                        // Message thread
                        if !messages.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(messages) { message in
                                    ArcMessageView(message: message)
                                }
                            }
                            .padding(.horizontal)
                            .id("thread-end")
                        }

                        // Bottom padding so content clears the input bar
                        Color.clear.frame(height: 80)
                    }
                    .padding()
                }
                .onChange(of: streamingText) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("thread-end", anchor: .bottom)
                    }
                }
            }

            // Input bar pinned to bottom — only visible once a conversation has started
            if !messages.isEmpty || isStreaming {
                VStack {
                    Spacer()
                    ArcInputBar(text: $inputText, isSending: isStreaming) { text in
                        Task { await sendFollowUp(text) }
                    }
                    .background(Color.enzoBg)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.enzoBg, for: .navigationBar)
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if segment.isGoalSegment {
                Label("Goal segment", systemImage: "star.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoAccent)
            }
            Text(segment.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
        }
    }

    private var statsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                statBlock(value: segment.prFormatted, label: "Current PR", mono: true, color: Color.enzoAccent)
                statBlock(value: formattedPRDate(segment.prDate), label: "Date set")
            }

            if segment.distanceMeters != nil || segment.elevationDeltaMeters != nil {
                Rectangle()
                    .fill(Color.enzoSecondary.opacity(0.12))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    if let dist = segment.distanceMeters {
                        statBlock(value: String(format: "%.1f mi", dist * 0.000621371), label: "Distance")
                    }
                    if let elev = segment.elevationDeltaMeters {
                        statBlock(value: String(format: "+%.0f ft", elev * 3.28084), label: "Elevation gain")
                    }
                }
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Readiness score")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .tracking(1)

            HStack {
                Text(segment.strikeLabel)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(pillColor)
                Spacer()
                Text(String(format: "%.0f", segment.strikeScore * 100))
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(pillColor)
            }
            Text(strikeLine)
                .font(.system(.subheadline))
                .foregroundStyle(Color.enzoSecondary)
                .lineSpacing(3)
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var goalBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.enzoAccent)
            Text("This is your current goal")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoAccent)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.enzoAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var goalSettingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasTargetDate) {
                Text("Set a target date")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoPrimary)
            }
            .tint(Color.enzoAccent)

            if hasTargetDate {
                DatePicker(
                    "Target date",
                    selection: $targetDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .foregroundStyle(Color.enzoPrimary)
            }

            Button {
                appState.setGoal(segment, targetDate: hasTargetDate ? targetDate : nil)
                dismiss()
            } label: {
                Text("Set this goal")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.enzoAccent, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var askEnzoButton: some View {
        Button {
            Task { await askEnzo() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15, weight: .semibold))
                Text("Ask Enzo")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(Color.enzoAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.enzoAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Helpers

    private func statBlock(value: String, label: String, mono: Bool = false, color: Color = Color.enzoPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(mono ? .system(.title2, design: .monospaced, weight: .bold) : .system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedPRDate(_ dateString: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = TimeZone(identifier: "UTC")
        guard let date = input.date(from: dateString) else { return dateString }
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .none
        return output.string(from: date)
    }

    // MARK: - Enzo messaging

    private func askEnzo() async {
        let prompt = AppState.segmentAssessmentPrompt(segment: segment, athleteContext: appState.athleteContext)
        let userMessage = ArcMessage(role: .user, content: prompt)
        messages.append(userMessage)
        isStreaming = true
        streamingText = ""

        let stream = await appState.sendSegmentMessage(prompt, segment: segment, history: [])
        for await token in stream {
            streamingText += token
        }

        if !streamingText.isEmpty {
            messages.append(ArcMessage(role: .enzo, content: streamingText))
        }
        streamingText = ""
        isStreaming = false
    }

    private func sendFollowUp(_ text: String) async {
        let userMessage = ArcMessage(role: .user, content: text)
        messages.append(userMessage)
        isStreaming = true
        streamingText = ""

        // Pass the full history (excluding the just-appended user message, since
        // sendSegmentMessage appends userMessage as the final turn internally).
        let history = Array(messages.dropLast())
        let stream = await appState.sendSegmentMessage(text, segment: segment, history: history)
        for await token in stream {
            streamingText += token
        }

        if !streamingText.isEmpty {
            messages.append(ArcMessage(role: .enzo, content: streamingText))
        }
        streamingText = ""
        isStreaming = false
    }
}

#Preview {
    NavigationStack {
        SegmentDetailView(segment: SegmentScore.previewSegments[0])
    }
    .environment(AppState())
}
