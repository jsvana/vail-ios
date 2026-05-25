// SkedEditView.swift
// Create or edit a sked.

import SwiftUI

struct SkedEditView: View {
    @EnvironmentObject var store: SkedStore
    @EnvironmentObject var contacts: ContactStore
    @Environment(\.dismiss) private var dismiss

    private enum RecurrenceKind: String, CaseIterable, Identifiable {
        case once = "Once"
        case daily = "Daily"
        case weekly = "Weekly"
        var id: String {
            rawValue
        }
    }

    private let editingID: UUID?

    @State private var title: String
    @State private var channel: String
    @State private var useCustomChannel: Bool
    @State private var customChannel: String
    @State private var startDate: Date
    @State private var recurrenceKind: RecurrenceKind
    @State private var weekdays: Set<Weekday>
    @State private var reminderLead: Int
    @State private var callsignsText: String
    @State private var notes: String

    private static let leadOptions = [0, 5, 10, 15, 30, 60]

    init(sked: Sked? = nil) {
        editingID = sked?.id
        let model = sked ?? Sked()
        _title = State(initialValue: model.title)

        let isStandard = ChannelPickerView.standardRooms.contains(model.channel)
        _useCustomChannel = State(initialValue: !isStandard)
        _channel = State(initialValue: isStandard ? model.channel : ChannelPickerView.standardRooms.first ?? "General")
        _customChannel = State(initialValue: isStandard ? "" : model.channel)

        _startDate = State(initialValue: model.startDate)
        _reminderLead = State(initialValue: model.reminderLeadMinutes)
        _callsignsText = State(initialValue: model.expectedCallsigns.joined(separator: ", "))
        _notes = State(initialValue: model.notes)

        switch model.recurrence {
        case .once:
            _recurrenceKind = State(initialValue: .once)
            _weekdays = State(initialValue: [])
        case .daily:
            _recurrenceKind = State(initialValue: .daily)
            _weekdays = State(initialValue: [])
        case let .weekly(days):
            _recurrenceKind = State(initialValue: .weekly)
            _weekdays = State(initialValue: days)
        }
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)
                    .autocorrectionDisabled()
            }

            Section("Channel") {
                Picker("Channel", selection: $channel) {
                    ForEach(ChannelPickerView.standardRooms, id: \.self) { Text($0).tag($0) }
                }
                .disabled(useCustomChannel)
                Toggle("Custom channel", isOn: $useCustomChannel)
                if useCustomChannel {
                    TextField("Room name", text: $customChannel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("Schedule") {
                Picker("Repeat", selection: $recurrenceKind) {
                    ForEach(RecurrenceKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if recurrenceKind == .once {
                    DatePicker("Date & time", selection: $startDate)
                } else {
                    DatePicker("Time", selection: $startDate, displayedComponents: .hourAndMinute)
                }

                if recurrenceKind == .weekly {
                    weekdayPicker
                }
            }

            Section("Reminder") {
                Picker("Remind me", selection: $reminderLead) {
                    ForEach(Self.leadOptions, id: \.self) { mins in
                        Text(mins == 0 ? "At start" : "\(mins) min before").tag(mins)
                    }
                }
            }

            Section("Expected callsigns") {
                TextField("W6JY, N9HO", text: $callsignsText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if !availableContacts.isEmpty {
                    Menu {
                        ForEach(availableContacts) { contact in
                            Button {
                                addCallsign(contact.callsign)
                            } label: {
                                Text(contact.name.isEmpty
                                    ? contact.callsign
                                    : "\(contact.name) (\(contact.callsign))")
                            }
                        }
                    } label: {
                        Label("Add from contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3 ... 6)
            }
        }
        .navigationTitle(editingID == nil ? "New Sked" : "Edit Sked")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(Weekday.allCases) { day in
                let selected = weekdays.contains(day)
                Button {
                    if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(day.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var resolvedChannel: String {
        return useCustomChannel
            ? customChannel.trimmingCharacters(in: .whitespacesAndNewlines)
            : channel
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !resolvedChannel.isEmpty else { return false }
        if recurrenceKind == .weekly && weekdays.isEmpty { return false }
        return true
    }

    private var currentCallsignTokens: [String] {
        callsignsText
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0).uppercased() }
    }

    /// Contacts not already listed in the callsigns field.
    private var availableContacts: [Contact] {
        let present = Set(currentCallsignTokens)
        return contacts.contacts.filter { !present.contains($0.callsign) }
    }

    private func addCallsign(_ callsign: String) {
        var tokens = currentCallsignTokens
        let upper = callsign.uppercased()
        guard !tokens.contains(upper) else { return }
        tokens.append(upper)
        callsignsText = tokens.joined(separator: ", ")
    }

    private func save() {
        let recurrence: Recurrence
        switch recurrenceKind {
        case .once: recurrence = .once
        case .daily: recurrence = .daily
        case .weekly: recurrence = .weekly(days: weekdays)
        }

        let callsigns = callsignsText
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0).uppercased() }

        let sked = Sked(
            id: editingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            channel: resolvedChannel,
            startDate: startDate,
            recurrence: recurrence,
            reminderLeadMinutes: reminderLead,
            expectedCallsigns: callsigns,
            notes: notes,
            isEnabled: true
        )
        store.upsert(sked)
        dismiss()
    }
}
