import SwiftUI

struct SettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                VStack(spacing: 12) {
                    syncSection
                    disconnectSection
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.enzoAccent)
                }
            }
            .confirmationDialog(
                "Disconnect Strava?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    dismiss()
                    appState.disconnect()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to connect again to sync your rides.")
            }
        }
    }

    // MARK: - Sync section

    private var syncSection: some View {
        actionRow(
            icon: "arrow.trianglehead.2.clockwise",
            label: "Sync now",
            sublabel: syncStatusText.isEmpty ? "Fetch recent rides and update your scores." : syncStatusText,
            isDestructive: false
        ) {
            dismiss()
            Task { await appState.syncV2() }
        }
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var syncStatusText: String {
        if appState.isSyncing {
            return appState.syncProgressMessage.isEmpty ? "Syncing..." : appState.syncProgressMessage
        }
        if let date = appState.lastSyncedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Last synced \(formatter.string(from: date))"
        }
        return ""
    }

    // MARK: - Disconnect section

    private var disconnectSection: some View {
        actionRow(
            icon: "person.slash",
            label: "Disconnect Strava",
            sublabel: nil,
            isDestructive: true
        ) {
            showDisconnectConfirm = true
        }
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Row builder

    private func actionRow(
        icon: String,
        label: String,
        sublabel: String?,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDestructive ? Color(.systemRed) : Color.enzoAccent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(isDestructive ? Color(.systemRed) : Color.enzoPrimary)
                    if let sublabel {
                        Text(sublabel)
                            .font(.system(.caption))
                            .foregroundStyle(Color.enzoSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Color.enzoSecondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

#Preview {
    SettingsSheet()
        .environment(AppState())
}
