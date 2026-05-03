//
//  EbayCategoryPickerSheet.swift
//  InZentory
//

import SwiftUI

// MARK: - Sheet

struct EbayCategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EbayCategoryCache.self) private var cache

    /// Called when a leaf category is tapped. Receives (categoryId, categoryName).
    let onSelect: (String, String) -> Void

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if cache.isFetching && cache.categories.isEmpty {
                    ProgressView("Loading categories…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = cache.fetchError, cache.categories.isEmpty {
                    ContentUnavailableView {
                        Label("Load Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(err)
                    } actions: {
                        Button("Retry") { Task { await cache.refresh() } }
                    }
                } else if cache.categories.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "tray")
                } else if searchText.isEmpty {
                    treeList(cache.categories)
                } else {
                    flatSearchList
                }
            }
            .navigationTitle("eBay Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // cachedOrFetch() is a no-op if the cache is already populated and fresh.
        .task { await cache.cachedOrFetch() }
    }

    // MARK: - Tree (no search)

    private func treeList(_ roots: [EbayCategory]) -> some View {
        List(roots, children: \.optionalChildren) { cat in
            categoryRow(cat)
        }
        .listStyle(.plain)
    }

    // MARK: - Flat search results

    private var flatSearchList: some View {
        let term = searchText.lowercased()
        let results = flatLeaves(from: cache.categories, matching: term)
        return Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(results) { cat in
                    searchResultRow(cat)
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ cat: EbayCategory) -> some View {
        if cat.isLeaf {
            Button {
                onSelect(cat.id, cat.name)
                dismiss()
            } label: {
                HStack {
                    Text(cat.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.hotPink)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(cat.name) {
                CategorySubtreeView(root: cat, onSelect: { id, name in
                    onSelect(id, name)
                    dismiss()
                })
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ cat: EbayCategory) -> some View {
        if cat.isLeaf {
            Button {
                onSelect(cat.id, cat.name)
                dismiss()
            } label: {
                HStack {
                    Text(cat.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.hotPink)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(cat.name)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Recursively collect leaf nodes whose names contain the search term,
    /// or any node (leaf or branch) whose name matches so users can still navigate.
    private func flatLeaves(from cats: [EbayCategory], matching term: String) -> [EbayCategory] {
        var result: [EbayCategory] = []
        for cat in cats {
            let nameMatches = cat.name.lowercased().contains(term)
            if cat.isLeaf {
                if nameMatches { result.append(cat) }
            } else {
                let childMatches = flatLeaves(from: cat.children ?? [], matching: term)
                if nameMatches { result.append(cat) }
                result.append(contentsOf: childMatches)
            }
        }
        return result
    }

}

// MARK: - Subtree drilldown (used when tapping a non-leaf in search results)

private struct CategorySubtreeView: View {
    let root: EbayCategory
    let onSelect: (String, String) -> Void

    var body: some View {
        List(root.children ?? [], children: \.optionalChildren) { cat in
            if cat.isLeaf {
                Button {
                    onSelect(cat.id, cat.name)
                } label: {
                    HStack {
                        Text(cat.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.hotPink)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(cat.name)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle(root.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
