//
//  ListingDetailView.swift
//  InZentory
//
//  Created by Blueverie on 3/11/26.
//

import SwiftUI
import SwiftData

struct ListingDetailView: View {
    @Bindable var item: ListingItem
    @State private var isEditing = false

    var body: some View {
        Form {
            Section("Details") {
                if isEditing {
                    TextField("Title", text: $item.title)
                } else {
                    LabeledContent("Title", value: item.title.isEmpty ? "—" : item.title)
                }
                LabeledContent("Type", value: item.type.displayName)
                LabeledContent("Status") {
                    StatusBadge(status: item.status)
                }
            }

            if item.type == .media {
                Section("Barcode") {
                    if isEditing {
                        #if os(iOS)
                        TextField("Barcode", text: Binding(
                            get: { item.barcode ?? "" },
                            set: { item.barcode = $0.isEmpty ? nil : $0 }
                        ))
                        .keyboardType(.numberPad)
                        #else
                        TextField("Barcode", text: Binding(
                            get: { item.barcode ?? "" },
                            set: { item.barcode = $0.isEmpty ? nil : $0 }
                        ))
                        #endif
                    } else {
                        LabeledContent("Barcode", value: item.barcode ?? "—")
                    }
                }
            }

            Section("Notes") {
                if isEditing {
                    TextField("Notes", text: $item.notes, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    Text(item.notes.isEmpty ? "—" : item.notes)
                        .foregroundStyle(item.notes.isEmpty ? .secondary : .primary)
                }
            }

            Section("Timestamps") {
                LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Updated", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if item.status == .draft {
                Section {
                    Button("Submit Listing") {
                        // TODO: wire up real submission
                        item.status = .listed
                        item.updatedAt = Date()
                        isEditing = false
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(item.title.isEmpty ? "Untitled" : item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        #endif
        .toolbar {
            if item.status == .draft {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing { item.updatedAt = Date() }
                        isEditing.toggle()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing { item.updatedAt = Date() }
                        isEditing.toggle()
                    }
                }
                #endif
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer = try! ModelContainer(for: ListingItem.self, configurations: config)
    let item = ListingItem(type: .media, title: "Sample Book", notes: "Good condition")
    container.mainContext.insert(item)
    return NavigationStack {
        ListingDetailView(item: item)
    }
    .modelContainer(container)
}
