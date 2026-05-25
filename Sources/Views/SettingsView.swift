// SettingsView.swift
// Callsign, TX tone, RX delay, etc.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: VailSession
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.quiet.rawValue
    @State private var callsignField: String = ""
    @State private var txToneField: Double = 72
    @State private var rxDelayField: Double = 2000
    @State private var keyerWPMField: Double = 20
    @FocusState private var callsignFocused: Bool

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRaw) ?? .quiet },
            set: { themeRaw = $0.rawValue }
        )
    }

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

            Section {
                Picker("Theme", selection: themeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(themeBinding.wrappedValue.tagline)
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
                    Slider(value: $txToneField, in: 48 ... 96, step: 1) {
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
                    Slider(value: $rxDelayField, in: 500 ... 5000, step: 100) {
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

            Section {
                LabeledContent("Status") {
                    Text(session.midiAdapterConnected ? "Connected" : "Not connected")
                        .foregroundStyle(session.midiAdapterConnected ? Color.green : Color.secondary)
                }
                Picker("Keyer mode", selection: $session.keyerMode) {
                    ForEach(MIDIOutput.KeyerMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Keyer speed")
                        Spacer()
                        Text("\(Int(keyerWPMField)) WPM")
                            .font(.body.monospaced())
                    }
                    Slider(value: $keyerWPMField, in: 5 ... 40, step: 1) {
                        Text("Keyer speed")
                    }
                    .onChange(of: keyerWPMField) { _, new in
                        session.keyerWPM = Int(new)
                    }
                    Text("Dit length for adapter-generated keying (iambic / bug). Ignored for straight key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("RX piezo feedback", isOn: $session.adapterRxFeedbackEnabled)
                Text("Buzz the adapter's piezo for received transmissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    session.wakeMidiAdapter()
                } label: {
                    Label("Wake up adapter", systemImage: "bolt.fill")
                }
            } header: {
                Text("Vail Adapter")
            } footer: {
                Text("The adapter powers up as a keyboard. If keying isn't detected, tap \"Wake up adapter\" to switch it into MIDI mode.")
            }

            Section {
                Toggle("Private mode", isOn: $session.privateMode)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Hides your channels from the server's public Rooms list and marks contact scans private. Anyone who knows a channel name can still join it.")
            }

            Section("Diagnostics") {
                LabeledContent("Lag") { Text("\(session.lagMs) ms").monospaced() }
                LabeledContent("Connected") { Text("\(session.clientCount)") }
                LabeledContent("State") { Text(stateText) }
                LabeledContent("Room decoder") { Text(session.roomDecoderEnabled ? "Enabled" : "Disabled") }
                NavigationLink {
                    LogView()
                } label: {
                    Label("In-app log", systemImage: "doc.text.magnifyingglass")
                }
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("About this app")
                    }
                }
            } footer: {
                Text("Unofficial third-party client. Not affiliated with the Vail project.")
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
            keyerWPMField = Double(session.keyerWPM)
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
