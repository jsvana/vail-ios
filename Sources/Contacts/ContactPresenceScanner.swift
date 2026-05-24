// ContactPresenceScanner.swift
// Cross-channel presence discovery for contacts.
//
// The Vail protocol has no presence API: the server's `Rooms` list carries
// only room names + occupancy counts, never callsigns. The only way to learn
// *which* room a given callsign is in is to connect to that room and read its
// `UsersInfo` roster. This scanner does exactly that against a candidate set
// of rooms, using its own short-lived WebSockets so the user's live audio
// connection (owned by VailClient) is never disturbed.
//
// Etiquette / cost: probing a room briefly joins it, so the probe appears in
// that room's roster for a second or two. To minimize footprint we (a) use an
// anonymous probe callsign rather than the user's, (b) keep scans on-demand
// (a button, never a background poll), and (c) skip the room the user is
// already connected to — that roster is read live from VailSession instead.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.jsvana.VailMorse", category: "presence-scanner")

@MainActor
public final class ContactPresenceScanner: ObservableObject {

    /// callsign (uppercased) → channels the callsign was seen in during the
    /// most recent scan.
    @Published public private(set) var channelsByCallsign: [String: [String]] = [:]
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var lastScanDate: Date?
    /// 0…1 progress across the candidate rooms.
    @Published public private(set) var progress: Double = 0

    private let baseURL = URL(string: "wss://vailmorse.com/chat")!
    private static let subprotocol = "json.vailmorse.com"
    /// Ephemeral config: probes are throwaway and should not share cookies or
    /// caches with anything else.
    private let urlSession = URLSession(configuration: .ephemeral)

    private var scanTask: Task<Void, Never>?

    /// How long to wait for a room's roster before giving up on that probe.
    private static let probeTimeout: Duration = .seconds(3)
    /// How many rooms to probe at once. Bounds the number of simultaneous
    /// sockets while keeping a full scan reasonably fast.
    private static let maxConcurrent = 4

    public init() {}

    /// Channels the given callsign is currently on (empty = not found / not on
    /// air as of the last scan).
    public func channels(for callsign: String) -> [String] {
        channelsByCallsign[callsign.uppercased()] ?? []
    }

    /// Begin a scan. `channels` is the candidate room set to probe;
    /// `targetCallsigns` are the calls we care about (others are ignored).
    /// `liveChannel`/`liveRoster` seed presence for the room the user is
    /// already connected to so we don't probe (and phantom-join) it.
    public func scan(
        channels: [String],
        targetCallsigns: Set<String>,
        liveChannel: String? = nil,
        liveRoster: [String] = []
    ) {
        guard !isScanning else { return }
        let targets = Set(targetCallsigns.map { $0.uppercased() })
        guard !targets.isEmpty else { return }

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.runScan(
                channels: channels,
                targets: targets,
                liveChannel: liveChannel,
                liveRoster: liveRoster
            )
        }
    }

    public func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Scan driver

    private func runScan(
        channels: [String],
        targets: Set<String>,
        liveChannel: String?,
        liveRoster: [String]
    ) async {
        isScanning = true
        progress = 0
        var found: [String: Set<String>] = [:]

        // Seed from the live room we're already in — no need to probe it.
        if let liveChannel {
            for cs in liveRoster.map({ $0.uppercased() }) where targets.contains(cs) {
                found[cs, default: []].insert(liveChannel)
            }
        }
        channelsByCallsign = found.mapValues { $0.sorted() }

        let probeCallsign = Self.anonymousProbeCallsign()
        let total = max(channels.count, 1)
        var completed = 0

        var index = 0
        while index < channels.count {
            if Task.isCancelled { break }
            let end = min(index + Self.maxConcurrent, channels.count)
            let batch = Array(channels[index..<end])

            let results = await withTaskGroup(of: (String, Set<String>).self) { group in
                for channel in batch {
                    group.addTask { [weak self] in
                        guard let self else { return (channel, []) }
                        let calls = await self.probe(channel: channel, probeCallsign: probeCallsign)
                        return (channel, calls)
                    }
                }
                var acc: [(String, Set<String>)] = []
                for await result in group { acc.append(result) }
                return acc
            }

            if Task.isCancelled { break }

            for (channel, calls) in results {
                for cs in calls where targets.contains(cs) {
                    found[cs, default: []].insert(channel)
                }
            }
            completed += batch.count
            progress = Double(completed) / Double(total)
            channelsByCallsign = found.mapValues { $0.sorted() }

            index = end
        }

        if !Task.isCancelled {
            channelsByCallsign = found.mapValues { $0.sorted() }
            lastScanDate = Date()
            progress = 1
        }
        isScanning = false
    }

    // MARK: - Single-room probe

    /// Connect to one room, read its roster, return the set of callsigns
    /// (uppercased) present. Returns empty on timeout or any failure.
    private func probe(channel: String, probeCallsign: String) async -> Set<String> {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "repeater", value: channel)]
        guard let url = components.url else { return [] }

        let task = urlSession.webSocketTask(with: url, protocols: [Self.subprotocol])
        task.resume()

        // Watchdog: cancel the socket after the timeout so a stalled receive()
        // throws and we bail instead of hanging the whole scan.
        let watchdog = Task {
            try? await Task.sleep(for: Self.probeTimeout)
            task.cancel(with: .goingAway, reason: nil)
        }
        defer {
            watchdog.cancel()
            task.cancel(with: .normalClosure, reason: nil)
        }

        // Send a hello so the server registers us and replies with the roster.
        // Mirror a normal client join exactly (private/decoder = false) so we
        // join the same room instance the user would and read its real roster.
        var hello = VailMessage(timestamp: Int64(Date().timeIntervalSince1970 * 1000))
        hello.callsign = probeCallsign
        hello.txTone = 72
        hello.private = false
        hello.decoder = false
        do {
            let data = try JSONEncoder().encode(hello)
            guard let string = String(data: data, encoding: .utf8) else { return [] }
            try await task.send(.string(string))
        } catch {
            return []
        }

        // Read until the first roster-bearing message (Duration:[] with a user
        // list) or until the watchdog cancels us.
        while !Task.isCancelled {
            guard let frame = try? await task.receive() else { return [] }
            let data: Data? = switch frame {
            case .string(let s): s.data(using: .utf8)
            case .data(let d): d
            @unknown default: nil
            }
            guard let data, let msg = try? JSONDecoder().decode(VailMessage.self, from: data) else { continue }
            guard msg.duration.isEmpty else { continue }
            if let info = msg.usersInfo {
                return Set(info.map { $0.callsign.uppercased() })
            } else if let users = msg.users {
                return Set(users.map { $0.uppercased() })
            }
            // A bare clock-sync hello with no roster — keep reading.
        }
        return []
    }

    private static func anonymousProbeCallsign() -> String {
        "scan\(Int.random(in: 1000...9999))"
    }
}
