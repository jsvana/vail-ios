// SkedRunner.swift
// Coordinates "running" a sked against the live VailSession.
//
// Per the chosen design, a sked is never auto-joined: when an occurrence is
// near (in-app) or a reminder is tapped, we surface a one-tap Join banner.
// Tapping Join switches to the sked's channel, opens a SkedRun, samples the
// roster for participants, and records the run to history on End.

import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.jsvana.VailMorse", category: "sked-runner")

@MainActor
public final class SkedRunner: ObservableObject {

    /// A sked awaiting the user's one-tap Join (banner state).
    @Published public private(set) var pendingSked: Sked?
    /// The currently running sked, if any.
    @Published public private(set) var activeRun: SkedRun?

    private let store: SkedStore
    private weak var session: VailSession?
    private weak var contacts: ContactStore?

    private var pendingOccurrence: Date?
    /// Occurrences the user has already acted on (joined or dismissed), keyed by
    /// "skedID@occurrenceEpoch", so the banner does not nag for the same one.
    private var handledKeys: Set<String> = []

    private var monitorTask: Task<Void, Never>?
    private var samplerTask: Task<Void, Never>?

    /// How long after an occurrence the in-app Join banner stays offered.
    private static let graceWindow: TimeInterval = 15 * 60
    private static let monitorInterval: TimeInterval = 30
    private static let samplerInterval: TimeInterval = 5

    public init(store: SkedStore) {
        self.store = store
    }

    public func attach(_ session: VailSession) {
        self.session = session
    }

    public func attachContacts(_ contacts: ContactStore) {
        self.contacts = contacts
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluateBanner()
                try? await Task.sleep(for: .seconds(Self.monitorInterval))
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func evaluateBanner() {
        guard activeRun == nil, pendingSked == nil else { return }
        let now = Date()
        let calendar = Calendar.current
        let searchFrom = now.addingTimeInterval(-Self.graceWindow)

        var best: (sked: Sked, occurrence: Date)?
        for sked in store.skeds where sked.isEnabled {
            guard let occ = sked.nextOccurrence(after: searchFrom, calendar: calendar) else { continue }
            let lead = TimeInterval(sked.reminderLeadMinutes * 60)
            let windowStart = occ.addingTimeInterval(-lead)
            let windowEnd = occ.addingTimeInterval(Self.graceWindow)
            guard now >= windowStart, now <= windowEnd else { continue }
            guard !handledKeys.contains(key(sked.id, occ)) else { continue }
            if best == nil || occ < best!.occurrence {
                best = (sked, occ)
            }
        }

        if let best {
            pendingSked = best.sked
            pendingOccurrence = best.occurrence
        }
    }

    // MARK: - Reminder routing

    /// Called when a reminder notification (or its Join action) is tapped.
    public func presentJoinPrompt(skedID: UUID) {
        guard let sked = store.skeds.first(where: { $0.id == skedID }) else { return }
        let now = Date()
        let occ = sked.nextOccurrence(after: now.addingTimeInterval(-Self.graceWindow)) ?? now
        pendingSked = sked
        pendingOccurrence = occ
    }

    // MARK: - Run lifecycle

    public func join(_ sked: Sked) {
        let occ = pendingOccurrence ?? Date()
        handledKeys.insert(key(sked.id, occ))

        if session?.channel != sked.channel {
            session?.switchChannel(sked.channel)
        } else {
            session?.connect()
        }

        activeRun = SkedRun(
            skedID: sked.id,
            title: sked.title,
            channel: sked.channel,
            scheduledAt: occ,
            startedAt: Date(),
            participants: [],
            outcome: .completed
        )
        pendingSked = nil
        pendingOccurrence = nil
        startSampling()
        log.info("Joined sked \(sked.title, privacy: .public) on \(sked.channel, privacy: .public)")
    }

    /// Dismiss the Join prompt without joining; records a skipped run.
    public func dismissPrompt() {
        guard let sked = pendingSked else { return }
        let occ = pendingOccurrence ?? Date()
        handledKeys.insert(key(sked.id, occ))
        store.record(SkedRun(
            skedID: sked.id,
            title: sked.title,
            channel: sked.channel,
            scheduledAt: occ,
            outcome: .skipped
        ))
        pendingSked = nil
        pendingOccurrence = nil
    }

    public func endActiveRun() {
        guard var run = activeRun else { return }
        run.endedAt = Date()
        run.outcome = .completed
        store.record(run)
        contacts?.markWorked(callsigns: run.participants)
        activeRun = nil
        stopSampling()
        log.info("Ended sked run \(run.title, privacy: .public)")
    }

    // MARK: - Participant sampling

    private func startSampling() {
        samplerTask?.cancel()
        samplerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleParticipants()
                try? await Task.sleep(for: .seconds(Self.samplerInterval))
            }
        }
    }

    private func stopSampling() {
        samplerTask?.cancel()
        samplerTask = nil
    }

    private func sampleParticipants() {
        guard var run = activeRun, let session else { return }
        var seen = Set(run.participants)
        for user in session.users where !user.callsign.isEmpty {
            seen.insert(user.callsign)
        }
        let merged = seen.sorted()
        if merged != run.participants {
            run.participants = merged
            activeRun = run
        }
    }

    private func key(_ id: UUID, _ occurrence: Date) -> String {
        "\(id.uuidString)@\(Int(occurrence.timeIntervalSince1970))"
    }
}
