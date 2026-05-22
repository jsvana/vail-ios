# VailMorse

A native iOS / iPadOS client for [vailmorse.com](https://vailmorse.com), the
internet Morse-code repeater. Built for CW operators who want low-latency
sidetone, native CoreMIDI support for the Vail Adapter and BLE MIDI keyers,
background audio for listening while the phone is locked, and an interface
that doesn't fight Mobile Safari for audio session control.

This is **v0 scaffolding** — a working architecture for you to iterate on, not
a finished app.

## Read first

[`CLAUDE.md`](./CLAUDE.md) contains the full protocol specification, audio
model, and architectural decisions, written for future Claude sessions to pick
up the codebase quickly. Read it before making significant changes.

## What works

- WebSocket connection to vailmorse.com with the modern JSON protocol
- Clock-offset tracking and 15s keepalive
- Echo suppression of own transmissions with lag measurement
- TX local sidetone (continuous oscillator with 5ms ramp)
- RX scheduled playback with per-sender tone pool
- CoreMIDI input from Vail Adapter (notes 0/1/2 = straight/dit/dah)
- Roster display (connected users with their TX tones)
- Channel switching
- Touch-input "big key" for testing without a hardware keyer
- Stuck-key auto-cutoff

## What's deferred

These have architectural hooks in the code but no implementation yet. See
CLAUDE.md §6 for details.

- Recording channel sessions (audio file)
- Chat UI (protocol layer handles it; needs SwiftUI view)
- CW decoder
- MIDI output to adapter for RX piezo feedback
- BLE MIDI pairing UI
- Background audio entitlement
- Settings persistence (UserDefaults)
- Telegraph-sound mode (vs pure sine sidetone)

## Setup

### Option A: XcodeGen (recommended for engineers who use it)

```bash
brew install xcodegen
cd VailMorse
xcodegen generate
open VailMorse.xcodeproj
```

### Option B: Manual Xcode project

1. In Xcode: File → New → Project → iOS → App
2. Product name: `VailMorse`. Interface: SwiftUI. Language: Swift.
3. Delete the auto-generated `VailMorseApp.swift` and `ContentView.swift`.
4. Drag the `Sources/` folder into the project navigator. Choose "Create
   groups" not "Create folder references".
5. Add to your target's `Info.plist`:
   - `NSMicrophoneUsageDescription` (only if you add recording later)
6. Set deployment target to iOS 17.0 (uses `Observable`, `for await` on
   `URLSessionWebSocketTask`, etc.)

## Running on hardware

CoreMIDI USB device support requires a physical iPhone or iPad. Simulator
does not enumerate USB MIDI devices.

For the Vail Adapter:
- iPhone 15+ / USB-C iPad: plug in directly with USB-C cable
- Older iPhone (Lightning): use Apple's Lightning-to-USB Camera Adapter
- BLE MIDI keyer: pair in iOS Settings → Bluetooth → "Other Devices", then
  use `CABTMIDICentralViewController` in-app (not yet wired in v0)

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      SwiftUI views (@MainActor)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │ observed state
┌────────────────────────────▼────────────────────────────────────┐
│                  VailSession (@MainActor, ObservableObject)      │
│  - orchestrates protocol + audio + input                         │
│  - publishes roster, connection state, chat                      │
│  - implements stuck-key safety                                   │
└──┬──────────────────────┬──────────────────────────┬─────────────┘
   │                      │                          │
┌──▼──────────┐    ┌──────▼──────┐         ┌─────────▼──────────┐
│ VailClient  │    │ KeyerEngine │         │     MIDIInput      │
│ (actor)     │    │             │         │ (CoreMIDI client)  │
│             │    │             │         │                    │
│ WebSocket   │    │ TX oscillator│         │ packet → key event │
│ JSON codec  │    │ RX pool     │          │ mach timestamps    │
│ echo dedup  │    │ AVAudioEngine│         │                    │
│ keepalive   │    │             │         │                    │
└─────────────┘    └─────────────┘         └────────────────────┘
```

See CLAUDE.md §6 for full data flow.

## Where to look first

| Want to change…                 | Open this file                       |
|---------------------------------|--------------------------------------|
| Wire protocol / JSON shape      | `Sources/Protocol/VailMessage.swift` |
| WebSocket / echo / keepalive    | `Sources/Protocol/VailClient.swift`  |
| Audio rendering / tone pool     | `Sources/Audio/KeyerEngine.swift`    |
| Vail Adapter integration        | `Sources/Input/MIDIInput.swift`      |
| Top-level orchestration         | `Sources/ViewModels/VailSession.swift` |
| Connect to vailmorse.com        | `Sources/Protocol/VailClient.swift` (`baseURL`) |
| UI                              | `Sources/Views/*.swift`              |

## Things to confirm before launching anything

1. **DevTools spot-check the WebSocket frames** on vailmorse.com. Confirm
   `UsersInfo` field name (could be `Callsign`/`TxTone` or `Name`/`Tone`).
   I extracted field names from the JS but didn't see live traffic.
2. **Run on real hardware with a Vail Adapter.** MIDI packet timestamps in
   the simulator may not match physical behavior.
3. **Verify echo suppression** by keying on two devices on the same channel.
   You should hear yourself once (local sidetone) and the other device should
   hear you exactly once.
4. **Test stuck-key behavior** by deliberately holding a key for >10 seconds.

## Code style

- Pure Apple frameworks: Foundation, AVFoundation, CoreMIDI, SwiftUI. No SPM
  deps unless there's a strong reason.
- Errors via typed enums per module.
- `os.Logger` for logging (not `print`).
- See CLAUDE.md §8.
