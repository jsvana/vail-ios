// SkedHistoryView.swift
// Past sked runs, most recent first.

import SwiftUI

struct SkedHistoryView: View {
    @EnvironmentObject var store: SkedStore

    var body: some View {
        if store.history.isEmpty {
            ContentUnavailableView(
                "No history",
                systemImage: "clock.arrow.circlepath",
                description: Text("Runs you join will appear here.")
            )
        } else {
            List {
                ForEach(store.history) { run in
                    RunRow(run: run)
                }
                .onDelete { store.deleteHistory(at: $0) }

                Section {
                    Button(role: .destructive) {
                        store.clearHistory()
                    } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct RunRow: View {
    let run: SkedRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: run.outcome == .completed ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(run.outcome == .completed ? .green : .secondary)
                Text(run.title)
                    .font(.headline)
                Spacer()
                Text(SkedFormat.clock(run.scheduledAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Label(run.channel, systemImage: "dot.radiowaves.left.and.right")
                if let d = run.duration {
                    Text("·")
                    Label(SkedFormat.duration(d), systemImage: "timer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !run.participants.isEmpty {
                Label(run.participants.joined(separator: ", "), systemImage: "person.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
