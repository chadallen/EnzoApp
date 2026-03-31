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
            RootView()
                .environment(appState)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                ConnectView()
            } else if appState.isResolvingOnboarding {
                // loadContext() is running — hold here to avoid flashing GoalSettingView
                // for existing users whose hasCompletedOnboarding hasn't been set yet.
                Color.enzoBg.ignoresSafeArea()
            } else if !appState.hasCompletedOnboarding {
                GoalSettingView(onGoalConfirmed: { appState.hasCompletedOnboarding = true })
            } else {
                MainTabView()
            }
        }
        .task {
            // Runs loadContext() before the gate resolves, so existing users with
            // a goal auto-set hasCompletedOnboarding and land in MainTabView.
            await appState.loadContext()
        }
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
