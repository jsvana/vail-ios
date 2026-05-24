// LogView.swift
// Renders the in-app log ring buffer (LogStore). Reached from Settings →
// Diagnostics. Most recent entry on top so flap-cycle order is obvious.

import SwiftUI

struct LogView: View {
    @ObservedObject private var store = LogStore.shared
    @State private var minimumLevel: LogEntry.Level = .info
    @State private var categoryFilter: String = ""

    var body: some View {
        List {
            ForEach(filtered) { entry in
                LogRow(entry: entry)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Minimum level", selection: $minimumLevel) {
                        ForEach(LogEntry.Level.allCases, id: \.self) { level in
                            Text(level.rawValue.capitalized).tag(level)
                        }
                    }
                    Button("Clear", role: .destructive) { store.clear() }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No log entries",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Connection-lifecycle events appear here as they happen.")
                )
            }
        }
    }

    private var filtered: [LogEntry] {
        let threshold = Self.rank(minimumLevel)
        return store.entries
            .filter { Self.rank($0.level) >= threshold }
            .reversed()
    }

    /// Higher rank = more severe.
    private static func rank(_ level: LogEntry.Level) -> Int {
        switch level {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .error: 4
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(entry.category)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 4)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                Text(entry.level.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color(for: entry.level))
                Spacer()
            }
            Text(entry.message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .debug: .secondary
        case .info: .blue
        case .notice: .teal
        case .warning: .orange
        case .error: .red
        }
    }
}
