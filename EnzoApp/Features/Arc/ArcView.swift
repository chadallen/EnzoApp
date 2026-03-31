import SwiftUI

struct ArcView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy? = nil

    private var context: AthleteContext { appState.athleteContext }
    private var showThread: Bool { !appState.arcMessages.isEmpty || appState.isStreaming }

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()
            scrollContent
        }
        .safeAreaInset(edge: .bottom) {
            inputArea
        }
        .task {
            // On each launch: load real data, then generate Arc content.
            // No-ops if not authenticated (supabaseUserId is nil).
            await appState.loadContext()
            async let briefing: Void = appState.generateBriefing()
            async let lookahead: Void = appState.generateLookahead()
            _ = await (briefing, lookahead)
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    GoalHeaderView(context: context)
                        .padding(.top, 12)

                    if let errorMessage = appState.syncErrorMessage {
                        HStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.system(.caption))
                                .foregroundStyle(Color.enzoAmber)
                            Spacer()
                            Button {
                                Task { await appState.syncPhase1() }
                            } label: {
                                Text("Retry")
                                    .font(.system(.caption, weight: .semibold))
                                    .foregroundStyle(Color.enzoAmber)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.enzoAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    ArcBriefingView(
                        text: appState.briefingText,
                        isLoading: appState.isGeneratingBriefing
                    ) {
                        Task { await appState.generateBriefing(forceRefresh: true) }
                    }

                    LookaheadSuggestionView(
                        text: appState.lookaheadText,
                        isLoading: appState.isGeneratingLookahead
                    )

                    FitnessChartView(
                        snapshots: appState.fitnessSnapshots,
                        goalValue: context.goal.requiredFitnessValue,
                        contextText: appState.briefingText.isEmpty
                            ? AthleteContext.previewChartContext
                            : String(appState.briefingText.prefix(120))
                    )

                    PROpportunitiesCard(segments: appState.segments)

                    if showThread {
                        messageThread
                    }

                    Color.clear.frame(height: 100).id("bottom")
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: appState.arcMessages.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: appState.streamingText) {
                proxy.scrollTo("bottom")
            }
        }
    }

    private var messageThread: some View {
        VStack(spacing: 12) {
            ForEach(appState.arcMessages) { message in
                ArcMessageView(message: message)
            }
            if appState.isStreaming {
                ArcMessageView(
                    message: ArcMessage(
                        role: .enzo,
                        content: appState.streamingText.isEmpty ? "..." : appState.streamingText
                    )
                )
                .id("streaming")
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            PromptChipsView(chips: PromptChipsView.defaultChips) { chip in
                Task {
                    await appState.sendMessage(chip)
                }
            }
            ArcInputBar(text: $inputText, isSending: appState.isStreaming) { text in
                Task {
                    await appState.sendMessage(text)
                }
            }
        }
        .background(
            Color.enzoBg
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    ArcView()
        .environment(AppState())
}
