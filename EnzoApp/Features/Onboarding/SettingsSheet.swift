import SwiftUI

struct SettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

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
        }
    }

    // MARK: - Sync section

    private var syncSection: some View {
        VStack(spacing: 1) {
            actionRow(
                icon: "arrow.trianglehead.2.clockwise",
                label: "Sync now",
                sublabel: appState.isSyncing || appState.isSyncingPhase2
                    ? syncStatusText
                    : nil,
                isDestructive: false
            ) {
                dismiss()
                Task { await appState.syncPhase1() }
            }

            Divider()
                .background(Color.enzoBg)

            actionRow(
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                label: "Reset sync history",
                sublabel: "Re-fetches all activities on next sync",
                isDestructive: false
            ) {
                appState.resetSyncHistory()
                dismiss()
                Task { await appState.syncPhase1() }
            }
        }
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var syncStatusText: String {
        if appState.isSyncing { return "Phase 1 running..." }
        if appState.isSyncingPhase2 { return "Phase 2 running..." }
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
            dismiss()
            appState.disconnect()
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
                    .foregroundStyle(isDestructive ? Color.enzoAmber : Color.enzoAccent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(isDestructive ? Color.enzoAmber : Color.enzoPrimary)
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
        .preferredColorScheme(.dark)
}
