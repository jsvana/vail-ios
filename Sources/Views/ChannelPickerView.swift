// ChannelPickerView.swift
// Standard rooms + active public rooms from server.

import SwiftUI

struct ChannelPickerView: View {
    /// Curated set matching the web client's dropdown.
    static let standardRooms: [String] = [
        "General",
        "Channel 1",
        "Channel 2",
        "Channel 3",
        "Decoder",
        "Echo",
        "Null",
        "Fortunes"
    ]

    @EnvironmentObject var session: VailSession
    @State private var customRoom: String = ""

    var body: some View {
        List {
            Section("Active public rooms") {
                if session.rooms.isEmpty {
                    Text("No active rooms")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(session.rooms, id: \.name) { room in
                        ChannelRow(
                            name: room.name,
                            users: room.users,
                            isActive: room.name == session.channel
                        ) {
                            session.switchChannel(room.name)
                        }
                    }
                }
            }

            Section("Standard rooms") {
                ForEach(Self.standardRooms, id: \.self) { name in
                    ChannelRow(
                        name: name,
                        users: occupancy[name] ?? 0,
                        isActive: name == session.channel
                    ) {
                        session.switchChannel(name)
                    }
                }
            }

            Section("Custom room") {
                HStack {
                    TextField("Room name", text: $customRoom)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Join") {
                        let name = customRoom.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        session.switchChannel(name)
                        customRoom = ""
                    }
                    .disabled(customRoom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Channels")
    }

    private var occupancy: [String: Int] {
        Dictionary(uniqueKeysWithValues: session.rooms.map { ($0.name, $0.users) })
    }
}

private struct ChannelRow: View {
    let name: String
    let users: Int?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                    .fontWeight(isActive ? .bold : .regular)
                Spacer()
                if let u = users {
                    Label("\(u)", systemImage: "person.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
