// ContactsView.swift
// Saved-contacts management: list, add/edit, favorite, delete, and the
// cross-channel presence scanner. The "Connected" view that used to live
// here was redundant with the Activity timeline (which now shows the full
// roster as lanes) so it was removed.

import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var session: VailSession
    @EnvironmentObject var contacts: ContactStore
    @EnvironmentObject var scanner: ContactPresenceScanner

    private enum Editor: Identifiable {
        case new
        case edit(Contact)
        var id: String {
            switch self {
            case .new: "new"
            case let .edit(contact): contact.id.uuidString
            }
        }
    }

    @State private var editor: Editor?
    @State private var detail: Contact?

    var body: some View {
        Group {
            if contacts.contacts.isEmpty {
                ContentUnavailableView(
                    "No contacts",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Tap + to add an operator. They'll show up with a badge on the Activity timeline when they key.")
                )
            } else {
                contactsList
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = .new
                } label: {
                    Label("Add contact", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                switch target {
                case .new:
                    ContactEditView()
                case let .edit(contact):
                    ContactEditView(contact: contact)
                }
            }
        }
        .sheet(item: $detail) { contact in
            ContactDetailView(contact: contact)
        }
    }

    private var contactsList: some View {
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

    private func startScan() {
        var channels = Set<String>()
        for room in session.rooms where room.users > 0 {
            channels.insert(room.name)
        }
        for room in ChannelPickerView.standardRooms {
            channels.insert(room)
        }
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
