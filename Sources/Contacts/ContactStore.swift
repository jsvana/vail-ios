// ContactStore.swift
// Owns the contact list. Persists to a JSON file in Application Support.
// Mirrors SkedStore's shape and persistence approach.

import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.jsvana.VailMorse", category: "contact-store")

@MainActor
public final class ContactStore: ObservableObject {
    @Published public private(set) var contacts: [Contact] = []

    private let fileURL: URL

    private struct Persisted: Codable {
        var contacts: [Contact]
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Lookup

    /// Case-insensitive lookup by callsign.
    public func contact(forCallsign callsign: String) -> Contact? {
        let key = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return nil }
        return contacts.first { $0.callsign == key }
    }

    public func isKnown(_ callsign: String) -> Bool {
        contact(forCallsign: callsign) != nil
    }

    // MARK: - CRUD

    public func upsert(_ contact: Contact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        } else {
            contacts.append(contact)
        }
        sort()
        persist()
    }

    public func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        persist()
    }

    public func delete(at offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
        persist()
    }

    public func toggleFavorite(_ contact: Contact) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[idx].isFavorite.toggle()
        sort()
        persist()
    }

    /// Stamp `lastWorked` for any contacts whose callsign appears in `callsigns`.
    /// Called when a sked run ends, from the run's sampled participants.
    public func markWorked(callsigns: [String], at date: Date = Date()) {
        let keys = Set(callsigns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        guard !keys.isEmpty else { return }
        var changed = false
        for idx in contacts.indices where keys.contains(contacts[idx].callsign) {
            contacts[idx].lastWorked = date
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            contacts = decoded.contacts
            sort()
        } catch {
            log.error("Failed to decode contacts: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(Persisted(contacts: contacts))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to persist contacts: \(error.localizedDescription)")
        }
    }

    /// Favorites first, then alphabetical by callsign.
    private func sort() {
        contacts.sort { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
            return a.callsign.localizedCaseInsensitiveCompare(b.callsign) == .orderedAscending
        }
    }

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let dir = (try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ))
            ?? fm.temporaryDirectory
        return dir.appendingPathComponent("contacts.json")
    }
}
