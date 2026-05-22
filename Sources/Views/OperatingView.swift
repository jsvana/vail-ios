// OperatingView.swift
// The main operating screen: status, big touch key, current room info.

import SwiftUI

struct OperatingView: View {
    @EnvironmentObject var session: VailSession

    var body: some View {
        VStack(spacing: 16) {
            statusBar
                .padding(.horizontal)
                .padding(.top, 8)

            channelHeader

            Spacer()

            TouchKeyView()
                .frame(maxWidth: 400, maxHeight: 400)
                .padding()

            Spacer()

            controlsBar
                .padding(.horizontal)
                .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(stateText).font(.caption.weight(.medium))
            Spacer()
            if session.lagMs > 0 {
                Text("Lag: \(session.lagMs)ms")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var channelHeader: some View {
        VStack(spacing: 4) {
            Text(session.channel)
                .font(.title2.weight(.semibold))
            Text("\(session.clientCount) connected")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notice = session.lastNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
    }

    private var controlsBar: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $session.breakInEnabled) {
                HStack {
                    Image(systemName: session.breakInEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    Text("Break-in (TX)")
                }
            }
            .tint(.red)

            if session.breakInEnabled {
                Text("Transmitting to channel")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var stateColor: Color {
        switch session.connectionState {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected, .idleDisconnected: .red
        }
    }

    private var stateText: String {
        switch session.connectionState {
        case .connected: "Connected to \(session.channel)"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .disconnected: "Disconnected"
        case .idleDisconnected: "Idle (will reconnect on activity)"
        }
    }
}
