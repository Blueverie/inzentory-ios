//
//  ListingDefaultsView.swift
//  InZentory
//

import SwiftUI

struct ListingDefaultsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(EbayCategoryCache.self) private var ebayCategoryCache

    @State private var minMarginText = ""
    @State private var showSaved = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $minMarginText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            } header: {
                Text("Min Margin")
            } footer: {
                Text("Items with margin below this amount will be flagged as REJECT or BORDERLINE.")
            }

            Section("Stories — Notes Phrases") {
                ForEach(settings.stockPhrases, id: \.self) { phrase in
                    Text(phrase)
                }
                .onDelete { offsets in settings.stockPhrases.remove(atOffsets: offsets) }
                .onMove  { from, to in settings.stockPhrases.move(fromOffsets: from, toOffset: to) }
                phraseAddRow(list: $settings.stockPhrases)
            }

            Section("Surplus — Notes Phrases") {
                ForEach(settings.surplusNotesPhrases, id: \.self) { phrase in
                    Text(phrase)
                }
                .onDelete { offsets in settings.surplusNotesPhrases.remove(atOffsets: offsets) }
                .onMove  { from, to in settings.surplusNotesPhrases.move(fromOffsets: from, toOffset: to) }
                phraseAddRow(list: $settings.surplusNotesPhrases)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if ebayCategoryCache.categories.isEmpty {
                            Text("Not cached yet")
                                .font(.subheadline)
                        } else {
                            Text("\(ebayCategoryCache.categories.count) top-level categories cached")
                                .font(.subheadline)
                        }
                        if let date = ebayCategoryCache.lastFetchedAt {
                            Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if ebayCategoryCache.isFetching {
                        ProgressView()
                    } else {
                        Button("Refresh") {
                            Task { await ebayCategoryCache.refresh() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                if let err = ebayCategoryCache.fetchError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Surplus — eBay Categories")
            } footer: {
                Text("Categories are refreshed automatically in the background and cached for 30 days.")
            }

            Section("Surplus — Description Phrases") {
                ForEach(settings.surplusDescriptionPhrases, id: \.self) { phrase in
                    Text(phrase)
                }
                .onDelete { offsets in settings.surplusDescriptionPhrases.remove(atOffsets: offsets) }
                .onMove  { from, to in settings.surplusDescriptionPhrases.move(fromOffsets: from, toOffset: to) }
                phraseAddRow(list: $settings.surplusDescriptionPhrases)
            }
        }
        .navigationTitle("Listing Defaults")
        .keyboardDoneButton()
        #if os(iOS)
        .toolbar {
            EditButton()
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear {
            if settings.minMargin > 0 {
                minMarginText = String(format: "%.2f", settings.minMargin)
            }
        }
        .overlay(alignment: .bottom) {
            if showSaved {
                Text("Saved")
                    .font(.callout.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.green.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showSaved)
    }

    /// Reusable inline add-phrase row for any phrase list.
    @ViewBuilder
    private func phraseAddRow(list: Binding<[String]>) -> some View {
        AddPhraseRow(list: list)
    }

    private func save() {
        settings.minMargin = Double(minMarginText) ?? 0
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSaved = false
        }
    }
}

// MARK: - AddPhraseRow helper

/// An inline HStack for adding a new phrase to any bound [String] list.
private struct AddPhraseRow: View {
    @Binding var list: [String]
    @State private var text = ""

    var body: some View {
        HStack {
            TextField("Add phrase…", text: $text)
            Button("Add") {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !list.contains(trimmed) else { return }
                list.append(trimmed)
                text = ""
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

#Preview {
    NavigationStack {
        ListingDefaultsView()
    }
    .environment(AppSettings.shared)
    .environment(EbayCategoryCache.shared)
}
