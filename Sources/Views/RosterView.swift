// RosterView.swift
// People hub: the live channel roster ("Connected") and saved contacts
// ("Contacts"), switchable via a segmented control. Contacts augment skeds and
// can be located across channels with the presence scanner.

import SwiftUI

struct RosterView: View {
    @EnvironmentObject var session: VailSession
    @EnvironmentObject var contacts: ContactStore
    @EnvironmentObject var scanner: ContactPresenceScanner

    private enum Segment: String, CaseIterable, Identifiable {
        case connected = "Connected"
        case contacts = "Contacts"
        var id: String { rawValue }
    }

    private enum Editor: Identifiable {
        case new
        case prefilled(callsign: String, txTone: Int?)
        case edit(Contact)
        var id: String {
            switch self {
            case .new: "new"
            case .prefilled(let cs, _): "prefill-\(cs)"
            case .edit(let contact): contact.id.uuidString
            }
        }
    }

    @State private var segment: Segment = .connected
    @State private var editor: Editor?
    @State private var detail: Contact?

    var body: some View {
        Group {
            switch segment {
            case .connected: connectedList
            case .contacts: contactsList
            }
        }
        .navigationTitle("Roster")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            if segment == .contacts {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .new
                    } label: {
                        Label("Add contact", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                switch target {
                case .new:
                    ContactEditView()
                case .prefilled(let callsign, let tone):
                    ContactEditView(prefillCallsign: callsign, prefillTxTone: tone)
                case .edit(let contact):
                    ContactEditView(contact: contact)
                }
            }
        }
        .sheet(item: $detail) { contact in
            ContactDetailView(contact: contact)
        }
    }

    // MARK: - Connected

    private var connectedList: some View {
        List {
            Section {
                if dedupedUsers.isEmpty {
                    Text("No users connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dedupedUsers, id: \.callsign) { user in
                        connectedRow(user)
                    }
                }
            } header: {
                Text("On \(session.channel) (\(dedupedUsers.count))")
            }
        }
    }

    @ViewBuilder
    private func connectedRow(_ user: VailMessage.UserInfo) -> some View {
        let known = contacts.contact(forCallsign: user.callsign)
        let isMe = user.callsign == session.callsign

        UserRow(user: user, isMe: isMe, contact: known)
            .contentShape(Rectangle())
            .onTapGesture {
                if let known { detail = known }
            }
            .swipeActions(edge: .leading) {
                if known == nil, !isMe {
                    Button {
                        editor = .prefilled(callsign: user.callsign, txTone: user.txTone)
                    } label: {
                        Label("Add", systemImage: "person.crop.circle.badge.plus")
                    }
                    .tint(.blue)
                }
            }
    }

    // MARK: - Contacts

    @ViewBuilder
    private var contactsList: some View {
        if contacts.contacts.isEmpty {
            ContentUnavailableView(
                "No contacts",
                systemImage: "person.crop.circle.badge.plus",
                description: Text("Tap + to add an operator, or swipe a connected user to save them.")
            )
        } else {
            List {
                Section {
                    Button {
                        startScan()
                    } label: {
                        HStack {
                            if scanner.isScanning {
                                ProgressView()
                                Text("Scanning… \(Int(scanner.progress * 100))%")
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("Find contacts on air")
                            }
                        }
                    }
                    .disabled(scanner.isScanning)
                } footer: {
                    if let date = scanner.lastScanDate, !scanner.isScanning {
                        Text("Last scan \(SkedFormat.relative(date)).")
                    } else {
                        Text("Briefly joins each active channel to find which one your contacts are on.")
                    }
                }

                Section {
                    ForEach(contacts.contacts) { contact in
                        ContactRow(contact: contact, channels: scanner.channels(for: contact.callsign))
                            .contentShape(Rectangle())
                            .onTapGesture { detail = contact }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    contacts.delete(contact)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    contacts.toggleFavorite(contact)
                                } label: {
                                    Label(contact.isFavorite ? "Unfavorite" : "Favorite",
                                          systemImage: contact.isFavorite ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                            }
                    }
                }
            }
        }
    }

    private func startScan() {
        var channels = Set<String>()
        for room in session.rooms where room.users > 0 { channels.insert(room.name) }
        for room in ChannelPickerView.standardRooms { channels.insert(room) }
        for contact in contacts.contacts {
            if let preferred = contact.preferredChannel, !preferred.isEmpty { channels.insert(preferred) }
        }
        channels.remove(session.channel)
        scanner.scan(
            channels: channels.sorted(),
            targetCallsigns: Set(contacts.contacts.map(\.callsign)),
            liveChannel: session.channel,
            liveRoster: session.users.map(\.callsign),
            isPrivate: session.privateMode
        )
    }

    /// Server reports per-socket, so the same callsign can appear multiple
    /// times during reconnect overlap or genuine multi-device login. Collapse
    /// by callsign, preferring an entry that advertises a non-zero TX tone.
    private var dedupedUsers: [VailMessage.UserInfo] {
        var byCallsign: [String: VailMessage.UserInfo] = [:]
        for user in session.users {
            if let existing = byCallsign[user.callsign] {
                let existingTone = existing.txTone ?? 0
                let newTone = user.txTone ?? 0
                if existingTone == 0, newTone > 0 {
                    byCallsign[user.callsign] = user
                }
            } else {
                byCallsign[user.callsign] = user
            }
        }
        let myCallsign = session.callsign
        return byCallsign.values.sorted { lhs, rhs in
            if lhs.callsign == myCallsign { return true }
            if rhs.callsign == myCallsign { return false }
            return lhs.callsign < rhs.callsign
        }
    }
}

private struct UserRow: View {
    let user: VailMessage.UserInfo
    let isMe: Bool
    let contact: Contact?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.callsign)
                        .font(.body.monospaced().weight(.medium))
                    if let contact, contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if isMe {
                        tag("YOU", color: .accentColor)
                    } else if contact != nil {
                        tag("CONTACT", color: .blue)
                    }
                }
                if let contact, !contact.name.isEmpty {
                    Text(contact.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let tone = user.txTone, tone > 0 {
                    Text("\(midiNoteName(tone)) • \(Int(KeyerEngine.midiNoteToHz(tone)))Hz")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}

private struct ContactRow: View {
    let contact: Contact
    let channels: [String]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Text(contact.callsign)
                        .font(.headline.monospaced())
                    if !contact.name.isEmpty {
                        Text(contact.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let worked = contact.lastWorked {
                    Text("Last worked \(SkedFormat.relative(worked))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !channels.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Label(channels.first ?? "", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    if channels.count > 1 {
                        Text("+\(channels.count - 1) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
