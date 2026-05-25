// ContentView.swift
// Root view. Tab structure on iPhone, split view on iPad.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: VailSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasAcknowledgedUnofficial") private var hasAcknowledged = false
    @State private var showAbout = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasAcknowledged },
            set: { hasAcknowledged = !$0 }
        )) {
            UnofficialNoticeView()
        }
    }

    private var iPhoneLayout: some View {
        TabView {
            OperatingView()
                .tabItem { Label("Key", systemImage: "circle.grid.cross") }
            NavigationStack { ContactsView() }
                .tabItem { Label("Contacts", systemImage: "person.crop.circle") }
            NavigationStack { SkedListView() }
                .tabItem { Label("Skeds", systemImage: "calendar") }
            ChannelPickerView()
                .tabItem { Label("Channels", systemImage: "list.bullet") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                Section("Skeds") {
                    NavigationLink {
                        SkedListView()
                    } label: {
                        Label("Manage skeds", systemImage: "calendar")
                    }
                }
                Section("Channels") { ChannelPickerView() }
                Section("Contacts") {
                    NavigationLink {
                        ContactsView()
                    } label: {
                        Label("Saved contacts", systemImage: "person.crop.circle")
                    }
                }
            }
            .navigationTitle("Vail")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showAbout) {
                NavigationStack {
                    AboutView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showAbout = false }
                            }
                        }
                }
            }
        } detail: {
            OperatingView()
        }
    }
}
