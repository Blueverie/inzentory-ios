//
//  TitleSearchSheet.swift
//  InZentory
//
//  AoB amz_keyword_search by title. Results are grouped by websiteDisplayGroup
//  with expand/collapse cards, defaulting to Book or to a media-type group
//  inferred from the keywords (audio, dvd, cd, etc.).
//
//  The sheet's results are owned by the parent (via @Binding) so the user
//  can dismiss after picking an ASIN, see the lookup result, then re-open
//  this sheet to try a different ASIN without re-running the search.
//

import SwiftUI

struct TitleSearchResults: Sendable, Equatable {
    let keywords: String
    let items: [AoBClient.AmzSearchItem]
}

extension AoBClient.AmzSearchItem: Equatable {
    static func == (lhs: AoBClient.AmzSearchItem, rhs: AoBClient.AmzSearchItem) -> Bool {
        lhs.asin == rhs.asin
    }
}

struct TitleSearchSheet: View {
    @Binding var cached: TitleSearchResults?
    let onPickASIN: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var keywords: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var expandedGroups: Set<String> = []
    @FocusState private var keywordsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                if isLoading {
                    ProgressView()
                        .padding()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                resultsList
            }
            .navigationTitle("Title Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let cached {
                    keywords = cached.keywords
                    if expandedGroups.isEmpty {
                        expandedGroups = defaultExpanded(items: cached.items, keywords: cached.keywords)
                    }
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        keywordsFocused = true
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Title keywords", text: $keywords)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($keywordsFocused)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }

            if !keywords.isEmpty {
                Button {
                    keywords = ""
                    keywordsFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Search") {
                keywordsFocused = false
                Task { await runSearch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(keywords.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if let cached, !cached.items.isEmpty {
            let groups = grouped(cached.items)
            List {
                ForEach(groups) { group in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group.id) },
                            set: { exp in
                                if exp { expandedGroups.insert(group.id) }
                                else   { expandedGroups.remove(group.id) }
                            }
                        )
                    ) {
                        ForEach(group.items) { item in
                            resultRow(item)
                        }
                    } label: {
                        HStack {
                            Text(group.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        } else if cached != nil && !isLoading {
            ContentUnavailableView("No results", systemImage: "magnifyingglass")
                .frame(maxHeight: .infinity)
        } else if cached == nil && !isLoading {
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Enter title keywords to search Amazon's catalog.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxHeight: .infinity)
        } else {
            Spacer()
        }
    }

    @ViewBuilder
    private func resultRow(_ item: AoBClient.AmzSearchItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(3)

            if let author = item.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(item.asin)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let brand = item.brand, !brand.isEmpty {
                    Text("• \(brand)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onPickASIN(item.asin)
                    dismiss()
                } label: {
                    Text("Use")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grouping

    private struct ResultGroup: Identifiable {
        let id: String
        let name: String
        let items: [AoBClient.AmzSearchItem]
    }

    private func grouped(_ items: [AoBClient.AmzSearchItem]) -> [ResultGroup] {
        var byKey: [String: (name: String, items: [AoBClient.AmzSearchItem])] = [:]
        var order: [String] = []
        for it in items {
            if byKey[it.websiteDisplayGroup] == nil {
                byKey[it.websiteDisplayGroup] = (it.websiteDisplayGroupName, [])
                order.append(it.websiteDisplayGroup)
            }
            byKey[it.websiteDisplayGroup]?.items.append(it)
        }
        return order.map { key in
            let entry = byKey[key]!
            return ResultGroup(id: key, name: entry.name, items: entry.items)
        }
    }

    private func defaultExpanded(items: [AoBClient.AmzSearchItem], keywords: String) -> Set<String> {
        let groups = grouped(items)
        guard !groups.isEmpty else { return [] }
        let lower = keywords.lowercased()

        // Keyword → group-name/id substring hints, ordered by specificity.
        let hints: [(triggers: [String], match: String)] = [
            (["audiobook", "audio cd", "audio"], "audio"),
            (["blu-ray", "bluray", "blu ray"],   "blu"),
            (["dvd"],                             "dvd"),
            (["vhs"],                             "vhs"),
            (["vinyl"],                           "vinyl"),
            (["video game", "videogame"],         "video_game"),
            (["cd"],                              "music"),
        ]

        for hint in hints {
            if hint.triggers.contains(where: { lower.contains($0) }),
               let g = groups.first(where: {
                   $0.name.lowercased().contains(hint.match) ||
                   $0.id.lowercased().contains(hint.match)
               }) {
                return [g.id]
            }
        }

        if let book = groups.first(where: {
            $0.name.lowercased().contains("book") || $0.id.lowercased().contains("book")
        }) {
            return [book.id]
        }

        return [groups[0].id]
    }

    // MARK: - Search

    private func runSearch() async {
        let trimmed = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        expandedGroups = []
        defer { isLoading = false }

        do {
            let items = try await AoBClient.shared.amzKeywordSearch(keywords: trimmed)
            let bundle = TitleSearchResults(keywords: trimmed, items: items)
            cached = bundle
            expandedGroups = defaultExpanded(items: items, keywords: trimmed)
        } catch {
            errorMessage = error.localizedDescription
            cached = TitleSearchResults(keywords: trimmed, items: [])
        }
    }
}

#Preview {
    @Previewable @State var cache: TitleSearchResults? = nil
    return TitleSearchSheet(cached: $cache) { asin in
        print("picked \(asin)")
    }
}
