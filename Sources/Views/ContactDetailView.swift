// ContactDetailView.swift
// Read-only detail for a contact: presence (where they are on air right now),
// quick actions to meet them, and the saved info. Presented as a sheet, so it
// hosts its own NavigationStack for the Edit push.

import SwiftUI

struct ContactDetailView: View {
    let contact: Contact

    @EnvironmentObject var session: VailSession
    @EnvironmentObject var store: ContactStore
    @EnvironmentObject var scanner: ContactPresenceScanner
    @Environment(\.dismiss) private var dismiss

    /// Latest copy from the store (so favorite/edit changes reflect live).
    private var current: Contact {
        store.contact(forCallsign: contact.callsign) ?? contact
    }

    private var presenceChannels: [String] {
        scanner.channels(for: contact.callsign)
    }

    var body: some View {
        NavigationStack {
            Form {
                presenceSection
                meetSection
                infoSection
                if !current.notes.isEmpty {
                    Section("Notes") { Text(current.notes) }
                }
                Section {
                    Button(role: .destructive) {
                        store.delete(current)
                        dismiss()
                    } label: {
                        Label("Delete contact", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(current.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.toggleFavorite(current)
                    } label: {
                        Image(systemName: current.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(current.isFavorite ? .yellow : .secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") {
                        ContactEditView(contact: current)
                    }
                }
            }
        }
    }

    // MARK: - Presence

    @ViewBuilder
    private var presenceSection: some View {
        Section {
            if scanner.isScanning {
                HStack {
                    ProgressView()
                    Text("Scanning channels…")
                        .foregroundStyle(.secondary)
                }
            } else if presenceChannels.isEmpty {
                Label("Not seen on air", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presenceChannels, id: \.self) { channel in
                    Button {
                        session.switchChannel(channel)
                        dismiss()
                    } label: {
                        HStack {
                            Label("On \(channel)", systemImage: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.green)
                            Spacer()
                            Text("Join")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            Button {
                startScan()
            } label: {
                Label("Find on air", systemImage: "magnifyingglass")
            }
            .disabled(scanner.isScanning)
        } header: {
            Text("Presence")
        } footer: {
            if let date = scanner.lastScanDate {
                Text("Last scan \(SkedFormat.relative(date)). Briefly joins each channel to read its roster.")
            } else {
                Text("Scans channels to find which one this operator is on. Briefly joins each channel to read its roster.")
            }
        }
    }

    // MARK: - Meet

    private var meetSection: some View {
        Section {
            Button {
                session.switchChannel(qsoChannel)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Start a QSO", systemImage: "person.line.dotted.person")
                    Text("On \(qsoChannel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Moves you to a private channel named from both callsigns. \(current.displayName) lands on the same name if they Start a QSO with you.")
        }
    }

    private var qsoChannel: String {
        session.qsoChannelName(with: current.callsign)
    }

    // MARK: - Info

    private var infoSection: some View {
        Section("Info") {
            LabeledContent("Callsign", value: current.callsign)
            if let channel = current.preferredChannel, !channel.isEmpty {
                LabeledContent("Usual channel", value: channel)
            }
            if let tone = current.preferredTxTone, tone > 0 {
                LabeledContent("TX tone", value: "\(midiNoteName(tone)) • \(Int(KeyerEngine.midiNoteToHz(tone)))Hz")
            }
            if let worked = current.lastWorked {
                LabeledContent("Last worked", value: SkedFormat.clock(worked))
            }
            LabeledContent("Added", value: SkedFormat.clock(current.dateAdded))
        }
    }

    // MARK: - Helpers

    private func startScan() {
        var channels = Set<String>()
        for room in session.rooms where room.users > 0 { channels.insert(room.name) }
        for room in ChannelPickerView.standardRooms { channels.insert(room) }
        if let preferred = current.preferredChannel, !preferred.isEmpty { channels.insert(preferred) }
        channels.remove(session.channel)
        scanner.scan(
            channels: channels.sorted(),
            targetCallsigns: [current.callsign],
            liveChannel: session.channel,
            liveRoster: session.users.map(\.callsign),
            isPrivate: session.privateMode
        )
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}
