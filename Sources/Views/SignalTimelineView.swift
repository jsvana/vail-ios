// SignalTimelineView.swift
// Horizontal timeline of sent and received CW tones + chat events, one lane
// per callsign. Auto-follows wall-clock now; drag right to pan back into the
// past, tap "Live" to resume. All visuals are theme-driven; see AppTheme.

import SwiftUI

// swiftlint:disable:next type_body_length
struct SignalTimelineView: View {
    @EnvironmentObject var session: VailSession
    @EnvironmentObject var contacts: ContactStore
    @Environment(\.appTheme) private var theme

    /// How many ms wide the visible window is. 30s gives enough room to see a
    /// short exchange without bars becoming pixel-thin.
    private let windowMs: Int64 = 30000
    private let rowHeight: CGFloat = 22
    private let rowSpacing: CGFloat = 4
    private let labelWidth: CGFloat = 82
    private let maxBodyHeight: CGFloat = 180

    /// Offset from wall-clock now, in ms. 0 = live, positive = panned into the past.
    @State private var panOffsetMs: Int64 = 0
    @State private var dragStartOffsetMs: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ThemedHairline(color: theme.palette.rule)
            TimelineView(.animation(minimumInterval: 0.05, paused: false)) { ctx in
                let nowMs = Int64(ctx.date.timeIntervalSince1970 * 1000)
                bodyContent(nowMs: nowMs)
            }
        }
        .background(timelineBackground)
    }

    @ViewBuilder
    private var timelineBackground: some View {
        switch theme {
        case .quiet:
            RoundedRectangle(cornerRadius: theme.secondaryCornerRadius)
                .fill(theme.palette.surface2)
        case .spec, .retro:
            Rectangle()
                .stroke(theme.palette.rule, lineWidth: 1)
        case .crt:
            Rectangle()
                .stroke(theme.palette.inkLow, lineWidth: 1)
        }
    }

    // MARK: - Header

    private var isLive: Bool {
        panOffsetMs <= 250
    }

    private var header: some View {
        HStack(spacing: 8) {
            if theme != .crt {
                Image(systemName: "waveform.path")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.palette.inkMute)
            }
            Text(theme.activityHeader)
                .font(.system(size: 12, weight: .semibold, design: theme.numericDesign))
                .tracking(theme.labelTracking * 0.8)
                .textCase(theme.labelsAllCaps ? .uppercase : nil)
                .foregroundStyle(theme.palette.inkMute)
            Spacer()
            if !isLive {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        panOffsetMs = 0
                    }
                } label: {
                    Label("Live", systemImage: "arrow.forward.to.line")
                        .font(.system(size: 11, weight: .semibold, design: theme.numericDesign))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(theme.palette.transmit)
            } else {
                HStack(spacing: 4) {
                    Circle().fill(theme.palette.live).frame(width: 6, height: 6)
                    Text(theme.labelsAllCaps ? "LIVE" : "Live")
                        .font(.system(size: 11, weight: .semibold, design: theme.numericDesign))
                        .tracking(theme.labelTracking * 0.8)
                        .foregroundStyle(theme.palette.live)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Body

    @ViewBuilder
    private func bodyContent(nowMs: Int64) -> some View {
        let endMs = nowMs - panOffsetMs
        let startMs = endMs - windowMs
        let events = session.signalEvents
        let liveStarts = session.liveOwnKeyStarts
        let own = session.callsign
        let roster = session.users.map(\.callsign)
        let lanes = laneOrder(
            events: events,
            ownCallsign: own,
            hasLiveOwn: !liveStarts.isEmpty,
            roster: roster
        )

        if lanes.isEmpty {
            emptyState
        } else {
            let contentHeight = CGFloat(lanes.count) * (rowHeight + rowSpacing) + 8
            ScrollView(.vertical, showsIndicators: false) {
                HStack(spacing: 0) {
                    labelColumn(lanes: lanes)
                    ThemedHairline(color: theme.palette.rule).frame(width: 1).fixedSize()
                    GeometryReader { geo in
                        Canvas { ctx, size in
                            drawTimeline(
                                ctx: ctx,
                                size: size,
                                events: events,
                                lanes: lanes,
                                ownCallsign: own,
                                liveOwnKeyStarts: liveStarts,
                                startMs: startMs,
                                endMs: endMs,
                                nowMs: nowMs
                            )
                        }
                        .contentShape(Rectangle())
                        .gesture(panGesture(canvasWidth: geo.size.width))
                    }
                    .frame(height: contentHeight)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: min(maxBodyHeight, contentHeight + 12))
            axisFooter(startMs: startMs, endMs: endMs, nowMs: nowMs)
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.palette.inkMute)
                Text(theme.labelsAllCaps ? "NO ACTIVITY" : "No activity yet")
                    .font(.system(size: 11, design: theme.numericDesign))
                    .tracking(theme.labelTracking)
                    .foregroundStyle(theme.palette.inkMute)
            }
            Spacer()
        }
        .frame(height: 80)
    }

    private func labelColumn(lanes: [String]) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(lanes, id: \.self) { call in
                let contact = contacts.contact(forCallsign: call)
                let isSelf = call == session.callsign
                HStack(spacing: 4) {
                    Circle()
                        .fill(theme.laneBarColor(forCallsign: call, isSelf: isSelf, hashColor: hashColor(for: call)))
                        .frame(width: 8, height: 8)
                    Text(call)
                        .font(.system(size: 10, weight: .medium, design: theme.numericDesign))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelf ? theme.palette.ink : theme.palette.inkMute)
                    if let contact {
                        Image(systemName: contact.isFavorite ? "star.fill" : "person.crop.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(contact.isFavorite ? theme.palette.accent : theme.palette.inkMute)
                            .accessibilityLabel(contact.isFavorite ? "Favorite contact" : "Saved contact")
                    }
                }
                .frame(height: rowHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: labelWidth, alignment: .leading)
        .padding(.leading, 10)
        .padding(.trailing, 6)
    }

    private func axisFooter(startMs: Int64, endMs: Int64, nowMs: Int64) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: labelWidth + 11)
            HStack {
                Text(relativeLabel(forMs: startMs, nowMs: nowMs))
                Spacer()
                Text(relativeLabel(forMs: (startMs + endMs) / 2, nowMs: nowMs))
                Spacer()
                Text(relativeLabel(forMs: endMs, nowMs: nowMs))
            }
            .font(.system(size: 9, design: theme.numericDesign))
            .tracking(theme.labelTracking * 0.6)
            .foregroundStyle(theme.palette.inkLow)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 6)
    }

    private func relativeLabel(forMs ms: Int64, nowMs: Int64) -> String {
        let delta = (ms - nowMs) / 1000
        if delta >= -1 && delta <= 0 { return theme.labelsAllCaps ? "NOW" : "now" }
        if delta < 0 { return "\(delta)s" }
        return "+\(delta)s"
    }

    // MARK: - Gesture

    private func panGesture(canvasWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if abs(value.translation.width) < 0.5 && abs(value.translation.height) < 0.5 {
                    dragStartOffsetMs = panOffsetMs
                    return
                }
                if value.startLocation == value.location {
                    dragStartOffsetMs = panOffsetMs
                }
                guard canvasWidth > 0 else { return }
                let msPerPx = CGFloat(windowMs) / canvasWidth
                // Drag to the right -> pan backwards in time (larger offset).
                let deltaMs = Int64(value.translation.width * msPerPx)
                panOffsetMs = max(0, dragStartOffsetMs + deltaMs)
            }
            .onEnded { _ in
                dragStartOffsetMs = panOffsetMs
                // Snap back to live if very close.
                if panOffsetMs < 500 {
                    withAnimation(.easeOut(duration: 0.15)) { panOffsetMs = 0 }
                }
            }
    }

    // MARK: - Drawing

    private func drawTimeline(
        ctx: GraphicsContext,
        size: CGSize,
        events: [SignalEvent],
        lanes: [String],
        ownCallsign: String,
        liveOwnKeyStarts: [Int64],
        startMs: Int64,
        endMs: Int64,
        nowMs: Int64
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let pxPerMs = size.width / CGFloat(windowMs)
        let rowFull = rowHeight + rowSpacing
        let cornerRadius: CGFloat = theme == .quiet ? 2 : 0
        let trackColor = theme.laneTrackColor

        // Row backgrounds.
        for i in 0 ..< lanes.count {
            let y = CGFloat(i) * rowFull
            ctx.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                with: .color(trackColor)
            )
        }

        // 5-second gridlines.
        let firstGrid = ((startMs / 5000) + 1) * 5000
        var g = firstGrid
        while g <= endMs {
            let x = CGFloat(g - startMs) * pxPerMs
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                },
                with: .color(theme.palette.rule.opacity(0.55)),
                lineWidth: 0.5
            )
            g += 5000
        }

        // "Now" marker — vertical line at wall-clock now.
        let nowX = CGFloat(nowMs - startMs) * pxPerMs
        if nowX >= 0, nowX <= size.width {
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: nowX, y: 0))
                    p.addLine(to: CGPoint(x: nowX, y: size.height))
                },
                with: .color(theme.palette.transmit.opacity(0.6)),
                lineWidth: 1
            )
        }

        // Index lanes by callsign.
        var laneIndex: [String: Int] = [:]
        laneIndex.reserveCapacity(lanes.count)
        for (i, c) in lanes.enumerated() {
            laneIndex[c] = i
        }

        // Live bars for in-progress local keys.
        if !liveOwnKeyStarts.isEmpty, let lane = laneIndex[ownCallsign] {
            let y = CGFloat(lane) * rowFull
            let liveColor = theme.laneBarColor(
                forCallsign: ownCallsign,
                isSelf: true,
                hashColor: hashColor(for: ownCallsign)
            )
            for start in liveOwnKeyStarts {
                let live = max(start, nowMs)
                if live < startMs || start > endMs { continue }
                let xRaw = CGFloat(start - startMs) * pxPerMs
                let wRaw = max(2, CGFloat(live - start) * pxPerMs)
                let x = max(0, xRaw)
                let w = max(2, min(size.width - x, xRaw + wRaw - x))
                guard w > 0 else { continue }
                let rect = CGRect(x: x, y: y + 3, width: w, height: rowHeight - 6)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: cornerRadius),
                    with: .color(liveColor)
                )
            }
        }

        // Events.
        for event in events {
            let eStart = event.startLocalMs
            let eEnd = event.endLocalMs
            if eEnd < startMs || eStart > endMs { continue }
            guard let lane = laneIndex[event.callsign] else { continue }
            let y = CGFloat(lane) * rowFull
            let isSelf = event.callsign == ownCallsign
            let baseColor = theme.laneBarColor(
                forCallsign: event.callsign,
                isSelf: isSelf,
                hashColor: hashColor(for: event.callsign)
            )

            switch event.kind {
            case let .tone(dur, _):
                let xRaw = CGFloat(eStart - startMs) * pxPerMs
                let wRaw = max(2, CGFloat(dur) * pxPerMs)
                let x = max(0, xRaw)
                let w = max(2, min(size.width - x, xRaw + wRaw - x))
                guard w > 0 else { continue }
                let rect = CGRect(x: x, y: y + 3, width: w, height: rowHeight - 6)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: cornerRadius),
                    with: .color(baseColor)
                )

            case .chat:
                let x = CGFloat(eStart - startMs) * pxPerMs
                if x < -8 || x > size.width + 8 { continue }
                let cy = y + rowHeight / 2
                var p = Path()
                p.move(to: CGPoint(x: x, y: cy - 6))
                p.addLine(to: CGPoint(x: x + 5, y: cy))
                p.addLine(to: CGPoint(x: x, y: cy + 6))
                p.addLine(to: CGPoint(x: x - 5, y: cy))
                p.closeSubpath()
                ctx.fill(p, with: .color(baseColor))
                ctx.stroke(p, with: .color(theme.palette.canvas.opacity(0.6)), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Lane ordering

    private func laneOrder(
        events: [SignalEvent],
        ownCallsign: String,
        hasLiveOwn: Bool,
        roster: [String]
    ) -> [String] {
        var lastSeen: [String: Int64] = [:]
        for event in events {
            let endTime = event.endLocalMs
            if let prev = lastSeen[event.callsign], prev >= endTime { continue }
            lastSeen[event.callsign] = endTime
        }
        if !ownCallsign.isEmpty, hasLiveOwn, lastSeen[ownCallsign] == nil {
            lastSeen[ownCallsign] = .max
        }

        var seen = Set<String>()
        var result: [String] = []

        if !ownCallsign.isEmpty {
            result.append(ownCallsign)
            seen.insert(ownCallsign)
        }

        let active = lastSeen.keys
            .filter { $0 != ownCallsign }
            .sorted { (lastSeen[$0] ?? 0) > (lastSeen[$1] ?? 0) }
        for call in active where !seen.contains(call) {
            result.append(call)
            seen.insert(call)
        }

        let quiet = roster.filter { !seen.contains($0) }.sorted()
        result.append(contentsOf: quiet)

        return result
    }

    // MARK: - Hash color (used by themes that want per-callsign variety)

    private func hashColor(for callsign: String) -> Color {
        var hash: UInt64 = 5381
        for byte in callsign.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        let sat = theme == .spec ? 0.45 : 0.62
        let bright = theme == .spec ? 0.78 : 0.86
        return Color(hue: hue, saturation: sat, brightness: bright)
    }
}

// MARK: - Themed hairline

private struct ThemedHairline: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}
