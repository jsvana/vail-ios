// SkedNotifier.swift
// Bridges the sked list to the system's local-notification scheduler.
//
// Each enabled sked schedules a reminder at (occurrence − reminderLead). The
// OS handles repetition and timezone/DST for recurring skeds via
// UNCalendarNotificationTrigger. Tapping a reminder (or its "Join" action)
// posts `.skedJoinRequested` so the app can surface the one-tap Join banner.

import Foundation
import UserNotifications
import OSLog

private let log = Logger(subsystem: "com.jsvana.VailMorse", category: "sked-notifier")

public final class SkedNotifier {
    private let center = UNUserNotificationCenter.current()

    /// Prefix for all notification identifiers we own, so a resync can clear
    /// only our requests without disturbing anything else.
    private static let idPrefix = "sked."
    /// Category enabling the "Join" action button on reminders.
    public static let categoryID = "SKED_REMINDER"
    public static let joinActionID = "SKED_JOIN"

    public init() {}

    /// Register the notification category. Call once at launch.
    public func registerCategory() {
        let join = UNNotificationAction(
            identifier: Self.joinActionID,
            title: "Join",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [join],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Prompt for notification permission. Returns whether it is granted.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Notification auth request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Remove all sked reminders and reschedule for the currently enabled skeds.
    public func sync(skeds: [Sked]) {
        Task { await syncAsync(skeds: skeds) }
    }

    private func syncAsync(skeds: [Sked]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            log.debug("Notifications not authorized; skipping schedule")
            return
        }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for sked in skeds where sked.isEnabled {
            for request in requests(for: sked) {
                do {
                    try await center.add(request)
                } catch {
                    log.error("Failed to schedule reminder for \(sked.title, privacy: .public): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancel reminders for a specific sked (e.g. on delete).
    public func cancel(skedID: UUID) {
        Task {
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix + skedID.uuidString) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Request building

    private func requests(for sked: Sked, calendar: Calendar = .current) -> [UNNotificationRequest] {
        let lead = TimeInterval(sked.reminderLeadMinutes * 60)
        let content = makeContent(for: sked)

        switch sked.recurrence {
        case .once:
            let fireDate = sked.startDate.addingTimeInterval(-lead)
            guard fireDate > Date() else { return [] }
            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = Self.idPrefix + sked.id.uuidString
            return [UNNotificationRequest(identifier: id, content: content, trigger: trigger)]

        case .daily:
            // Derive the repeating fire time from a concrete next occurrence so a
            // lead that crosses midnight lands on the right hour/minute.
            guard let occ = sked.nextOccurrence(after: Date(), calendar: calendar) else { return [] }
            let fire = occ.addingTimeInterval(-lead)
            let comps = calendar.dateComponents([.hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let id = Self.idPrefix + sked.id.uuidString
            return [UNNotificationRequest(identifier: id, content: content, trigger: trigger)]

        case .weekly(let days):
            var result: [UNNotificationRequest] = []
            let time = calendar.dateComponents([.hour, .minute, .second], from: sked.startDate)
            for day in days {
                // Concrete next occurrence for this weekday, then back off the
                // lead — this correctly shifts the weekday when the lead crosses
                // midnight (e.g. a Monday 00:05 sked reminds Sunday 23:55).
                var dayTime = time
                dayTime.weekday = day.rawValue
                guard let occ = calendar.nextDate(
                    after: Date(), matching: dayTime, matchingPolicy: .nextTime) else { continue }
                let fire = occ.addingTimeInterval(-lead)
                let comps = calendar.dateComponents([.weekday, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let id = Self.idPrefix + sked.id.uuidString + "#\(day.rawValue)"
                result.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
            return result
        }
    }

    private func makeContent(for sked: Sked) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = sked.title.isEmpty ? "Sked reminder" : sked.title
        let lead = sked.reminderLeadMinutes
        content.body = lead > 0
            ? "On \(sked.channel) in \(lead) min"
            : "On \(sked.channel) now"
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["skedID": sked.id.uuidString]
        return content
    }
}
