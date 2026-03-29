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
            MainTabView()
                .environment(appState)
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
    }
}
