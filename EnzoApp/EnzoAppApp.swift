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
                Color.enzoBg.ignoresSafeArea()
            } else if appState.isOnboardingSyncing {
                SyncProgressView(onComplete: { appState.isOnboardingSyncing = false })
            } else if !appState.hasCompletedOnboarding {
                GoalSettingView(onGoalConfirmed: { appState.hasCompletedOnboarding = true })
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
    @State private var selectedTab: Tab = .today
    @State private var showSettings = false

    enum Tab: String, CaseIterable {
        case today = "Today"
        case targets = "Targets"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                tabPicker
                Divider()
                    .background(Color.enzoSecondary.opacity(0.15))
                ZStack {
                    ArcView()
                        .opacity(selectedTab == .today ? 1 : 0)
                        .allowsHitTesting(selectedTab == .today)
                    SegmentsView()
                        .opacity(selectedTab == .targets ? 1 : 0)
                        .allowsHitTesting(selectedTab == .targets)
                }
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

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.system(.subheadline, design: .rounded,
                                          weight: selectedTab == tab ? .bold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.enzoPrimary : Color.enzoSecondary)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.enzoAccent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
