import Charts
import SwiftUI

struct SegmentDetailView: View {
    let segment: SegmentScore
    var autoStartChat: Bool = false
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Goal-setting state
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()
    @State private var showGoalToast = false

    // Enzo chat state — session-scoped, cleared on view disappear
    @State private var messages: [ArcMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingText = ""

    private func formattedSeconds(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        readinessCard
                        statsCard

                        if segment.elevationDeltaMeters != nil {
                            elevationCard
                        }

                        if !segment.efforts.isEmpty {
                            effortHistoryCard
                        }

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
                        if messages.contains(where: { !$0.isHidden }) {
                            VStack(spacing: 12) {
                                ForEach(messages.filter { !$0.isHidden }) { message in
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
            if messages.contains(where: { !$0.isHidden }) || isStreaming {
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
        .overlay(alignment: .top) {
            if showGoalToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(.caption, weight: .semibold))
                    Text("Goal set")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(Color.enzoPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.enzoCard, in: Capsule())
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showGoalToast)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.enzoBg, for: .navigationBar)
        .task {
            if autoStartChat {
                await askEnzo()
            }
        }
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
                if !segment.prDate.isEmpty {
                    statBlock(value: formattedPRDate(segment.prDate), label: "Date set")
                }
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
        VStack(spacing: 0) {
            if let prob = segment.prProbability {
                // Valid model — lead with probability, then predicted time, then subordinate CTL detail
                VStack(spacing: 16) {
                    // Primary: probability score
                    VStack(spacing: 6) {
                        Text("\(Int(prob * 100))%")
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.enzoAccent)
                        Text("likely to PR")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.enzoSecondary)
                    }

                    // Strike label pill
                    Text(segment.strikeLabel)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(strikeColor(for: prob))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(strikeColor(for: prob).opacity(0.12), in: Capsule())

                    // Secondary: predicted time ± 1σ
                    if let predicted = segment.predictedTime, let sigma = segment.predictionSigma {
                        VStack(spacing: 4) {
                            Text("Predicted \(formattedSeconds(predicted))")
                                .font(.system(.callout, design: .monospaced, weight: .medium))
                                .foregroundStyle(Color.enzoPrimary)
                            Text("±\(formattedSeconds(sigma)) range")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.enzoSecondary)
                        }
                    }

                    // Extrapolation warning
                    if segment.isExtrapolating {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Outside your training range — estimate is approximate")
                                .font(.system(.caption, design: .rounded))
                        }
                        .foregroundStyle(Color.enzoAmber)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal)

                // Divider between primary and subordinate sections
                Rectangle()
                    .fill(Color.enzoSecondary.opacity(0.12))
                    .frame(height: 1)

                // Subordinate: CTL/TSB context
                VStack(spacing: 6) {
                    if let fallback = segment.naiveFallback {
                        Text(fallback)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Text("Based on \(segment.nEfforts) effort\(segment.nEfforts == 1 ? "" : "s")")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal)

            } else {
                // Invalid model — not enough data state
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.enzoSecondary)

                    Text("Not enough data yet")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoPrimary)

                    if let fallback = segment.naiveFallback {
                        Text(fallback)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    Text(segment.nEfforts < 1 ? "No efforts recorded yet" : "Based on \(segment.nEfforts) effort\(segment.nEfforts == 1 ? "" : "s")")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal)
            }
        }
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // Two-point elevation profile: flat start → rise to delta over distance.
    // TODO: replace with real elevation stream from Strava /segments/{id}/streams?keys=altitude
    // once the segment map spike (EnzoApp-75h.5) determines feasibility.
    private var elevationCard: some View {
        let elevFt = (segment.elevationDeltaMeters ?? 0) * 3.28084
        let distMi = (segment.distanceMeters ?? 1609.0) * 0.000621371
        let data: [(dist: Double, elev: Double)] = [(0, 0), (distMi, max(elevFt, 0))]
        let yMax = max(elevFt, 1) * 1.3

        return VStack(alignment: .leading, spacing: 8) {
            Text("Elevation profile")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .tracking(1)

            Chart {
                ForEach(data.indices, id: \.self) { i in
                    AreaMark(
                        x: .value("Distance", data[i].dist),
                        y: .value("Elevation", data[i].elev)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.enzoChartSecondary.opacity(0.4), Color.enzoChartSecondary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Distance", data[i].dist),
                        y: .value("Elevation", data[i].elev)
                    )
                    .foregroundStyle(Color.enzoChartPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .frame(height: 72)
            .chartXScale(domain: 0...distMi)
            .chartYScale(domain: 0...yMax)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

            HStack {
                Text(String(format: "%.1f mi", distMi))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.enzoSecondary)
                Spacer()
                Text(String(format: "+%.0f ft", elevFt))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(Color.enzoPrimary)
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var effortHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effort history")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 10) {
                ForEach(segment.efforts) { effort in
                    effortRow(effort)
                }
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func effortRow(_ effort: EffortRecord) -> some View {
        let isPR = effort.seconds == segment.prSeconds
        return HStack {
            Text(formattedPRDate(effort.date))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)

            Spacer()

            if isPR {
                Text("PR")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.enzoAccent.opacity(0.1), in: Capsule())
            }

            Text(formattedTime(effort.seconds))
                .font(.system(.subheadline, design: .monospaced, weight: isPR ? .bold : .regular))
                .foregroundStyle(isPR ? Color.enzoAccent : Color.enzoPrimary)
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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
                showGoalToast = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    dismiss()
                }
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
        isStreaming = true
        streamingText = ""
        // Append as hidden — keeps it in history for follow-up context but never renders as a bubble.
        messages.append(ArcMessage(role: .user, content: prompt, isHidden: true))

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

#Preview("Readiness — valid model") {
    // previewSegments[4]: "Bolinas Ridge descent" — 84% strike now, no extrapolation
    NavigationStack {
        SegmentDetailView(segment: SegmentScore.previewSegments[4])
    }
    .environment(AppState())
}

#Preview("Readiness — extrapolating") {
    // previewSegments[3]: "Pantoll to Rock Spring" — 73% almost there, isExtrapolating=true
    NavigationStack {
        SegmentDetailView(segment: SegmentScore.previewSegments[3])
    }
    .environment(AppState())
}

#Preview("Readiness — not enough data") {
    // previewSegments[2]: "Paradise Loop Climb" — prProbability=nil (isValid=false)
    NavigationStack {
        SegmentDetailView(segment: SegmentScore.previewSegments[2])
    }
    .environment(AppState())
}
