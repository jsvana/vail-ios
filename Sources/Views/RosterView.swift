// RosterView.swift
// Connected users with their TX tones.

import SwiftUI

struct RosterView: View {
    @EnvironmentObject var session: VailSession

    var body: some View {
        List {
            Section {
                if session.users.isEmpty {
                    Text("No users connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.users, id: \.callsign) { user in
                        UserRow(user: user, isMe: user.callsign == session.callsign)
                    }
                }
            } header: {
                Text("Connected (\(session.users.count))")
            }
        }
        .navigationTitle("Roster")
    }
}

private struct UserRow: View {
    let user: VailMessage.UserInfo
    let isMe: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(user.callsign)
                        .font(.body.monospaced().weight(.medium))
                    if isMe {
                        Text("YOU")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
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

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}
