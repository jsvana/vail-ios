// SignalTimelineView.swift
// Horizontal timeline of sent and received CW tones + chat events, one lane
// per callsign. Auto-follows wall-clock now; drag right to pan back into the
// past, tap "Live" to resume.

import SwiftUI

struct SignalTimelineView: View {
    @EnvironmentObject var session: VailSession
    @EnvironmentObject var contacts: ContactStore

    /// How many ms wide the visible window is. 30s gives enough room to see a
    /// short exchange without bars becoming pixel-thin.
    private let windowMs: Int64 = 30000
    private let rowHeight: CGFloat = 24
    private let rowSpacing: CGFloat = 4
    private let labelWidth: CGFloat = 78
    private let maxBodyHeight: CGFloat = 180

    /// Offset from wall-clock now, in ms. 0 = live, positive = panned into the past.
    @State private var panOffsetMs: Int64 = 0
    @State private var dragStartOffsetMs: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            TimelineView(.animation(minimumInterval: 0.05, paused: false)) { ctx in
                let nowMs = Int64(ctx.date.timeIntervalSince1970 * 1000)
                bodyContent(nowMs: nowMs)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Header

    private var isLive: Bool {
        panOffsetMs <= 250
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Activity")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if !isLive {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        panOffsetMs = 0
                    }
                } label: {
                    Label("Live", systemImage: "arrow.forward.to.line")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.red)
            } else {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
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
                    Divider()
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
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No activity yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 80)
    }

    private func labelColumn(lanes: [String]) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(lanes, id: \.self) { call in
                let contact = contacts.contact(forCallsign: call)
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(for: call))
                        .frame(width: 8, height: 8)
                    Text(call)
                        .font(.caption2.weight(.medium).monospaced())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(call == session.callsign ? .primary : .secondary)
                    if let contact {
                        Image(systemName: contact.isFavorite ? "star.fill" : "person.crop.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(contact.isFavorite ? .yellow : .blue)
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
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 6)
    }

    private func relativeLabel(forMs ms: Int64, nowMs: Int64) -> String {
        let delta = (ms - nowMs) / 1000
        if delta >= -1 && delta <= 0 { return "now" }
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

        // Row backgrounds.
        for i in 0 ..< lanes.count {
            let y = CGFloat(i) * rowFull
            ctx.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                with: .color(Color(.tertiarySystemGroupedBackground))
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
                with: .color(Color(.separator).opacity(0.35)),
                lineWidth: 0.5
            )
            g += 5000
        }

        // "Now" marker — vertical red line at wall-clock now (off-screen when panned far).
        let nowX = CGFloat(nowMs - startMs) * pxPerMs
        if nowX >= 0, nowX <= size.width {
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: nowX, y: 0))
                    p.addLine(to: CGPoint(x: nowX, y: size.height))
                },
                with: .color(.red.opacity(0.55)),
                lineWidth: 1
            )
        }

        // Index lanes by callsign.
        var laneIndex: [String: Int] = [:]
        laneIndex.reserveCapacity(lanes.count)
        for (i, c) in lanes.enumerated() {
            laneIndex[c] = i
        }

        // Live bars for in-progress local keys. Drawn before completed events
        // so a finalized bar laid on top at key-up replaces the live one with
        // no visual seam.
        if !liveOwnKeyStarts.isEmpty, let lane = laneIndex[ownCallsign] {
            let y = CGFloat(lane) * rowFull
            let liveColor = color(for: ownCallsign)
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
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(liveColor)
                )
            }
        }

        // Events.
        for event in events {
            // Quick window cull.
            let eStart = event.startLocalMs
            let eEnd = event.endLocalMs
            if eEnd < startMs || eStart > endMs { continue }
            guard let lane = laneIndex[event.callsign] else { continue }
            let y = CGFloat(lane) * rowFull
            let baseColor = color(for: event.callsign)

            switch event.kind {
            case let .tone(dur, _):
                let xRaw = CGFloat(eStart - startMs) * pxPerMs
                let wRaw = max(2, CGFloat(dur) * pxPerMs)
                // Clip to visible canvas
                let x = max(0, xRaw)
                let w = max(2, min(size.width - x, xRaw + wRaw - x))
                guard w > 0 else { continue }
                let rect = CGRect(x: x, y: y + 3, width: w, height: rowHeight - 6)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(baseColor)
                )
                if event.origin == .received {
                    // Subtle hatching for received vs sent: thin border.
                    ctx.stroke(
                        Path(roundedRect: rect, cornerRadius: 2),
                        with: .color(.black.opacity(0.25)),
                        lineWidth: 0.5
                    )
                }

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
                ctx.stroke(p, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Lane ordering

    /// Lane composition:
    ///   1. Own callsign first (always, when set — even with zero activity, so
    ///      the operator always sees their own lane ready to fill).
    ///   2. Everyone with activity in the window, sorted by most recent.
    ///   3. Remaining roster members (connected but quiet), sorted alphabetically.
    ///
    /// The activity timeline doubles as the "who's on the channel" surface
    /// now that the Roster tab is gone, so every connected user gets a lane.
    private func laneOrder(
        events: [SignalEvent],
        ownCallsign: String,
        hasLiveOwn: Bool,
        roster: [String]
    ) -> [String] {
        var lastSeen: [String: Int64] = [:]
        for e in events {
            let t = e.endLocalMs
            if let prev = lastSeen[e.callsign], prev >= t { continue }
            lastSeen[e.callsign] = t
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
        for c in active where !seen.contains(c) {
            result.append(c)
            seen.insert(c)
        }

        let quiet = roster.filter { !seen.contains($0) }.sorted()
        result.append(contentsOf: quiet)

        return result
    }

    // MARK: - Color

    private func color(for callsign: String) -> Color {
        var hash: UInt64 = 5381
        for byte in callsign.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.86)
    }
}
