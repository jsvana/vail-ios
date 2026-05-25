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
            NavigationStack { ChatView() }
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .badge(session.unreadChatCount)
            NavigationStack { RosterView() }
                .tabItem { Label("Roster", systemImage: "person.crop.circle") }
            ChannelPickerView()
                .tabItem { Label("Channels", systemImage: "list.bullet") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                Section("Chat") {
                    NavigationLink {
                        ChatView()
                    } label: {
                        HStack {
                            Label("Channel chat", systemImage: "bubble.left.and.bubble.right")
                            Spacer()
                            if session.unreadChatCount > 0 {
                                Text("\(session.unreadChatCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                    }
                }
                Section("Roster") {
                    NavigationLink {
                        RosterView()
                    } label: {
                        Label("Contacts & skeds", systemImage: "person.crop.circle")
                    }
                }
                Section("Channels") { ChannelPickerView() }
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
