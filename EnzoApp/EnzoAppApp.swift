//
//  EnzoAppApp.swift
//  EnzoApp
//
//  Created by Chad Allen on 3/28/26.
//

import SwiftUI

@main
struct EnzoAppApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if !appState.isAuthenticated {
                ConnectPlaceholderView()
                    .environment(appState)
            } else if !appState.hasCompletedOnboarding {
                GoalSettingView(onGoalConfirmed: { appState.hasCompletedOnboarding = true })
                    .environment(appState)
            } else {
                MainTabView()
                    .environment(appState)
            }
        }
    }
}

/// Placeholder for the Connect screen — replaced by ConnectView in Chunk 2.
struct ConnectPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "figure.outdoor.cycle")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.enzoAccent)
                Text("Connect Strava")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoPrimary)
                Text("Coming soon — Chunk 2")
                    .font(.system(.caption))
                    .foregroundStyle(Color.enzoSecondary)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ArcView()
                .tabItem {
                    Label("Arc", systemImage: "waveform.path.ecg")
                }
            SegmentsView()
                .tabItem {
                    Label("Segments", systemImage: "flag.checkered")
                }
        }
        .tint(Color.enzoAccent)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.enzoCard, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
