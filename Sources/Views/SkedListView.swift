// SkedListView.swift
// Sked manager home: upcoming skeds + run history, with add/edit.

import SwiftUI

struct SkedListView: View {
    @EnvironmentObject var store: SkedStore

    private enum Segment: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case history = "History"
        var id: String {
            rawValue
        }
    }

    private enum Editor: Identifiable {
        case new
        case edit(Sked)
        var id: String {
            switch self {
            case .new: "new"
            case let .edit(sked): sked.id.uuidString
            }
        }
    }

    @State private var segment: Segment = .upcoming
    @State private var editor: Editor?

    var body: some View {
        Group {
            switch segment {
            case .upcoming: upcomingList
            case .history: SkedHistoryView()
            }
        }
        .navigationTitle("Skeds")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = .new
                } label: {
                    Label("Add sked", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                switch target {
                case .new: SkedEditView()
                case let .edit(sked): SkedEditView(sked: sked)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        if store.skeds.isEmpty {
            ContentUnavailableView(
                "No skeds",
                systemImage: "calendar.badge.plus",
                description: Text("Tap + to schedule a contact.")
            )
        } else {
            List {
                ForEach(store.skeds) { sked in
                    SkedRow(sked: sked, nextOccurrence: sked.nextOccurrence(after: Date()))
                        .contentShape(Rectangle())
                        .onTapGesture { editor = .edit(sked) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(sked)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.setEnabled(!sked.isEnabled, for: sked)
                            } label: {
                                sked.isEnabled
                                    ? Label("Disable", systemImage: "bell.slash")
                                    : Label("Enable", systemImage: "bell")
                            }
                            .tint(sked.isEnabled ? .orange : .green)
                        }
                }
            }
        }
    }
}

private struct SkedRow: View {
    let sked: Sked
    let nextOccurrence: Date?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sked.title)
                    .font(.headline)
                    .foregroundStyle(sked.isEnabled ? .primary : .secondary)
                HStack(spacing: 6) {
                    Label(sked.channel, systemImage: "dot.radiowaves.left.and.right")
                    Text("·")
                    Text(sked.recurrenceDescription())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if !sked.isEnabled {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(.secondary)
                } else if let next = nextOccurrence {
                    Text(SkedFormat.relative(next))
                        .font(.caption.weight(.medium))
                    Text(SkedFormat.clock(next))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Past")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shared date formatting for sked views.
enum SkedFormat {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: now)
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let fmt = DateComponentsFormatter()
        fmt.allowedUnits = [.hour, .minute]
        fmt.unitsStyle = .abbreviated
        return fmt.string(from: seconds) ?? "—"
    }
}
