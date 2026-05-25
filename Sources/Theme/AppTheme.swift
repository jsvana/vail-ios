// AppTheme.swift
// Four committed aesthetic directions for the app. Each theme carries its own
// palette, typography, ornament, and required color scheme. Theme is the
// operator's choice (Settings → Appearance) and persists via @AppStorage.
//
// Tokens are exposed as SwiftUI Color / Font.Design values so views can stay
// theme-agnostic and just read what they need from the environment.

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case quiet
    case spec
    case retro
    case crt

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .quiet: "Quiet utility"
        case .spec: "Spec instrument"
        case .retro: "Retro telegraph"
        case .crt: "CRT terminal"
        }
    }

    var tagline: String {
        switch self {
        case .quiet: "Refined, content-forward, stays out of the way."
        case .spec: "Aviation EFB readouts. Mono numerics, sharp rules."
        case .retro: "Bakelite and parchment, without the costume."
        case .crt: "Amber phosphor, scanlines, blinking cursor."
        }
    }
}

// MARK: - Color scheme

extension AppTheme {
    /// Each theme requires a specific color scheme because its palette only
    /// works in one. The app forces this via .preferredColorScheme at the root.
    var preferredColorScheme: ColorScheme {
        switch self {
        case .quiet, .retro: .light
        case .spec, .crt: .dark
        }
    }
}

// MARK: - Palette

struct ThemePalette {
    let canvas: Color // root background
    let surface: Color // raised surface
    let surface2: Color // most raised
    let ink: Color // primary text/icon
    let inkMute: Color // secondary text
    let inkLow: Color // tertiary text / hairlines on surface
    let rule: Color // separators
    let accent: Color // theme accent (key, own callsign, primary action)
    let live: Color // connected / live indicator
    let transmit: Color // transmit / break-in armed
}

extension AppTheme {
    var palette: ThemePalette {
        switch self {
        case .quiet:
            ThemePalette(
                canvas: Color(hex: 0xF7F7F8),
                surface: Color(hex: 0xFFFFFF),
                surface2: Color(hex: 0xEFEFF1),
                ink: Color(hex: 0x2F323A),
                inkMute: Color(hex: 0x83858E),
                inkLow: Color(hex: 0xB6B8BE),
                rule: Color(hex: 0xE4E5E7),
                accent: Color(hex: 0x5D7EB8),
                live: Color(hex: 0x5FB37F),
                transmit: Color(hex: 0xCD6E58)
            )
        case .spec:
            ThemePalette(
                canvas: Color(hex: 0x22252C),
                surface: Color(hex: 0x2C2F37),
                surface2: Color(hex: 0x373A43),
                ink: Color(hex: 0xF1F2F3),
                inkMute: Color(hex: 0x969AA3),
                inkLow: Color(hex: 0x686C75),
                rule: Color(hex: 0x484C55),
                accent: Color(hex: 0xDAB64A), // amber
                live: Color(hex: 0x7EC690), // phosphor green
                transmit: Color(hex: 0xDC7E6C)
            )
        case .retro:
            ThemePalette(
                canvas: Color(hex: 0xEFE9D6), // parchment
                surface: Color(hex: 0xF5EFDD),
                surface2: Color(hex: 0xD8D2C0),
                ink: Color(hex: 0x322A23),
                inkMute: Color(hex: 0x5E524A),
                inkLow: Color(hex: 0x8E817A),
                rule: Color(hex: 0xBDB29F),
                accent: Color(hex: 0x85363A), // oxblood
                live: Color(hex: 0x9E8049), // brass
                transmit: Color(hex: 0x85363A)
            )
        case .crt:
            ThemePalette(
                canvas: Color(hex: 0x1D1812),
                surface: Color(hex: 0x231D15),
                surface2: Color(hex: 0x2C241A),
                ink: Color(hex: 0xE5B962), // bright amber
                inkMute: Color(hex: 0x9D8348), // dim amber
                inkLow: Color(hex: 0x5E4F33),
                rule: Color(hex: 0x5E4F33),
                accent: Color(hex: 0xE5B962),
                live: Color(hex: 0xB6E078), // green phosphor for variety
                transmit: Color(hex: 0xDD765F)
            )
        }
    }
}

// MARK: - Typography

extension AppTheme {
    /// Font design for display text (channel name, key label).
    var displayDesign: Font.Design {
        switch self {
        case .quiet: .default
        case .spec: .default
        case .retro: .serif
        case .crt: .monospaced
        }
    }

    /// Font design for body text.
    var bodyDesign: Font.Design {
        switch self {
        case .quiet: .default
        case .spec: .default
        case .retro: .serif
        case .crt: .monospaced
        }
    }

    /// Font design for technical readouts (lag, callsigns, stats).
    var numericDesign: Font.Design {
        switch self {
        case .quiet: .default
        case .spec: .monospaced
        case .retro: .serif
        case .crt: .monospaced
        }
    }

    /// Whether small labels (stat captions, eyebrow text) should render as
    /// uppercase with letter-spacing tracking.
    var labelsAllCaps: Bool {
        switch self {
        case .quiet: false
        case .spec, .retro, .crt: true
        }
    }

    /// Letter-spacing for tracked-out labels (only meaningful when
    /// `labelsAllCaps` is true, but available for any tracked text).
    var labelTracking: CGFloat {
        switch self {
        case .quiet: 0
        case .spec: 1.6
        case .retro: 2.0
        case .crt: 0.8
        }
    }
}

// MARK: - Ornament / structure

extension AppTheme {
    /// Corner radius for primary tactile surfaces (the key, sheets).
    var primaryCornerRadius: CGFloat {
        switch self {
        case .quiet: 20
        case .spec: 0
        case .retro: 0
        case .crt: 0
        }
    }

    /// Corner radius for secondary cards (banners, control rows).
    var secondaryCornerRadius: CGFloat {
        switch self {
        case .quiet: 14
        case .spec: 0
        case .retro: 0
        case .crt: 0
        }
    }

    /// Render scanlines on top of the canvas.
    var hasScanlines: Bool {
        self == .crt
    }

    /// Render a faint phosphor glow on display text.
    var hasPhosphorGlow: Bool {
        self == .crt
    }

    /// Show a hairline at the top and bottom of the channel block.
    var usesChannelDividers: Bool {
        switch self {
        case .spec, .retro: true
        case .quiet, .crt: false
        }
    }

    /// Border weight (pt) for the key button. 0 = filled, no border.
    var keyBorderWidth: CGFloat {
        switch self {
        case .crt: 2
        case .retro: 1
        case .spec, .quiet: 0
        }
    }
}

// MARK: - Lane color logic

extension AppTheme {
    /// What color a callsign's tone bar should render as in the signal
    /// timeline. For themes with a singular voice (CRT, Retro), every non-self
    /// callsign uses inkMute so the signal stays in palette; richer themes
    /// keep per-callsign hash colors so multi-op activity is glanceable.
    func laneBarColor(forCallsign _: String, isSelf: Bool, hashColor: Color) -> Color {
        if isSelf { return palette.accent }
        switch self {
        case .crt, .retro: return palette.inkMute
        case .spec, .quiet: return hashColor
        }
    }

    /// Background color for the lane track (the rail behind the bars).
    var laneTrackColor: Color {
        switch self {
        case .quiet: palette.rule
        case .spec, .retro: palette.surface
        case .crt: palette.canvas
        }
    }
}

// MARK: - Voice (microcopy that varies by theme)

extension AppTheme {
    var keyLabel: String {
        switch self {
        case .quiet: "Hold to send"
        case .spec: "Hold to send"
        case .retro: "Strike"
        case .crt: "HOLD TO TX"
        }
    }

    var activityHeader: String {
        switch self {
        case .quiet: "Activity"
        case .spec: "ACTIVITY / 30s"
        case .retro: "Activity"
        case .crt: "ACTIVITY ── 30s"
        }
    }

    func connectedHint(count: Int) -> String {
        switch self {
        case .quiet: "\(count) operators on the channel"
        case .spec: "\(count) OPS · LIVE"
        case .retro: "in conversation with \(count) operators"
        case .crt: "\(count) OPS · LIVE"
        }
    }
}

// MARK: - Color helper

extension Color {
    /// Build a Color from a 0xRRGGBB literal.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
