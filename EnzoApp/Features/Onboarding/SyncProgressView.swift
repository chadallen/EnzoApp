//
//  SyncProgressView.swift
//  EnzoApp
//

import SwiftUI
import Combine

// MARK: - Route Shape

/// Abstract cycling route: rolling approach → switchback hairpin → sustained climb.
/// Uses relative coordinates (0–1) scaled by the proxy size at draw time.
private struct CyclingRoutePath: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * w, y: y * h)
        }

        var p = Path()

        // Start: bottom-left approach
        p.move(to: pt(0.04, 0.78))

        // Roll 1: gentle rise
        p.addCurve(to:       pt(0.18, 0.48),
                   control1: pt(0.09, 0.75),
                   control2: pt(0.14, 0.52))

        // Roll 2: small descent into valley
        p.addCurve(to:       pt(0.30, 0.60),
                   control1: pt(0.22, 0.44),
                   control2: pt(0.27, 0.62))

        // Roll 3: rise to switchback entry
        p.addCurve(to:       pt(0.42, 0.40),
                   control1: pt(0.33, 0.58),
                   control2: pt(0.38, 0.42))

        // Switchback hairpin: reverse direction briefly
        p.addCurve(to:       pt(0.50, 0.50),
                   control1: pt(0.46, 0.36),
                   control2: pt(0.52, 0.42))

        p.addCurve(to:       pt(0.44, 0.35),
                   control1: pt(0.48, 0.55),
                   control2: pt(0.42, 0.40))

        // Exit switchback and begin main climb
        p.addCurve(to:       pt(0.62, 0.28),
                   control1: pt(0.48, 0.28),
                   control2: pt(0.56, 0.26))

        // Sustained climb to summit
        p.addCurve(to:       pt(0.80, 0.18),
                   control1: pt(0.68, 0.28),
                   control2: pt(0.75, 0.20))

        // Final push to top-right
        p.addCurve(to:       pt(0.96, 0.12),
                   control1: pt(0.84, 0.16),
                   control2: pt(0.91, 0.11))

        return p
    }
}

// MARK: - SyncProgressView

struct SyncProgressView: View {
    @Environment(AppState.self) private var appState
    let onComplete: () -> Void

    // Animation
    @State private var progress: Double = 0

    // Copy phases
    private enum SyncPhase: Int, CaseIterable {
        case reading      = 0
        case bestEfforts  = 1
        case fitness      = 2
        case opportunities = 3
        case almostReady  = 4

        var text: String {
            switch self {
            case .reading:       return "Reading your rides..."
            case .bestEfforts:   return "Finding your best efforts..."
            case .fitness:       return "Sizing up your fitness..."
            case .opportunities: return "Scoping your opportunities..."
            case .almostReady:   return "Enzo is almost ready..."
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

            VStack(spacing: 0) {
                // Route animation — upper 55% of screen
                GeometryReader { geo in
                    ZStack {
                        // Faint full path
                        CyclingRoutePath()
                            .stroke(Color.enzoAccent.opacity(0.15), lineWidth: 2)

                        // Animated leading segment with trail
                        CyclingRoutePath()
                            .trim(from: max(0, progress - 0.25), to: progress)
                            .stroke(
                                Color.enzoAccent,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                            )
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)

                // Copy + counter — lower 45%
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
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                progress = 1.0
            }
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
            // Cycle phases 0–1 during Phase 1
            let current = phaseIndex <= 1 ? phaseIndex : 0
            nextIndex = current == 0 ? 1 : 0
        } else if appState.isSyncingPhase2 {
            // Cycle phases 2–4 during Phase 2
            let current = phaseIndex >= 2 ? phaseIndex : 2
            nextIndex = current < 4 ? current + 1 : 2
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
