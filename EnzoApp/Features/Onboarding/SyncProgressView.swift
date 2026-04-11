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

    // Copy phases
    private enum SyncPhase: Int, CaseIterable {
        case findingRides     = 0  // Phase 1
        case trackingProgress = 1  // Phase 1
        case bestEfforts      = 2  // Phase 1
        case computingFitness = 3  // Phase 1
        case findingSegments  = 4  // Phase 2
        case checkingPRs      = 5  // Phase 2
        case analyzingOpps    = 6  // Phase 2
        case scoringEfforts   = 7  // Phase 2
        case almostReady      = 8  // Completion

        var text: String {
            switch self {
            case .findingRides:     return "Finding your rides..."
            case .trackingProgress: return "Tracking your progress..."
            case .bestEfforts:      return "Checking your best efforts..."
            case .computingFitness: return "Computing your fitness..."
            case .findingSegments:  return "Finding your segments..."
            case .checkingPRs:      return "Checking PRs..."
            case .analyzingOpps:    return "Analyzing opportunities..."
            case .scoringEfforts:   return "Scoring your efforts..."
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
                // Phase text with crossfade
                Text(SyncPhase(rawValue: phaseIndex)?.text ?? SyncPhase.almostReady.text)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundColor(.enzoPrimary)
                    .multilineTextAlignment(.center)
                    .id(phaseIndex)
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
        // Phase cycling timer
        .onReceive(phaseTick) { _ in
            advancePhase()
        }
        // Start detection + completion detection for isSyncing
        .onChange(of: appState.isSyncing) { _, newValue in
            if newValue { syncHasStarted = true }
            checkCompletion()
        }
        // Start detection + completion detection for isSyncingPhase2
        .onChange(of: appState.isSyncingPhase2) { _, newValue in
            if newValue { syncHasStarted = true }
            checkCompletion()
        }
    }

    // MARK: - Helpers

    private func advancePhase() {
        let nextIndex: Int
        if appState.isSyncing {
            // Cycle phases 0–3 during Phase 1
            let current = phaseIndex <= 3 ? phaseIndex : 0
            nextIndex = current < 3 ? current + 1 : 0
        } else if appState.isSyncingPhase2 {
            // Cycle phases 4–7 during Phase 2
            let current = phaseIndex >= 4 ? phaseIndex : 4
            nextIndex = current < 7 ? current + 1 : 4
        } else {
            return
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            phaseIndex = nextIndex
        }
    }

    private func checkCompletion() {
        guard syncHasStarted,
              !appState.isSyncing,
              !appState.isSyncingPhase2,
              !completionFired else { return }

        completionFired = true

        // Show "Enzo is almost ready..." then hand off
        withAnimation(.easeInOut(duration: 0.5)) {
            phaseIndex = SyncPhase.almostReady.rawValue  // 8
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
