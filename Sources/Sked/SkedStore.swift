// SkedStore.swift
// Owns the sked list and run history. Persists to a JSON file in Application
// Support and keeps system notifications in sync on every mutation.

import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.jsvana.VailMorse", category: "sked-store")

@MainActor
public final class SkedStore: ObservableObject {
    @Published public private(set) var skeds: [Sked] = []
    @Published public private(set) var history: [SkedRun] = []

    private let notifier: SkedNotifier
    private let fileURL: URL
    private static let historyCap = 200

    private struct Persisted: Codable {
        var skeds: [Sked]
        var history: [SkedRun]
    }

    public init(notifier: SkedNotifier, fileURL: URL? = nil) {
        self.notifier = notifier
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Authorization

    /// Request notification permission and (re)sync reminders.
    public func requestNotificationAuthorization() async {
        await notifier.requestAuthorization()
        notifier.sync(skeds: skeds)
    }

    // MARK: - CRUD

    public func upsert(_ sked: Sked) {
        if let idx = skeds.firstIndex(where: { $0.id == sked.id }) {
            skeds[idx] = sked
        } else {
            skeds.append(sked)
        }
        sortSkeds()
        persistAndSync()
    }

    public func delete(_ sked: Sked) {
        skeds.removeAll { $0.id == sked.id }
        notifier.cancel(skedID: sked.id)
        persistAndSync()
    }

    public func delete(at offsets: IndexSet) {
        let removed = offsets.map { skeds[$0] }
        skeds.remove(atOffsets: offsets)
        for sked in removed {
            notifier.cancel(skedID: sked.id)
        }
        persistAndSync()
    }

    public func setEnabled(_ enabled: Bool, for sked: Sked) {
        guard let idx = skeds.firstIndex(where: { $0.id == sked.id }) else { return }
        skeds[idx].isEnabled = enabled
        if !enabled { notifier.cancel(skedID: sked.id) }
        persistAndSync()
    }

    // MARK: - History

    public func record(_ run: SkedRun) {
        history.removeAll { $0.id == run.id }
        history.insert(run, at: 0)
        if history.count > Self.historyCap {
            history.removeLast(history.count - Self.historyCap)
        }
        persist()
    }

    public func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        persist()
    }

    public func clearHistory() {
        history.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            skeds = decoded.skeds
            history = decoded.history
            sortSkeds()
        } catch {
            log.error("Failed to decode skeds: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(Persisted(skeds: skeds, history: history))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to persist skeds: \(error.localizedDescription)")
        }
    }

    private func persistAndSync() {
        persist()
        notifier.sync(skeds: skeds)
    }

    private func sortSkeds() {
        let now = Date()
        skeds.sort { a, b in
            let an = a.nextOccurrence(after: now) ?? .distantFuture
            let bn = b.nextOccurrence(after: now) ?? .distantFuture
            if an != bn { return an < bn }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let dir = (try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ))
            ?? fm.temporaryDirectory
        return dir.appendingPathComponent("skeds.json")
    }
}
