// ThemeEnvironment.swift
// Bridges the AppStorage-backed theme choice into the SwiftUI environment so
// any view can read `@Environment(\.appTheme)` without going through a global.

import SwiftUI

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .quiet
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// View modifier that paints the canvas, optionally overlays CRT scanlines,
/// and applies the theme's preferred color scheme + accent tint.
struct AppThemeRoot: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, theme)
            .tint(theme.palette.accent)
            .preferredColorScheme(theme.preferredColorScheme)
    }
}

extension View {
    func appThemeRoot(_ theme: AppTheme) -> some View {
        modifier(AppThemeRoot(theme: theme))
    }
}

/// Repeating-line overlay for CRT theme. Sits on top of content but ignores
/// hit testing so it doesn't intercept touches.
struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let lineEvery: CGFloat = 3
                var yPos: CGFloat = 0
                while yPos < size.height {
                    let rect = CGRect(x: 0, y: yPos, width: size.width, height: 1)
                    ctx.fill(Path(rect), with: .color(.black.opacity(0.22)))
                    yPos += lineEvery
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}
