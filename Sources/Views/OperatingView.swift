// OperatingView.swift
// The main operating screen. Status, channel, activity timeline, big touch
// key, and break-in control. Every visual is theme-token-driven; see
// Sources/Theme/AppTheme.swift for token definitions.

import SwiftUI

struct OperatingView: View {
    @EnvironmentObject var session: VailSession
    @EnvironmentObject var runner: SkedRunner
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.palette.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                statusBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                if runner.activeRun != nil || runner.pendingSked != nil {
                    skedBanner
                        .padding(.horizontal, 18)
                }

                channelBlock
                    .padding(.horizontal, 18)

                statRow
                    .padding(.horizontal, 18)

                SignalTimelineView()
                    .padding(.horizontal, 18)

                Spacer(minLength: 0)

                TouchKeyView()
                    .frame(maxWidth: 480, maxHeight: 160)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)

                controlsBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }

            if theme.hasScanlines {
                ScanlineOverlay()
                    .ignoresSafeArea()
            }
        }
        .foregroundStyle(theme.palette.ink)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateText)
                .font(.system(size: 11, weight: .medium, design: theme.numericDesign))
                .tracking(theme.labelTracking)
                .textCase(theme.labelsAllCaps ? .uppercase : nil)
                .foregroundStyle(theme.palette.inkMute)
            Spacer()
            if session.lagMs > 0 {
                Text(theme.labelsAllCaps ? "LAG \(session.lagMs)MS" : "Lag \(session.lagMs) ms")
                    .font(.system(size: 11, weight: .medium, design: theme.numericDesign))
                    .tracking(theme.labelTracking)
                    .foregroundStyle(theme.palette.inkMute)
            }
        }
    }

    private var stateColor: Color {
        switch session.connectionState {
        case .connected: theme.palette.live
        case .connecting, .reconnecting: theme.palette.accent
        case .disconnected, .idleDisconnected: theme.palette.transmit
        }
    }

    private var stateText: String {
        switch session.connectionState {
        case .connected: "Connected · \(session.channel)"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Disconnected"
        case .idleDisconnected: "Idle"
        }
    }

    // MARK: - Sked banner

    @ViewBuilder
    private var skedBanner: some View {
        if let run = runner.activeRun {
            ThemedBanner(theme: theme, accent: theme.palette.live) {
                bannerRow(BannerContent(
                    icon: "calendar.badge.clock",
                    iconColor: theme.palette.live,
                    title: "Running: \(run.title)",
                    sub: run.participants.isEmpty
                        ? "On \(run.channel)"
                        : "\(run.participants.count) on \(run.channel)",
                    primaryLabel: "End",
                    primaryAction: { runner.endActiveRun() },
                    primaryTint: theme.palette.transmit,
                    secondaryLabel: nil,
                    secondaryAction: nil
                ))
            }
        } else if let sked = runner.pendingSked {
            ThemedBanner(theme: theme, accent: theme.palette.accent) {
                bannerRow(BannerContent(
                    icon: "calendar.badge.exclamationmark",
                    iconColor: theme.palette.accent,
                    title: "Sked: \(sked.title)",
                    sub: "On \(sked.channel)",
                    primaryLabel: "Join",
                    primaryAction: { runner.join(sked) },
                    primaryTint: theme.palette.accent,
                    secondaryLabel: "Dismiss",
                    secondaryAction: { runner.dismissPrompt() }
                ))
            }
        }
    }

    private struct BannerContent {
        let icon: String
        let iconColor: Color
        let title: String
        let sub: String
        let primaryLabel: String
        let primaryAction: () -> Void
        let primaryTint: Color
        let secondaryLabel: String?
        let secondaryAction: (() -> Void)?
    }

    private func bannerRow(_ data: BannerContent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: data.icon)
                .foregroundStyle(data.iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(data.title)
                    .font(.system(size: 14, weight: .semibold, design: theme.bodyDesign))
                    .foregroundStyle(theme.palette.ink)
                Text(data.sub)
                    .font(.system(size: 12, design: theme.bodyDesign))
                    .foregroundStyle(theme.palette.inkMute)
            }
            Spacer()
            if let label = data.secondaryLabel, let action = data.secondaryAction {
                Button(label, action: action)
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.palette.inkMute)
            }
            Button(data.primaryLabel, action: data.primaryAction)
                .buttonStyle(.borderedProminent)
                .tint(data.primaryTint)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Channel block

    private var channelBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if theme.usesChannelDividers {
                ThemedRule(color: theme.palette.rule, weight: theme == .retro ? 2 : 1)
                    .padding(.bottom, 8)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(session.channel)
                    .font(displayFont)
                    .tracking(theme == .retro ? -1 : -0.5)
                    .foregroundStyle(theme.palette.ink)
                    .shadow(
                        color: theme.hasPhosphorGlow
                            ? theme.palette.accent.opacity(0.45)
                            : .clear,
                        radius: 4
                    )
                Spacer()
                if theme == .crt {
                    Text(theme.connectedHint(count: session.clientCount))
                        .font(.system(size: 14, design: theme.numericDesign))
                        .foregroundStyle(theme.palette.inkMute)
                }
            }
            if theme != .crt {
                Text(theme.connectedHint(count: session.clientCount))
                    .font(.system(size: 13, design: theme.bodyDesign))
                    .italic(theme == .retro)
                    .foregroundStyle(theme.palette.inkMute)
            }
            if let notice = session.lastNotice {
                Text(notice)
                    .font(.system(size: 12, design: theme.bodyDesign))
                    .foregroundStyle(theme.palette.transmit)
                    .padding(.top, 2)
            }
            if theme.usesChannelDividers {
                ThemedRule(color: theme.palette.rule, weight: 1)
                    .padding(.top, 8)
            }
        }
    }

    private var displayFont: Font {
        switch theme {
        case .quiet: .system(size: 32, weight: .semibold, design: .default)
        case .spec: .system(size: 30, weight: .semibold, design: .default)
        case .retro: .system(size: 40, weight: .heavy, design: .serif)
        case .crt: .system(size: 36, weight: .regular, design: .monospaced)
        }
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack(spacing: 14) {
            statCell(label: "TX Tone", value: midiNoteName(session.txTone), highlight: true)
            ThemedRule(color: theme.palette.rule, weight: 1).frame(width: 1, height: 28).fixedSize()
            statCell(label: "Lag", value: "\(session.lagMs)ms", highlight: false)
            ThemedRule(color: theme.palette.rule, weight: 1).frame(width: 1, height: 28).fixedSize()
            statCell(label: "Ops", value: "\(session.clientCount)", highlight: false)
        }
    }

    private func statCell(label: String, value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(theme.labelsAllCaps ? label.uppercased() : label)
                .font(.system(size: 9, weight: .medium, design: theme.numericDesign))
                .tracking(theme.labelTracking)
                .foregroundStyle(theme.palette.inkMute)
            Text(value)
                .font(.system(size: 17, weight: .medium, design: theme.numericDesign))
                .monospacedDigit()
                .foregroundStyle(highlight ? theme.palette.accent : theme.palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 12) {
            Text(theme.labelsAllCaps ? "BREAK-IN" : "Break-in")
                .font(.system(size: 13, weight: .medium, design: theme.bodyDesign))
                .tracking(theme.labelTracking * 0.7)
                .foregroundStyle(theme.palette.inkMute)
            Spacer()
            Toggle("", isOn: $session.breakInEnabled)
                .labelsHidden()
                .tint(theme.palette.transmit)
            Text(session.breakInEnabled
                ? (theme.labelsAllCaps ? "LIVE" : "Live")
                : (theme.labelsAllCaps ? "OFF" : "Off"))
                .font(.system(size: 12, weight: .semibold, design: theme.numericDesign))
                .tracking(theme.labelTracking)
                .foregroundStyle(session.breakInEnabled ? theme.palette.transmit : theme.palette.inkLow)
                .frame(width: 44, alignment: .leading)
        }
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}

// MARK: - Themed banner

private struct ThemedBanner<Content: View>: View {
    let theme: AppTheme
    let accent: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content()
        }
    }

    @ViewBuilder
    private var background: some View {
        switch theme {
        case .quiet:
            RoundedRectangle(cornerRadius: theme.secondaryCornerRadius)
                .fill(theme.palette.surface)
        case .spec:
            Rectangle()
                .fill(theme.palette.surface)
                .overlay(
                    Rectangle()
                        .stroke(theme.palette.rule, lineWidth: 1)
                )
        case .retro:
            Rectangle()
                .fill(theme.palette.surface)
                .overlay(
                    Rectangle()
                        .stroke(theme.palette.ink, lineWidth: 1)
                )
        case .crt:
            Rectangle()
                .fill(theme.palette.canvas)
                .overlay(
                    Rectangle()
                        .stroke(accent, lineWidth: 1)
                )
        }
    }
}

// MARK: - Themed rule

private struct ThemedRule: View {
    let color: Color
    let weight: CGFloat

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: weight)
            .frame(maxWidth: .infinity)
    }
}
