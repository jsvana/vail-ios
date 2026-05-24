// ContactEditView.swift
// Create or edit a contact.

import SwiftUI

struct ContactEditView: View {
    @EnvironmentObject var store: ContactStore
    @Environment(\.dismiss) private var dismiss

    private let editingID: UUID?
    private let dateAdded: Date
    private let lastWorked: Date?

    @State private var callsign: String
    @State private var name: String
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var preferredChannel: String
    @State private var preferredTxTone: Int?

    /// Edit an existing contact, or prefill a new one (e.g. from the roster).
    init(contact: Contact? = nil, prefillCallsign: String? = nil, prefillTxTone: Int? = nil) {
        editingID = contact?.id
        dateAdded = contact?.dateAdded ?? Date()
        lastWorked = contact?.lastWorked
        _callsign = State(initialValue: contact?.callsign ?? (prefillCallsign?.uppercased() ?? ""))
        _name = State(initialValue: contact?.name ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
        _isFavorite = State(initialValue: contact?.isFavorite ?? false)
        _preferredChannel = State(initialValue: contact?.preferredChannel ?? "")
        _preferredTxTone = State(initialValue: contact?.preferredTxTone ?? prefillTxTone)
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Callsign", text: $callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Name (optional)", text: $name)
                    .autocorrectionDisabled()
            }

            Section {
                Toggle("Favorite", isOn: $isFavorite)
            } footer: {
                Text("Favorites sort to the top and are highlighted in the roster.")
            }

            Section("Usual channel") {
                TextField("e.g. General (optional)", text: $preferredChannel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(editingID == nil ? "New Contact" : "Edit Contact")
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

    private var isValid: Bool {
        !callsign.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmedChannel = preferredChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = Contact(
            id: editingID ?? UUID(),
            callsign: callsign,
            name: name.trimmingCharacters(in: .whitespaces),
            notes: notes,
            isFavorite: isFavorite,
            preferredChannel: trimmedChannel.isEmpty ? nil : trimmedChannel,
            preferredTxTone: preferredTxTone,
            dateAdded: dateAdded,
            lastWorked: lastWorked
        )
        store.upsert(contact)
        dismiss()
    }
}
