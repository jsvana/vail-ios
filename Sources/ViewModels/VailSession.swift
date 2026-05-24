// VailSession.swift
// Top-level orchestrator. Owns the VailClient, KeyerEngine, and MIDIInput.
// Publishes observable state for SwiftUI views.
//
// Responsibilities:
//   - Wire MIDI key events to TX (local sidetone + WebSocket send)
//   - Wire VailClient events to RX (scheduled audio + roster updates)
//   - Stuck-key safety (10s auto-cutoff)
//   - Hold @Published state for SwiftUI
//
// See CLAUDE.md §6 for the full data flow.

import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.example.VailMorse", category: "session")

@MainActor
public final class VailSession: ObservableObject {

    // MARK: - Published state

    @Published public var connectionState: VailClient.ConnectionState = .disconnected
    @Published public var channel: String = "General" {
        didSet { UserDefaults.standard.set(channel, forKey: Self.channelDefaultsKey) }
    }
    @Published public var callsign: String = "" {
        didSet { UserDefaults.standard.set(callsign, forKey: Self.callsignDefaultsKey) }
    }
    @Published public var txTone: Int = 72 {
        didSet { UserDefaults.standard.set(txTone, forKey: Self.txToneDefaultsKey) }
    }
    @Published public var rxDelayMs: Int = 2000 {
        didSet { UserDefaults.standard.set(rxDelayMs, forKey: Self.rxDelayDefaultsKey) }
    }
    @Published public var users: [VailMessage.UserInfo] = []
    @Published public var rooms: [VailMessage.Room] = []
    @Published public var chatMessages: [ChatMessage] = []
    @Published public var lagMs: Int64 = 0
    @Published public var breakInEnabled: Bool = false {
        didSet { UserDefaults.standard.set(breakInEnabled, forKey: Self.breakInDefaultsKey) }
    }
    @Published public var lastNotice: String?
    @Published public var clientCount: Int = 0
    @Published public var roomDecoderEnabled: Bool = false

    /// Whether a Vail Adapter is connected for MIDI output (config + RX piezo).
    @Published public var midiAdapterConnected: Bool = false

    /// Keyer mode pushed to the adapter (raw value of MIDIOutput.KeyerMode).
    @Published public var keyerMode: Int = MIDIOutput.KeyerMode.straightKey.rawValue {
        didSet {
            UserDefaults.standard.set(keyerMode, forKey: Self.keyerModeDefaultsKey)
            let mode = MIDIOutput.KeyerMode(rawValue: keyerMode) ?? .straightKey
            Task { await midiOutput?.setKeyerMode(mode) }
        }
    }

    /// Keyer speed in WPM, sent to the adapter as a dit duration. Only affects
    /// adapter-generated keying (iambic/bug modes), not straight key.
    @Published public var keyerWPM: Int = 20 {
        didSet {
            UserDefaults.standard.set(keyerWPM, forKey: Self.keyerWPMDefaultsKey)
            let wpm = keyerWPM
            Task { await midiOutput?.setSpeed(wpm: wpm) }
        }
    }

    /// When enabled, received tones also buzz the adapter's piezo.
    @Published public var adapterRxFeedbackEnabled: Bool = false {
        didSet { UserDefaults.standard.set(adapterRxFeedbackEnabled, forKey: Self.adapterRxFeedbackDefaultsKey) }
    }

    public struct ChatMessage: Identifiable, Sendable, Equatable {
        public let id = UUID()
        public let text: String
        public let callsign: String?
        public let timestampMs: Int64
    }

    // MARK: - Components

    private let client: VailClient
    private let keyer: KeyerEngine
    private var midi: MIDIInput?
    private var midiOutput: MIDIOutput?
    private var clientEventTask: Task<Void, Never>?

    // Per-key TX state.
    private struct KeyState {
        var isDown: Bool = false
        var beginLocalMs: Int64 = 0
    }
    private var keyState: [MIDIInput.Key: KeyState] = [
        .straight: KeyState(),
        .dit: KeyState(),
        .dah: KeyState()
    ]
    private var stuckKeyTask: Task<Void, Never>?

    /// Auto-disable break-in if a key has been down for >10s.
    /// Matches the web client's stuck-key safety.
    public static let stuckKeyTimeoutMs: Int64 = 10_000

    private static let callsignDefaultsKey = "VailSession.callsign"
    private static let channelDefaultsKey = "VailSession.channel"
    private static let txToneDefaultsKey = "VailSession.txTone"
    private static let rxDelayDefaultsKey = "VailSession.rxDelayMs"
    private static let breakInDefaultsKey = "VailSession.breakInEnabled"
    private static let keyerModeDefaultsKey = "VailSession.keyerMode"
    private static let keyerWPMDefaultsKey = "VailSession.keyerWPM"
    private static let adapterRxFeedbackDefaultsKey = "VailSession.adapterRxFeedback"

    public init(initialCallsign: String? = nil) {
        let defaults = UserDefaults.standard

        let storedCallsign = defaults.string(forKey: Self.callsignDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cs = initialCallsign
            ?? (storedCallsign?.isEmpty == false ? storedCallsign! : Self.generateAnonymousCallsign())

        let storedChannel = defaults.string(forKey: Self.channelDefaultsKey)
        let resolvedChannel = (storedChannel?.isEmpty == false) ? storedChannel! : "General"

        let resolvedTxTone = defaults.object(forKey: Self.txToneDefaultsKey) != nil
            ? defaults.integer(forKey: Self.txToneDefaultsKey)
            : 72
        let resolvedRxDelay = defaults.object(forKey: Self.rxDelayDefaultsKey) != nil
            ? defaults.integer(forKey: Self.rxDelayDefaultsKey)
            : 2000
        let resolvedBreakIn = defaults.object(forKey: Self.breakInDefaultsKey) != nil
            ? defaults.bool(forKey: Self.breakInDefaultsKey)
            : false

        // Stored let properties first.
        self.client = VailClient(callsign: cs, txTone: resolvedTxTone)
        self.keyer = KeyerEngine()

        // didSet does not fire from designated initializer, so these loads do not
        // re-write themselves to UserDefaults.
        self.callsign = cs
        self.channel = resolvedChannel
        self.txTone = resolvedTxTone
        self.rxDelayMs = resolvedRxDelay
        self.breakInEnabled = resolvedBreakIn

        self.keyerMode = defaults.object(forKey: Self.keyerModeDefaultsKey) != nil
            ? defaults.integer(forKey: Self.keyerModeDefaultsKey)
            : MIDIOutput.KeyerMode.straightKey.rawValue
        self.keyerWPM = defaults.object(forKey: Self.keyerWPMDefaultsKey) != nil
            ? defaults.integer(forKey: Self.keyerWPMDefaultsKey)
            : 20
        self.adapterRxFeedbackEnabled = defaults.object(forKey: Self.adapterRxFeedbackDefaultsKey) != nil
            ? defaults.bool(forKey: Self.adapterRxFeedbackDefaultsKey)
            : false

        self.keyer.localTxToneMIDI = resolvedTxTone
    }

    // MARK: - Lifecycle

    public func start() {
        do {
            try keyer.start()
        } catch {
            log.error("KeyerEngine.start failed: \(error.localizedDescription)")
        }

        do {
            let m = try MIDIInput()
            m.onEvent = { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleMIDIEvent(event)
                }
            }
            self.midi = m
        } catch {
            log.error("MIDIInput init failed: \(error.localizedDescription)")
        }

        do {
            let out = try MIDIOutput()
            self.midiOutput = out
            let mode = MIDIOutput.KeyerMode(rawValue: keyerMode) ?? .straightKey
            let wpm = keyerWPM
            let tone = txTone
            Task {
                await out.setOnConnectionChange { [weak self] connected in
                    Task { @MainActor in self?.midiAdapterConnected = connected }
                }
                await out.configure(keyerMode: mode, wpm: wpm, sidetoneMIDINote: tone)
                await out.connectToAdapter()
            }
        } catch {
            log.error("MIDIOutput init failed: \(error.localizedDescription)")
        }

        clientEventTask?.cancel()
        clientEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in await client.events() {
                await MainActor.run {
                    self.handleClientEvent(event)
                }
            }
        }
    }

    public func stop() {
        clientEventTask?.cancel()
        clientEventTask = nil
        stuckKeyTask?.cancel()
        stuckKeyTask = nil
        Task { await client.disconnect() }
        keyer.stop()
    }

    public func connect() {
        Task {
            await client.connect(channel: channel)
        }
    }

    public func disconnect() {
        Task { await client.disconnect() }
    }

    public func switchChannel(_ name: String) {
        channel = name
        chatMessages.removeAll()
        users.removeAll()
        Task {
            await client.disconnect()
            await client.connect(channel: name)
        }
    }

    public func setCallsign(_ newCallsign: String) {
        let trimmed = newCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        callsign = trimmed
        Task { await client.setCallsign(trimmed) }
    }

    public func setTxTone(_ note: Int) {
        let clamped = max(0, min(127, note))
        txTone = clamped
        keyer.localTxToneMIDI = clamped
        Task { await client.setTxTone(clamped) }
        Task { await midiOutput?.setSidetone(midiNote: clamped) }
    }

    public func sendChat(_ text: String) {
        Task { await client.sendChat(text) }
    }

    /// Re-broadcast the adapter wake/config sequence. Use when the adapter is
    /// plugged in but not responding (it may have powered up in keyboard mode).
    public func wakeMidiAdapter() {
        Task { await midiOutput?.wakeAdapter() }
    }

    // MARK: - Key event handling

    private func handleMIDIEvent(_ event: MIDIInput.Event) {
        let wasDown = keyState[event.key]?.isDown ?? false
        if event.isDown && !wasDown {
            handleKeyDown(event)
        } else if !event.isDown && wasDown {
            handleKeyUp(event)
        }
    }

    /// Public for the on-screen touch key.
    public func touchKey(isDown: Bool) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let event = MIDIInput.Event(
            key: .straight,
            isDown: isDown,
            machTimestamp: mach_absolute_time(),
            timestampMs: nowMs
        )
        handleMIDIEvent(event)
    }

    private func handleKeyDown(_ event: MIDIInput.Event) {
        keyState[event.key]?.isDown = true
        keyState[event.key]?.beginLocalMs = event.timestampMs

        // Local sidetone fires immediately, regardless of break-in.
        keyer.beginTx()

        startStuckKeyWatchdog()
    }

    private func handleKeyUp(_ event: MIDIInput.Event) {
        guard let begin = keyState[event.key]?.beginLocalMs else { return }
        let durationMs = max(0, event.timestampMs - begin)
        keyState[event.key]?.isDown = false

        keyer.endTx()

        if breakInEnabled, durationMs > 0, durationMs <= UInt16.max {
            Task { [client] in
                await client.transmitTone(
                    durationMs: UInt16(durationMs),
                    beginLocalMs: begin
                )
            }
        }

        // If no keys are down, cancel the stuck-key watchdog.
        if keyState.values.allSatisfy({ !$0.isDown }) {
            stuckKeyTask?.cancel()
            stuckKeyTask = nil
        }
    }

    private func startStuckKeyWatchdog() {
        guard stuckKeyTask == nil else { return }
        let timeout = Self.stuckKeyTimeoutMs
        stuckKeyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(timeout)))
            if Task.isCancelled { return }
            guard let self else { return }
            self.handleStuckKey()
        }
    }

    private func handleStuckKey() {
        // Force all keys up and disable break-in.
        for key in keyState.keys {
            keyState[key]?.isDown = false
        }
        keyer.endTx()
        keyer.panic()
        breakInEnabled = false
        lastNotice = "Stuck key detected. Break-in disabled."
        log.warning("Stuck key — panic")
        stuckKeyTask = nil
    }

    // MARK: - Client event handling

    private func handleClientEvent(_ event: VailClient.Event) {
        switch event {
        case .stateChanged(let s):
            connectionState = s

        case .tone(let at, let durationMs, _, let txTone):
            let note = txTone ?? 69
            let playAt = at + Int64(rxDelayMs)
            keyer.scheduleReceivedTone(
                midiNote: note,
                durationMs: durationMs,
                playAtLocalMs: playAt
            )
            if adapterRxFeedbackEnabled {
                let buzzNote = UInt8(max(0, min(127, note)))
                Task { await midiOutput?.scheduleBuzz(note: buzzNote, durationMs: durationMs, playAtLocalMs: playAt) }
            }

        case .chat(let text, let cs, let ts):
            chatMessages.append(ChatMessage(text: text, callsign: cs, timestampMs: ts))
            // Cap chat history to avoid unbounded growth.
            if chatMessages.count > 500 { chatMessages.removeFirst(chatMessages.count - 500) }

        case .roster(let userList, let roomList):
            users = userList
            if let r = roomList { rooms = r }
            clientCount = userList.count

        case .decoderRoomChanged(let enabled):
            roomDecoderEnabled = enabled

        case .ownEcho(let lag, _):
            // For v0, show the latest instantaneous lag. Smoothing/averaging
            // is a polish task — see CLAUDE.md §6.
            lagMs = lag

        case .notice(let text):
            lastNotice = text
        }
    }

    // MARK: - Helpers

    private static func generateAnonymousCallsign() -> String {
        let n = Int.random(in: 1000...9999)
        return "anon\(n)"
    }
}
