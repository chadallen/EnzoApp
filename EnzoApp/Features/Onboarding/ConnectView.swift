import SwiftUI

struct ConnectView: View {
    @Environment(AppState.self) private var appState
    @State private var isConnecting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            VStack(spacing: 24) {
                Image("EnzoIcon")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 13.5))

                Text(Config.connectWelcomeText)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    Task { await connect() }
                } label: {
                    Group {
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Connect")
                                .font(.system(.body, design: .default, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .background(Color.enzoAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isConnecting)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(.caption))
                        .foregroundStyle(Color.enzoAmber)
                        .multilineTextAlignment(.center)
                }

                Text("Your data stays on your device. Enzo only reads your ride history — it never posts or modifies anything.")
                    .font(.system(.caption))
                    .foregroundStyle(Color.enzoSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
            .background(Color.enzoBg)
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        do {
            try await appState.authenticate(contextProvider: WindowContextProvider())
            Task { await appState.startOnboardingSync() }
        } catch {
            errorMessage = "Strava couldn't connect — tap to retry."
            isConnecting = false
        }
    }
}

#Preview {
    ConnectView()
        .environment(AppState())
}
