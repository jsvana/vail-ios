// SkedModels.swift
// Data model for the sked (scheduled contact) manager.
//
// A "sked" is a prearranged on-air meeting: a channel + a time, optionally
// recurring, with a reminder lead and a set of expected callsigns. Past runs
// are recorded as SkedRun for history. See CLAUDE.md for app architecture.

import Foundation

/// Day of week, matching `Calendar`'s 1-based weekday numbering (Sunday = 1).
public enum Weekday: Int, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var id: Int {
        rawValue
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Two-letter label for compact toggles ("Mo", "Tu", …).
    public var shortLabel: String {
        switch self {
        case .sunday: "Su"
        case .monday: "Mo"
        case .tuesday: "Tu"
        case .wednesday: "We"
        case .thursday: "Th"
        case .friday: "Fr"
        case .saturday: "Sa"
        }
    }
}

/// How a sked repeats.
public enum Recurrence: Codable, Equatable, Sendable {
    case once
    case daily
    case weekly(days: Set<Weekday>)
}

/// A scheduled contact.
public struct Sked: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var channel: String
    /// For `.once`, the full date+time of the contact. For `.daily`/`.weekly`,
    /// only the time-of-day component is significant (the day is derived from
    /// the recurrence rule).
    public var startDate: Date
    public var recurrence: Recurrence
    public var reminderLeadMinutes: Int
    public var expectedCallsigns: [String]
    public var notes: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        channel: String = "General",
        startDate: Date = Date(),
        recurrence: Recurrence = .once,
        reminderLeadMinutes: Int = 10,
        expectedCallsigns: [String] = [],
        notes: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.startDate = startDate
        self.recurrence = recurrence
        self.reminderLeadMinutes = reminderLeadMinutes
        self.expectedCallsigns = expectedCallsigns
        self.notes = notes
        self.isEnabled = isEnabled
    }

    /// Next occurrence strictly after `reference`, honoring the recurrence rule.
    /// Returns nil for a one-off sked whose time has already passed.
    public func nextOccurrence(after reference: Date, calendar: Calendar = .current) -> Date? {
        switch recurrence {
        case .once:
            return startDate > reference ? startDate : nil

        case .daily:
            let time = calendar.dateComponents([.hour, .minute, .second], from: startDate)
            return calendar.nextDate(after: reference, matching: time, matchingPolicy: .nextTime)

        case let .weekly(days):
            guard !days.isEmpty else { return nil }
            var time = calendar.dateComponents([.hour, .minute, .second], from: startDate)
            var candidates: [Date] = []
            for day in days {
                time.weekday = day.rawValue
                if let next = calendar.nextDate(after: reference, matching: time, matchingPolicy: .nextTime) {
                    candidates.append(next)
                }
            }
            return candidates.min()
        }
    }

    /// Human-readable recurrence summary, e.g. "Weekly · Mo We Fr".
    public func recurrenceDescription(calendar _: Calendar = .current) -> String {
        switch recurrence {
        case .once:
            return "Once"
        case .daily:
            return "Daily"
        case let .weekly(days):
            let ordered = days.sorted().map(\.shortLabel).joined(separator: " ")
            return ordered.isEmpty ? "Weekly" : "Weekly · \(ordered)"
        }
    }
}

/// Outcome of a sked that the user actually engaged with.
public enum SkedOutcome: String, Codable, Sendable {
    case completed
    case skipped
}

/// A recorded run of a sked, for history.
public struct SkedRun: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let skedID: UUID
    /// Title/channel are snapshotted so history survives editing or deleting
    /// the originating sked.
    public let title: String
    public let channel: String
    public let scheduledAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var participants: [String]
    public var outcome: SkedOutcome

    public init(
        id: UUID = UUID(),
        skedID: UUID,
        title: String,
        channel: String,
        scheduledAt: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        participants: [String] = [],
        outcome: SkedOutcome = .completed
    ) {
        self.id = id
        self.skedID = skedID
        self.title = title
        self.channel = channel
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.participants = participants
        self.outcome = outcome
    }

    /// Elapsed time between start and end, if both are known.
    public var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}
