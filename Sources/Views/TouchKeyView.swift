// TouchKeyView.swift
// Big touch key. Same gesture, four visual treatments per AppTheme.
//
// Uses DragGesture with onChanged/onEnded for down/up detection — TapGesture
// doesn't give you press-down events, only fires on release.
// UITouch.timestamp would be more accurate than current wall clock but for
// touch input the ~50-80ms screen latency floor dominates either way.

import SwiftUI

struct TouchKeyView: View {
    @EnvironmentObject var session: VailSession
    @Environment(\.appTheme) private var theme
    @State private var isPressed: Bool = false

    var body: some View {
        ZStack {
            shape
                .fill(fillColor)

            if theme.keyBorderWidth > 0 {
                shape
                    .stroke(borderColor, lineWidth: theme.keyBorderWidth)
            }

            VStack(spacing: 4) {
                Text(label)
                    .font(labelFont)
                    .tracking(labelTracking)
                    .foregroundStyle(textColor)
                    .shadow(
                        color: theme.hasPhosphorGlow
                            ? theme.palette.accent.opacity(0.5)
                            : .clear,
                        radius: 3
                    )
                if let hint {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: theme.numericDesign))
                        .tracking(theme.labelsAllCaps ? theme.labelTracking : 0)
                        .foregroundStyle(textColor.opacity(0.7))
                }
                if theme == .crt && !isPressed {
                    BlinkingCursor(color: theme.palette.accent)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.06), value: isPressed)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        session.touchKey(isDown: true)
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        session.touchKey(isDown: false)
                    }
                }
        )
        .accessibilityLabel("Morse key")
        .accessibilityHint("Press and hold to send a tone")
    }

    // MARK: - Theme-driven visuals

    private var shape: some Shape {
        RoundedRectangle(cornerRadius: theme.primaryCornerRadius)
    }

    private var fillColor: Color {
        switch theme {
        case .quiet:
            return isPressed ? theme.palette.accent : theme.palette.ink
        case .spec, .retro:
            return theme.palette.accent.opacity(isPressed ? 0.82 : 1)
        case .crt:
            return isPressed ? theme.palette.accent : .clear
        }
    }

    private var borderColor: Color {
        switch theme {
        case .crt: return theme.palette.accent
        case .retro: return theme.palette.ink.opacity(0.6)
        default: return .clear
        }
    }

    private var textColor: Color {
        switch theme {
        case .quiet: return Color.white
        case .spec, .retro: return theme.palette.canvas
        case .crt: return isPressed ? theme.palette.canvas : theme.palette.accent
        }
    }

    private var label: String {
        theme.keyLabel
    }

    private var labelFont: Font {
        switch theme {
        case .quiet: .system(size: 22, weight: .semibold, design: .default)
        case .spec: .system(size: 24, weight: .bold, design: .default)
        case .retro: .system(size: 18, weight: .heavy, design: .serif)
        case .crt: .system(size: 22, weight: .regular, design: .monospaced)
        }
    }

    private var labelTracking: CGFloat {
        switch theme {
        case .retro: 8
        case .crt: 2
        case .spec: 0.4
        case .quiet: -0.4
        }
    }

    private var hint: String? {
        switch theme {
        case .quiet:
            return "\(midiNoteName(session.txTone))"
        case .spec:
            let note = midiNoteName(session.txTone)
            return session.breakInEnabled ? "TX \(note) · ARMED" : "TX \(note)"
        case .retro:
            return "hold to transmit"
        case .crt:
            return nil
        }
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}

// MARK: - Blinking cursor (CRT only)

private struct BlinkingCursor: View {
    let color: Color
    @State private var visible: Bool = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 10, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.0).repeatForever(autoreverses: true).delay(0.5)) {
                    visible.toggle()
                }
            }
            .accessibilityHidden(true)
    }
}
