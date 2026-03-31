import SwiftUI

struct ConnectView: View {
    @Environment(AppState.self) private var appState
    @State private var isConnecting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "figure.outdoor.cycle")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.enzoAccent)

                    Text("Enzo")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.enzoPrimary)

                    Text("Meet Enzo. Your cycling companion.")
                        .font(.system(.body))
                        .foregroundStyle(Color.enzoSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await connect() }
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView()
                                    .tint(Color.enzoBg)
                            } else {
                                Text("Connect Strava")
                                    .font(.system(.body, design: .default, weight: .semibold))
                                    .foregroundStyle(Color.enzoBg)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .background(Color.enzoAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .disabled(isConnecting)

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.caption))
                            .foregroundStyle(Color.enzoAmber)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
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
