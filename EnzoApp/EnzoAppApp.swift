//
//  EnzoAppApp.swift
//  EnzoApp
//
//  Created by Chad Allen on 3/28/26.
//

import SwiftUI
import SwiftData

@main
struct EnzoAppApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.light)
        }
        .modelContainer(ModelContainer.enzo)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                ConnectView()
            } else if appState.isResolvingOnboarding {
                Color.enzoBg.ignoresSafeArea()
            } else if appState.isOnboardingSyncing {
                SyncProgressView(onComplete: {
                    appState.isOnboardingSyncing = false
                    appState.hasCompletedOnboarding = true
                })
            } else {
                MainTabView()
            }
        }
        .task {
            await appState.loadContext()
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Divider()
                    .background(Color.enzoSecondary.opacity(0.15))
                SegmentsView()
            }
            .background(Color.enzoBg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environment(appState)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Enzo")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.enzoSecondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
