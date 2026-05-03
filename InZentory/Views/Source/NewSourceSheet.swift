//
//  NewSourceSheet.swift
//  InZentory
//

import SwiftUI

struct NewSourceSheet: View {
    @Environment(SourcesService.self) private var sources
    @Environment(\.dismiss) private var dismiss

    let kind: SourceKind
    /// Called with the newly created record once saved (so the caller can navigate to it).
    var onCreated: ((SourceRecord) -> Void)? = nil

    @State private var name: String = ""
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("\(kind.displayName) Source")
                }

                if kind != .bulk {
                    Section {
                        Text("Detailed \(kind.displayName.lowercased()) tracking is coming soon. You can still create the source now and add details later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("New \(kind.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Open") {
                            Task { await open() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func open() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        do {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
            let created = try await sources.create(
                name: trimmed,
                kind: kind,
                date: date,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            onCreated?(created)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
