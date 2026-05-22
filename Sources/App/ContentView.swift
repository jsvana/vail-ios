// ContentView.swift
// Root view. Tab structure on iPhone, split view on iPad.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: VailSession
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    private var iPhoneLayout: some View {
        TabView {
            OperatingView()
                .tabItem { Label("Key", systemImage: "circle.grid.cross") }
            RosterView()
                .tabItem { Label("Roster", systemImage: "person.3") }
            ChannelPickerView()
                .tabItem { Label("Channels", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                Section("Channels") { ChannelPickerView() }
                Section("Roster") { RosterView() }
            }
            .navigationTitle("Vail")
        } detail: {
            OperatingView()
        }
    }
}
