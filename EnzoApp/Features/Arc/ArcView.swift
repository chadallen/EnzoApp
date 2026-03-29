import SwiftUI

struct ArcView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    private var context: AthleteContext { appState.athleteContext }

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
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text("Enzo")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
            Spacer()
            Button {
                // Step 11: settings sheet
            } label: {
                Image(systemName: "person.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.enzoSecondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ArcBriefingView(text: AthleteContext.previewBriefing)

                LookaheadSuggestionView(text: AthleteContext.previewLookahead)

                FitnessChartView(
                    snapshots: appState.fitnessSnapshots,
                    goalScore: context.goal.requiredFitnessScore,
                    peakScore: context.peakFitnessScore,
                    contextText: AthleteContext.previewChartContext
                )

                PROpportunitiesCard(segments: appState.segments)

                if !appState.arcMessages.isEmpty {
                    messageThread
                }

                Color.clear.frame(height: 100)
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
    }

    private var messageThread: some View {
        VStack(spacing: 12) {
            ForEach(appState.arcMessages) { message in
                ArcMessageView(message: message)
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            PromptChipsView(chips: PromptChipsView.defaultChips) { chip in
                inputText = chip
            }
            ArcInputBar(text: $inputText) { text in
                // Step 3: wire to ClaudeService
                let userMsg = ArcMessage(role: .user, content: text)
                appState.arcMessages.append(userMsg)
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
