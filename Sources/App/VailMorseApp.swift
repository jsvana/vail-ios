// VailMorseApp.swift
// App entry point.

import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted (with userInfo["skedID": UUID]) when a sked reminder is tapped.
    static let skedJoinRequested = Notification.Name("skedJoinRequested")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show reminders even while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // Route a tapped reminder (or its Join action) to the runner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let idString = response.notification.request.content.userInfo["skedID"] as? String,
           let id = UUID(uuidString: idString) {
            NotificationCenter.default.post(
                name: .skedJoinRequested, object: nil, userInfo: ["skedID": id])
        }
        completionHandler()
    }
}

@main
struct VailMorseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var session = VailSession()
    @StateObject private var skedStore: SkedStore
    @StateObject private var skedRunner: SkedRunner

    private let skedNotifier: SkedNotifier

    init() {
        let notifier = SkedNotifier()
        let store = SkedStore(notifier: notifier)
        skedNotifier = notifier
        _skedStore = StateObject(wrappedValue: store)
        _skedRunner = StateObject(wrappedValue: SkedRunner(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(skedStore)
                .environmentObject(skedRunner)
                .onAppear {
                    session.start()
                    session.connect()
                    skedRunner.attach(session)
                    skedRunner.startMonitoring()
                    skedNotifier.registerCategory()
                    Task { await skedStore.requestNotificationAuthorization() }
                    // Keep screen awake while connected.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .skedJoinRequested)) { note in
                    if let id = note.userInfo?["skedID"] as? UUID {
                        skedRunner.presentJoinPrompt(skedID: id)
                    }
                }
        }
    }
}
