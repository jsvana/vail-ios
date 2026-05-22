// RosterView.swift
// Connected users with their TX tones.

import SwiftUI

struct RosterView: View {
    @EnvironmentObject var session: VailSession

    var body: some View {
        List {
            Section {
                if dedupedUsers.isEmpty {
                    Text("No users connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dedupedUsers, id: \.callsign) { user in
                        UserRow(user: user, isMe: user.callsign == session.callsign)
                    }
                }
            } header: {
                Text("Connected (\(dedupedUsers.count))")
            }
        }
        .navigationTitle("Roster")
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
