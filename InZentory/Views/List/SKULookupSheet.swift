//
//  SKULookupSheet.swift
//  InZentory
//

import SwiftUI

struct SKULookupSheet: View {
    let onSelect: (ReopenPayload) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isSearching = false
    @State private var results: [LookupResult] = []
    @State private var searchError: String? = nil
    @FocusState private var fieldFocused: Bool

    struct LookupResult: Identifiable {
        let id = UUID()
        let payload: ReopenPayload
        let source: ResultSource
        enum ResultSource { case draft, aob }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("SKU, barcode, or title", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { Task { await search() } }

                    Button("Search") {
                        Task { await search() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                .padding()

                Divider()

                if isSearching {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if let err = searchError {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else if results.isEmpty && !query.isEmpty {
                    Spacer()
                    Text("No results found")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(results) { result in
                        Button {
                            onSelect(result.payload)
                            dismiss()
                        } label: {
                            resultRow(result)
                        }
                        .foregroundStyle(.primary)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Find Listing")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    @ViewBuilder
    private func resultRow(_ result: LookupResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.payload.title.isEmpty ? "Untitled" : result.payload.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let sku = result.payload.sku {
                        Text(sku).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    switch result.source {
                    case .draft:
                        Label("Draft", systemImage: "tray")
                            .font(.caption2).foregroundStyle(.orange)
                    case .aob:
                        Label("AoB", systemImage: "checkmark.circle")
                            .font(.caption2).foregroundStyle(.green)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Search

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        searchError = nil
        results = []

        var found: [LookupResult] = []

        // Search InZentory drafts (client-side filter)
        if let allDrafts = try? await APIClient.shared.fetchDrafts() {
            let ql = q.lowercased()
            let matching = allDrafts.filter {
                ($0.sku?.lowercased().contains(ql) == true) ||
                ($0.title?.lowercased().contains(ql) == true) ||
                ($0.isbn?.contains(q) == true) ||
                ($0.asin?.lowercased().contains(ql) == true) ||
                ($0.upc?.contains(q) == true)
            }
            found += matching.map { draft in
                LookupResult(
                    payload: ReopenPayload(
                        inzentoryDraftId: draft.id,
                        sku:       draft.sku,
                        type:      .media,
                        asin:      draft.asin,
                        isbn:      draft.isbn,
                        upc:       draft.upc,
                        title:     draft.title ?? "",
                        author:    "",
                        publisher: "",
                        pubDate:   "",
                        itemMedia: "",
                        weight:    draft.weight.map { String($0) } ?? "",
                        qty:       draft.qty.map { String($0) } ?? "1",
                        price:     draft.price.map { String($0) } ?? "",
                        condition: draft.condition.flatMap { Int($0) }.flatMap { ItemCondition(rawValue: $0) },
                        source:    draft.source ?? "",
                        location:  draft.location ?? "",
                        notes:     draft.notes ?? "",
                        photoURLs: draft.photos?.map(\.url) ?? []
                    ),
                    source: .draft
                )
            }
        }

        // Search AoB by SKU exact match
        do {
            let items = try await AoBClient.shared.fetchItems(params: ["sku": q])
            found += items.map { item in
                LookupResult(
                    payload: ReopenPayload(
                        inzentoryDraftId: nil,
                        sku:       item.sku,
                        type:      .media,
                        asin:      item.asin,
                        isbn:      item.isbn,
                        upc:       item.upc,
                        title:     item.title,
                        author:    item.author ?? "",
                        publisher: item.publisher ?? "",
                        pubDate:   item.releaseDate ?? "",
                        itemMedia: item.media ?? "",
                        weight:    item.weight ?? "",
                        qty:       item.qty.map { String($0) } ?? "1",
                        price:     item.price ?? "",
                        condition: item.conditionRaw.flatMap { ItemCondition(rawValue: $0) },
                        source:    item.source ?? "",
                        location:  item.location ?? "",
                        notes:     item.notes ?? "",
                        photoURLs: item.imageURL.map { [$0] } ?? []
                    ),
                    source: .aob
                )
            }
        } catch AoBClient.AoBError.missingCredentials {
            // AoB creds not set — only show draft results; not an error
        } catch {
            if found.isEmpty {
                searchError = error.localizedDescription
            }
        }

        results = found
        isSearching = false
    }
}
