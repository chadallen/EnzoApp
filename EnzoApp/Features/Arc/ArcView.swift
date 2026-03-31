import SwiftUI

struct ArcView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var showSettings = false

    private var context: AthleteContext { appState.athleteContext }
    private var showThread: Bool { !appState.arcMessages.isEmpty || appState.isStreaming }

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                GoalHeaderView(context: context)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()
                    .background(Color.enzoSecondary.opacity(0.1))

                scrollContent
            }
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

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text("Enzo")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.enzoSecondary)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
                    .environment(appState)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ArcBriefingView(
                        text: appState.briefingText,
                        isLoading: appState.isGeneratingBriefing
                    ) {
                        Task { await appState.generateBriefing() }
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
                .padding(.top, 16)
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
                .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    ArcView()
        .environment(AppState())
}
