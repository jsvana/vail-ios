// SettingsView.swift
// Callsign, TX tone, RX delay, etc.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: VailSession
    @State private var callsignField: String = ""
    @State private var txToneField: Double = 72
    @State private var rxDelayField: Double = 2000
    @FocusState private var callsignFocused: Bool

    var body: some View {
        Form {
            Section("Identity") {
                HStack {
                    Text("Callsign")
                    Spacer()
                    TextField("Callsign", text: $callsignField)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($callsignFocused)
                        .submitLabel(.done)
                        .onSubmit { commitCallsign() }
                }
                Button("Apply callsign") { commitCallsign() }
                    .disabled(callsignField.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("TX Tone") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("\(midiNoteName(Int(txToneField))) • \(Int(KeyerEngine.midiNoteToHz(Int(txToneField))))Hz")
                            .font(.body.monospaced())
                        Spacer()
                        Text("MIDI \(Int(txToneField))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $txToneField, in: 48...96, step: 1) {
                        Text("TX Tone")
                    }
                    .onChange(of: txToneField) { _, new in
                        session.setTxTone(Int(new))
                    }
                }
            }

            Section("RX Delay") {
                VStack(alignment: .leading) {
                    Text("\(Int(rxDelayField)) ms")
                        .font(.body.monospaced())
                    Slider(value: $rxDelayField, in: 500...5000, step: 100) {
                        Text("RX Delay")
                    }
                    .onChange(of: rxDelayField) { _, new in
                        session.rxDelayMs = Int(new)
                    }
                    Text("Network buffer for received transmissions. Higher = more reliable, lower = more responsive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                LabeledContent("Lag") { Text("\(session.lagMs) ms").monospaced() }
                LabeledContent("Connected") { Text("\(session.clientCount)") }
                LabeledContent("State") { Text(stateText) }
                LabeledContent("Room decoder") { Text(session.roomDecoderEnabled ? "Enabled" : "Disabled") }
            }
        }
        .navigationTitle("Settings")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { callsignFocused = false }
            }
        }
        .onAppear {
            callsignField = session.callsign
            txToneField = Double(session.txTone)
            rxDelayField = Double(session.rxDelayMs)
        }
    }

    private func commitCallsign() {
        session.setCallsign(callsignField)
        callsignFocused = false
    }

    private var stateText: String {
        switch session.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Disconnected"
        case .idleDisconnected: "Idle"
        }
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}
