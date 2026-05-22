// TouchKeyView.swift
// A big touch button that acts as a straight key.
//
// Uses DragGesture with onChanged/onEnded for down/up detection — TapGesture
// doesn't give you press-down events, only fires on release.
// UITouch.timestamp would be more accurate than current wall clock but for
// touch input the ~50-80ms screen latency floor dominates either way.

import SwiftUI

struct TouchKeyView: View {
    @EnvironmentObject var session: VailSession
    @State private var isPressed: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(isPressed ? Color.accentColor : Color.accentColor.opacity(0.25))
                .shadow(radius: isPressed ? 2 : 8)

            VStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(isPressed ? .white : .accentColor)
                Text("KEY")
                    .font(.title.weight(.bold))
                    .foregroundStyle(isPressed ? .white : .primary)
            }
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.05), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: 32))
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
}
