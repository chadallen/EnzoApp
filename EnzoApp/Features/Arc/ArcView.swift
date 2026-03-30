import SwiftUI
import AuthenticationServices

// TEMP: smoke test helper — remove after Step 6 is verified
private class WindowContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

struct ArcView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy? = nil
    // TEMP: smoke test — remove after Step 6 is verified
    @State private var isConnecting = false
    @State private var connectError: String? = nil
    private let contextProvider = WindowContextProvider()

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
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text("Enzo")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
            Spacer()
            // TEMP: smoke test — remove after Step 6 is verified
            Button {
                isConnecting = true
                connectError = nil
                Task {
                    do {
                        try await appState.authenticate(contextProvider: contextProvider)
                        print("✅ OAuth success — athlete ID: \(appState.stravaAthleteId ?? -1)")
                    } catch {
                        connectError = error.localizedDescription
                        print("❌ OAuth error: \(error)")
                    }
                    isConnecting = false
                }
            } label: {
                if isConnecting {
                    ProgressView()
                        .tint(Color.enzoAccent)
                        .frame(width: 22, height: 22)
                } else if appState.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.enzoGoal)
                } else {
                    Text("Connect")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoAccent)
                }
            }
            .disabled(isConnecting || appState.isAuthenticated)
            // END TEMP
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ArcBriefingView(text: AthleteContext.previewBriefing)

                    LookaheadSuggestionView(text: AthleteContext.previewLookahead)

                    FitnessChartView(
                        snapshots: appState.fitnessSnapshots,
                        goalValue: context.goal.requiredFitnessValue,
                        contextText: AthleteContext.previewChartContext
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
