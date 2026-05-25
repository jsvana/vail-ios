// RosterView.swift
// Combined Contacts + Skeds tab. Both views shared a calendar/contacts
// theme and didn't justify two separate tabs, so they're now reachable via
// a top segmented picker. Each child view contributes its own toolbar
// items to the shared NavigationStack.

import SwiftUI

struct RosterView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case contacts = "Contacts"
        case skeds = "Skeds"
        var id: String {
            rawValue
        }
    }

    @State private var segment: Segment = .contacts

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            switch segment {
            case .contacts: ContactsView()
            case .skeds: SkedListView()
            }
        }
    }
}
