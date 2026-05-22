// VailMorseApp.swift
// App entry point.

import SwiftUI
import UIKit

@main
struct VailMorseApp: App {
    @StateObject private var session = VailSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onAppear {
                    session.start()
                    session.connect()
                    // Keep screen awake while connected.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
    }
}
