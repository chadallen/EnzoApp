//
//  SyncProgressView.swift
//  EnzoApp
//

import SwiftUI
import Combine

// MARK: - SyncProgressView

struct SyncProgressView: View {
    @Environment(AppState.self) private var appState
    let onComplete: () -> Void

    // Copy phases — cycled automatically while isSyncing is true.
    private enum SyncPhase: Int, CaseIterable {
        case findingRides     = 0
        case trackingProgress = 1
        case computingFitness = 2
        case findingSegments  = 3
        case analyzingOpps    = 4
        case fittingModels    = 5
        case almostReady      = 6

        var text: String {
            switch self {
            case .findingRides:     return "Fetching your rides..."
            case .trackingProgress: return "Computing your fitness..."
            case .computingFitness: return "Building fitness timeline..."
            case .findingSegments:  return "Fetching your segments..."
            case .analyzingOpps:    return "Analyzing opportunities..."
            case .fittingModels:    return "Fitting performance models..."
            case .almostReady:      return "Enzo is almost ready..."
            }
        }
    }

    @State private var phaseIndex: Int = 0

    // Completion tracking
    @State private var syncHasStarted = false
    @State private var completionFired = false

    // Timers
    private let secondTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let phaseTick  = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    @State private var elapsed: Int = 0

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.enzoAccent)

                // Phase text with crossfade — prefer live progress message when available.
                let displayText = appState.syncProgressMessage.isEmpty
                    ? (SyncPhase(rawValue: phaseIndex)?.text ?? SyncPhase.almostReady.text)
                    : appState.syncProgressMessage
                Text(displayText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundColor(.enzoPrimary)
                    .multilineTextAlignment(.center)
                    .id(displayText)
                    .transition(.opacity)

                // Activity counter
                if appState.syncedActivityCount > 0 {
                    Text("\(appState.syncedActivityCount) rides and counting")
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                        .foregroundColor(.enzoSecondary)
                        .transition(.opacity)
                }

                // Long-sync message (> 60s)
                if elapsed >= 60 {
                    Text("Big history — this is worth it.")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundColor(.enzoSecondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 40)
        }
        // Elapsed timer
        .onReceive(secondTick) { _ in
            elapsed += 1
        }
        // Phase cycling timer (fallback when syncProgressMessage is empty)
        .onReceive(phaseTick) { _ in
            advancePhase()
        }
        // Start detection + completion detection
        .onChange(of: appState.isSyncing) { _, newValue in
            if newValue { syncHasStarted = true }
            checkCompletion()
        }
    }

    // MARK: - Helpers

    private func advancePhase() {
        guard appState.isSyncing else { return }
        let maxPhase = SyncPhase.fittingModels.rawValue
        let nextIndex = phaseIndex < maxPhase ? phaseIndex + 1 : 0
        withAnimation(.easeInOut(duration: 0.5)) {
            phaseIndex = nextIndex
        }
    }

    private func checkCompletion() {
        guard syncHasStarted,
              !appState.isSyncing,
              !completionFired else { return }

        completionFired = true

        // Show "Enzo is almost ready..." then hand off
        withAnimation(.easeInOut(duration: 0.5)) {
            phaseIndex = SyncPhase.almostReady.rawValue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onComplete()
        }
    }
}

// MARK: - Preview

#Preview {
    SyncProgressView(onComplete: {})
        .environment(AppState())
}
