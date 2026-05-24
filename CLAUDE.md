# VailMorse iOS — Claude Reference Document

This document is the source of truth for the Vail protocol, audio model, and
iOS architecture. Read it in full before making non-trivial changes.

The vailmorse.com web client is closed-source but the JavaScript is unminified
and readable. This document was assembled by reading `vail.mjs`,
`repeaters.mjs`, and `outputs.mjs` directly. When in doubt, those files are
ground truth — re-read them rather than guessing.

---

## 1. Wire protocol

### Endpoint

```
wss://vailmorse.com/chat?repeater=<channel_name>
```

Subprotocol negotiated via `Sec-WebSocket-Protocol: json.vailmorse.com`.

The deprecated binary subprotocol (`binary.vail.woozle.org`) and JSON
subprotocol with woozle naming (`json.vail.woozle.org`) may still be accepted
for legacy clients but the modern client only uses `json.vailmorse.com`. Match
it.

### Message envelope

All messages — sent in both directions — share a single JSON envelope.
Different "message types" are distinguished by which fields are populated.

```json
{
  "Timestamp": 1716321500123,   // int64 ms since Unix epoch, in SERVER clock
  "Duration": [80, 80, 240],    // []uint16 ms; alternating tone/silence; empty for non-CW msgs
  "Callsign": "W6JY",           // string
  "TxTone": 72,                 // int MIDI note (C5 = 72)
  "Private": false,             // bool (sent on connect/keepalive only)
  "Decoder": false,             // bool (sent on connect; server echoes per-room)
  "Text": "hello world",        // string; present iff this is a chat message

  // Server-added fields, present in some inbound messages:
  "Clients": 5,                 // int; connected clients count
  "Users": ["W6JY", "N9HO"],    // []string; legacy callsign list
  "UsersInfo": [                // []{Callsign, TxTone}; preferred over Users
    { "Callsign": "W6JY", "TxTone": 72 },
    { "Callsign": "N9HO", "TxTone": 69 }
  ],
  "Rooms": [                    // []{Name, Users}; public rooms list
    { "Name": "General", "Users": 8 },
    { "Name": "Channel 1", "Users": 0 }
  ]
}
```

### Message types (by populated fields)

| Direction | Type                  | Distinguishing fields                                  |
|-----------|-----------------------|--------------------------------------------------------|
| Out       | Initial / keepalive   | `Duration:[]`, `Callsign`, `TxTone`, `Private`, `Decoder` |
| Out       | Tone transmission     | `Duration: [ms]` (single element), optional `TxTone`   |
| Out       | Chat                  | `Duration:[]`, `Text`, `Callsign`                      |
| In        | Server hello / sync   | `Duration:[]`, server-added fields (set clock offset)   |
| In        | Tone from other user  | `Duration: [t, s, t, …]`, `Callsign`, `TxTone`         |
| In        | Echo of own tone      | matches a recently-sent message in our `sent[]` queue  |
| In        | Chat from other user  | `Text`, `Callsign`, `Timestamp`                        |

### Clock offset model

The server is the authoritative clock. **Wire timestamps are always in server
clock**, not local clock.

On any received message with `Duration: []`, set:
```
clockOffset = localNowMs - msg.Timestamp
```

To send:
```
wireTimestamp = localNowMs - clockOffset
```

To play back received audio:
```
localPlayAtMs = msg.Timestamp + clockOffset + rxDelayMs
```

`clockOffset` is updated every time a `Duration:[]` message arrives. Since the
keepalive runs every 15s and the server responds with such messages, drift is
corrected continuously.

### Echo of own transmissions

The server echoes your own tone messages back to you. The client uses these for
lag measurement and to feed the decoder, but **does not render them as audio**
(local sidetone already played).

To detect: maintain a `sent[]` queue. On every received message, check for
equality (same `Timestamp` AND same `Duration` array) against entries in
`sent[]`. On match:
- Remove the entry from `sent[]`
- Compute lag: `now - clockOffset - msg.Timestamp - sum(msg.Duration)`
- Feed durations to decoder (if enabled)
- **Do not play audio**

The deque should be bounded (50 entries is plenty — anything older never came
back).

### Keepalive

Send a hello message (the initial-connect message format) every **15 seconds**.
The server is on Cloud Run and drops idle connections aggressively. Skipping
the keepalive results in disconnection after ~30s of silence.

### Inactivity reconnect

If the server closes with `reason` containing "inactivity", **do not
auto-reconnect**. Instead, set `wantConnected = false`. On the next user
action (key press, chat send), reconnect. This matches the web client's
behavior and avoids burning battery on idle reconnect loops.

### Reconnection on transport errors

For non-inactivity disconnects (network drop, server restart), reconnect with
a backoff (web client uses fixed 2s; exponential backoff with cap is fine).

### TX tone semantics

`TxTone` is a MIDI note number (0–127). The default in the web client is **72
(C5)**. Common values: 69 = A4 (440 Hz), 72 = C5, 74 = D5.

Hz conversion (equal temperament): `freq = 440 * pow(2, (note - 69) / 12)`.

The web client sends `TxTone` on:
- Every initial/keepalive message (announces your preferred TX tone to others)
- Every outgoing tone message (allows mid-transmission tone changes)

The web client receives `TxTone` in:
- Roster updates via `UsersInfo` — stable preference per user
- Per-tone messages — overrides per transmission

Render each received tone at the sender's TX tone, not your own.

### Special fields

- `Notice`: server-pushed toast message (not seen in code yet but referenced in
  `vail.mjs` via `stats.notice` — may be a future extension or only sent on
  certain server events).
- The `Decoder` flag in incoming messages tells you whether the room has
  server-side decoder enabled. The client honors this by enabling local CW
  decoding even if the user didn't explicitly turn it on.

---

## 2. REST endpoints (auxiliary)

The web client uses several REST endpoints alongside the WebSocket. Not
required for v1 but documented for completeness:

| Endpoint                         | Purpose                                |
|----------------------------------|----------------------------------------|
| `GET /api/events`                | Verify admin password (200 = valid)    |
| `GET /api/enigma`                | Get current Weekly Enigma puzzle       |
| `POST /api/enigma/check`         | Submit Enigma answer                   |
| `GET /api/enigma/leaderboard`    | Top Enigma solvers                     |
| `GET /api/enigma/latest-solve`   | Most recent Enigma solve               |
| `GET /api/admin-callsigns`       | List of admin-protected callsigns      |

Admin auth uses headers: `X-Callsign: <call>`, `X-Admin-Password: <pwd>`.

---

## 3. Audio model

The web client uses Web Audio's `OscillatorNode` + `GainNode` pattern. Each
unique sender tone gets its own continuous oscillator, and a gain envelope
gates it on/off with a **5ms linear ramp** to avoid clicks (square-wave
overtones from instant transitions sound terrible and aren't proper CW).

### Mapping to iOS / AVAudioEngine

Two distinct audio paths:

**TX (local sidetone)**: continuous tone generation gated by key state. Use
`AVAudioSourceNode` with an atomic Bool for the gate. On key-down, start the
ramp-up; on key-up, start the ramp-down. The TX path has zero scheduled
latency — it should sound immediately.

**RX (received from server)**: pre-rendered `AVAudioPCMBuffer` per tone burst,
scheduled at sample-accurate future time via `AVAudioPlayerNode.scheduleBuffer(_:at:)`.
Maintain a pool of `AVAudioPlayerNode`s keyed by MIDI note — one node per
unique sender tone. Lazily create on first use.

Both paths feed into `engine.mainMixerNode`. A single tap on
`mainMixerNode.installTap(onBus:bufferSize:format:)` captures everything for
the optional recording feature.

### Why per-sender oscillators / players?

If two senders are keying simultaneously with different TX tones, they
overlap audibly. Pooling per-tone allows them to mix naturally. The web client
uses a `Map<MIDINote, Oscillator>`; iOS uses `[Int: AVAudioPlayerNode]`.
Lazy-allocate; pool is small (typically <20 unique senders in active rooms).

### Tone envelope

For received tones, render a buffer of:
```
frames = sampleRate * durationMs / 1000
```
samples. Apply a linear ramp over the first ~5ms (attack) and last ~5ms
(release). Mid section is constant amplitude.

Amplitude formula: `sin(2π * freq * t / sampleRate) * envelope(i)`.

Amplitude scaling: 0.5 (matches `txGain = 0.5` in `outputs.mjs`).

### Panic

On audio session interruption (`AVAudioSession.interruptionNotification`), on
app backgrounding without audio entitlement, or on stuck-key detection:
**panic**. Force-stop all players, force key-up state, cancel any in-flight
transmission. Mirror the `Panic()` method in `outputs.mjs`.

### MIDI output to Vail Adapter

Implemented in `Sources/Input/MIDIOutput.swift` (a `MIDIOutput` actor owned by
`VailSession`). It opens a CoreMIDI output port, finds the adapter's
destination, and on connect sends the web-client init sequence — `B0 00 00`
(switch out of HID keyboard mode), dit duration, keyer mode, sidetone. Keyer
mode / speed / sidetone are reconfigurable at runtime.

The web client also sends MIDI note-on/off to the adapter on RX so its onboard
piezo buzzes received CW. `MIDIOutput.scheduleBuzz` does this, gated behind the
`adapterRxFeedbackEnabled` setting; note-on/off are timestamped (mach time) to
land in sync with the audio playback.

---

## 4. Vail Adapter MIDI protocol

The adapter is a USB MIDI class-compliant device. It shows up via CoreMIDI on
iOS (USB-C, Lightning Camera Connection Kit, or BLE MIDI when paired).

### Inbound (adapter → host) — what we read

MIDI channel 1 (zero-indexed channel 0).

| Message              | Meaning                          |
|----------------------|----------------------------------|
| Note On `90 00 7F`   | Straight key closed              |
| Note Off `80 00 00`  | Straight key open                |
| Note On `90 01 7F`   | Dit paddle closed                |
| Note Off `80 01 00`  | Dit paddle open                  |
| Note On `90 02 7F`   | Dah paddle closed                |
| Note Off `80 02 00`  | Dah paddle open                  |

Note: spec docs claim notes C#/D for dit/dah, but the note number actually
varies by firmware and keyer mode. `MIDIInput` accepts the full Vail web
repeater set: straight = 0, dit = 1 / 20 / 61 (C#4), dah = 2 / 21 / 62 (D4).
Unmapped notes are ignored (we connect to all sources, so unrelated MIDI must
not register as keying). Code is source of truth.

Critically, the adapter boots in HID **keyboard** mode and does not emit these
note events until the host sends a Control Change. `MIDIOutput.connectToAdapter`
broadcasts the mode-switch (`B0 00 00`) to all destinations on start and on
every CoreMIDI setup change — without it, MIDI input never fires.

Use `MIDIPacket.timeStamp` (mach_absolute_time units) for accurate key event
timing. Convert via `mach_timebase_info`.

### Outbound (host → adapter) — what we send

Channel 1. Configures the adapter.

| Message              | Meaning                                              |
|----------------------|------------------------------------------------------|
| `B0 00 vv`           | Mode: vv≥0x40 = Keyboard, vv<0x40 = MIDI             |
| `B0 01 vv`           | Dit duration: `ms = vv * 2`                          |
| `B0 02 vv`           | Sidetone MIDI note (0–127); also sets adapter buzzer |
| `C0 vv`              | Keyer mode (Program Change):                         |
|                      |   0=passthrough 1=straight 2=bug 3=elbug 4=singledot |
|                      |   5=ultimatic 6=plain-iambic 7=iambicA 8=iambicB     |
|                      |   9=keyahead                                         |
| `90 NN 7F`           | Buzz the adapter at MIDI note NN (RX feedback)       |
| `80 NN 00`           | Silence the adapter                                  |

When the host sends ANY CC, the adapter switches into MIDI mode (stops
emitting HID keystrokes). This is how the web client suppresses adapter
keyboard output — it sends `B0 00 00` on connect.

---

## 5. Repeater state machine

The Vail repeater connection has the following lifecycle:

```
                  ┌──────────────┐
                  │ Disconnected │
                  └──────┬───────┘
                         │ connect(channel)
                         ▼
                  ┌──────────────┐
                  │  Connecting  │
                  └──────┬───────┘
                         │ WebSocket open
                         ▼
                  ┌──────────────┐    Duration:[] received
   ┌──────────────│   Connected  │◄──────────────────────┐
   │              └──────┬───────┘                       │
   │                     │                               │
   │                     │ inactivity close              │
   │                     ▼                               │
   │              ┌──────────────────┐                   │
   │              │ Idle (lazy reconn) │                 │
   │              └──────┬─────────────┘                 │
   │                     │ user keys or chats           │
   │                     ▼                               │
   │              ┌──────────────┐                       │
   │              │  Connecting  │───────────────────────┘
   │              └──────────────┘
   │
   │ user closes / network error
   ▼
┌──────────────┐  2s retry
│  Reconnecting├─────────────┐
└──────────────┘             │
       ▲                     │
       └─────────────────────┘
```

Important invariants:
- The `clockOffset` is reset to 0 on every `reopen()` and re-established on
  the first `Duration:[]` from the server.
- `sent[]` is per-connection. Clear on reopen.
- `lagSamples` may persist across reconnects to give continuity in UI display.

---

## 6. iOS app architecture

### Module layout

```
Sources/
├── App/             # App entry point, root view
├── Protocol/        # VailMessage, VailClient (network layer)
├── Audio/           # KeyerEngine (TX + RX audio)
├── Input/           # MIDIInput + MIDIOutput (CoreMIDI), touch input in Views
├── ViewModels/      # VailSession (orchestrates everything)
└── Views/           # SwiftUI views
```

### Threading / concurrency

- `VailClient` is an `actor` — all state mutation serialized.
- `VailSession` is `@MainActor` — owns published state for SwiftUI.
- `KeyerEngine` is not isolated — interacts with the audio thread directly.
  Internal state mutated from the main thread is fine for our needs; the audio
  render block is the only hot path and it reads atomically.
- `MIDIInput` callbacks come from a high-priority MIDI thread. Forward to
  the session via `Task { @MainActor in ... }`.

### Data flow

```
Vail Adapter ──MIDI──▶ MIDIInput ──key event──▶ VailSession ──┬──▶ KeyerEngine.startTx/endTx
                                                              │
                                                              └──▶ VailClient.transmitTone

VailClient ──tone event──▶ VailSession ──┬──▶ KeyerEngine.scheduleReceivedTone
                                         └──▶ MIDIOutput.scheduleBuzz (RX piezo, opt-in)
VailClient ──roster─────▶ VailSession ──▶ @Published users
VailClient ──chat──────▶ VailSession ──▶ @Published messages

VailSession ──config──▶ MIDIOutput ──MIDI──▶ Vail Adapter (mode/keyer/speed/sidetone)
```

### Audio session

For v1: `.playback` category with `.mixWithOthers` option, so Vail coexists
with music apps. For background receive (v2): add `audio` to
`UIBackgroundModes` in `Info.plist`.

### Sleep prevention

Set `UIApplication.shared.isIdleTimerDisabled = true` when actively connected
to a channel. Restore on disconnect/background.

### Stuck-key safety

Implemented in `VailSession`. If any key has been "down" for more than 10
seconds, force a key-up event and toast the user. This prevents jammed
paddles from spamming the channel.

### What's deferred

These are not in v1 but the architecture has space for them:

- **Recording**: `AVAudioEngine.mainMixerNode.installTap()` writing to
  `AVAudioFile`. Add a `Recorder` class.
- **Chat UI**: protocol code already handles chat in/out. Just add a SwiftUI
  view and a `@Published` message buffer.
- **Decoder**: CW-to-text decoding. Port from a known implementation (the web
  client's `decoder.mjs`).
- **Settings persistence**: `UserDefaults` keys `VailSession.callsign`,
  `VailSession.channel`, `VailSession.txTone`, `VailSession.rxDelayMs`,
  `VailSession.breakInEnabled`, `VailSession.keyerMode`, `VailSession.keyerWPM`,
  and `VailSession.adapterRxFeedback` are persisted via `didSet` observers on the
  `@Published` properties.
- **BLE MIDI pairing UI**: `CABTMIDICentralViewController` wrapped for
  SwiftUI. CoreMIDI sees BLE devices automatically once paired.
- **Background audio entitlement**: requires explicit Info.plist key + UI
  affordance.
- **Anonymous callsign auto-generation** matching web client (`anon####`).

---

## 7. Confirmed wire details and remaining open questions

### Confirmed against the wire (2026-05-21)

1. **`UsersInfo` field structure**: `[{callsign: String, txTone: Int}]` —
   note the **lowercase** keys, inconsistent with the rest of the envelope
   which uses uppercase. iOS `VailMessage.UserInfo` CodingKeys reflect this.
2. **`Rooms` field structure**: `[{name: String, users: Int, private: Bool}]`
   — also lowercase keys. `private` is currently ignored on the client.
3. **Server includes `UsersInfo` on every message**, including chat and
   (presumably) tone bursts. Decoding it must succeed or every message is
   dropped. This caused the original "zero users + no RX audio" bug — see
   git history for the fix.

### Still open

1. **Timestamp signedness**: assumed `Int64`. Server uses Go `int64`, which is
   signed. Should be safe through 2262.
2. **Are echoes of own messages bit-exact?** Documented behavior: server
   passes through. Verify by logging in DevTools — if server modifies
   timestamps, echo suppression breaks.
3. **`Notice` field**: referenced in `vail.mjs` but not in observed
   server-to-client messages I've seen. May appear in admin/error paths.
4. **What happens if you send `Duration: []` with no callsign?** Probably
   treated as a keepalive ping with empty roster info. Test.
5. **Can `TxTone` be 0?** Web client treats 0 as "not specified" and falls
   back to 69 (A4). Match this convention.

---

## 8. Style and conventions

- **Logging**: use `os.Logger` from Apple's logging framework with category
  per module (`subsystem: "com.you.vailmorse", category: "protocol"`).
  Don't `print` — log entries are debuggable via Console.app and OSLogStore.
- **Errors**: typed errors per module (e.g., `enum VailClientError: Error`),
  never `NSError`-style.
- **Concurrency**: prefer `actor` for stateful network/protocol code,
  `@MainActor` for ViewModels. Avoid GCD queues unless interfacing with C APIs
  (CoreMIDI).
- **Strings**: avoid throwing in user-visible paths; degrade gracefully and
  surface errors via SwiftUI alerts.
- **No external dependencies**: this app uses only Foundation, AVFoundation,
  CoreMIDI, and SwiftUI. Keep it that way unless there's a strong reason.

---

## 9. References

- **vailmorse.com**: the production server (closed source).
- **vail.woozle.org**: original Neale Pickett server. Same protocol family.
- **github.com/Vail-CW/vail_repeater_depricated**: previous-generation server
  source. Useful for confirming server behavior, but the modern protocol
  diverges (richer envelope, JSON only).
- **github.com/Vail-CW/vail-adapter**: adapter firmware. Defines the MIDI
  message vocabulary.
- **vailadapter.com**: adapter purchase / build info.
- **discord.gg/h28DefCf6J**: Vail community Discord. iOS-specific feedback
  goes in the `#ios-apps` channel.

---

*This file is the contract between you and future you (or future Claude). Keep
it accurate. When the protocol surface changes, update this first, then code.*
