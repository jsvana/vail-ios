// ContactModels.swift
// Data model for the contacts/friends manager.
//
// A Contact is a locally-stored operator the user wants to keep track of and
// meet on air. The Vail server has no presence or friends API — the only
// people-data on the wire is the per-channel roster (UsersInfo). Contacts are
// therefore device-local and matched against live/probed rosters by callsign.
// See ContactPresenceScanner for the cross-channel "find on air" mechanism.

import Foundation

/// A saved operator the user wants to track and sked with.
public struct Contact: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Canonical key, always uppercased. Matched against roster callsigns.
    public var callsign: String
    /// Operator name or nickname; falls back to the callsign for display.
    public var name: String
    public var notes: String
    public var isFavorite: Bool
    /// Channel this operator is usually found on (used as a scan hint and a
    /// default for skeds).
    public var preferredChannel: String?
    /// Their advertised TX tone (MIDI note), captured when known. Display only.
    public var preferredTxTone: Int?
    public let dateAdded: Date
    /// Last time this contact was seen in a sked run we joined.
    public var lastWorked: Date?

    public init(
        id: UUID = UUID(),
        callsign: String,
        name: String = "",
        notes: String = "",
        isFavorite: Bool = false,
        preferredChannel: String? = nil,
        preferredTxTone: Int? = nil,
        dateAdded: Date = Date(),
        lastWorked: Date? = nil
    ) {
        self.id = id
        self.callsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.name = name
        self.notes = notes
        self.isFavorite = isFavorite
        self.preferredChannel = preferredChannel
        self.preferredTxTone = preferredTxTone
        self.dateAdded = dateAdded
        self.lastWorked = lastWorked
    }

    /// Name if set, otherwise the callsign.
    public var displayName: String {
        name.isEmpty ? callsign : name
    }
}
