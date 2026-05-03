//
//  RecentListingsSection.swift
//  InZentory
//

import SwiftUI

struct RecentListingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthService.self) private var auth

    /// Called when the user taps re-open on any item.
    let onReopen: (ReopenPayload) -> Void

    @State private var drafts: [InZentoryListing] = []
    @State private var recentListed: [AoBClient.AoBItem] = []
    @State private var isLoadingDrafts = false
    @State private var isLoadingRecent = false
    @State private var draftsError: String? = nil
    @State private var recentError: String? = nil

    @State private var showPrinterPicker = false
    @State private var printingItemId: String? = nil
    @State private var printError: String? = nil
    @State private var draftsExpanded = true
    @State private var recentExpanded = true
    @State private var draftPendingDelete: InZentoryListing? = nil
    @State private var isDeletingDraft = false

    var body: some View {
        Group {
            if !drafts.isEmpty || !recentListed.isEmpty || isLoadingDrafts || isLoadingRecent
                || draftsError != nil || recentError != nil {
                content
            }
        }
        .task { await loadAll() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.vertical, 8)

            // Printer chip
            Button { showPrinterPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "printer")
                        .font(.caption)
                    if settings.selectedPrinterName.isEmpty {
                        Text("No printer selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                            Text(settings.selectedPrinterName)
                            .font(.caption)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            // Drafts (InZentory API)
            if isLoadingDrafts {
                HStack { ProgressView(); Text("Loading drafts…").font(.caption).foregroundStyle(.secondary) }
                    .padding(.bottom, 6)
            } else if let err = draftsError {
                Text("Drafts error: \(err)").font(.caption).foregroundStyle(.red).padding(.bottom, 6)
            } else if !drafts.isEmpty {
                DisclosureGroup(isExpanded: $draftsExpanded) {
                    ForEach(drafts) { draft in
                        draftRow(draft)
                            .padding(.leading, 4)
                    }
                } label: {
                    Label("Open Drafts (\(drafts.count))", systemImage: "tray")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.bottom, 6)
            }

            // Recent listed (AoB API)
            if isLoadingRecent {
                HStack { ProgressView(); Text("Loading recent…").font(.caption).foregroundStyle(.secondary) }
            } else if let err = recentError {
                Text("Recent listings error: \(err)").font(.caption).foregroundStyle(.red)
            } else if !recentListed.isEmpty {
                DisclosureGroup(isExpanded: $recentExpanded) {
                    ForEach(recentListed) { item in
                        listedRow(item)
                            .padding(.leading, 4)
                    }
                } label: {
                    Label("Recently Listed", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .alert("Print Error", isPresented: .init(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) { printError = nil }
        } message: { Text(printError ?? "") }
        .alert("Delete Draft?", isPresented: .init(
            get: { draftPendingDelete != nil },
            set: { if !$0 { draftPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let draft = draftPendingDelete {
                    Task { await deleteDraft(draft) }
                }
            }
            Button("Cancel", role: .cancel) { draftPendingDelete = nil }
        } message: {
            Text("\"\(draftPendingDelete?.title ?? "Untitled")\" will be permanently deleted.")
        }
        .sheet(isPresented: $showPrinterPicker) {
            NavigationStack { PrintNodeSettingsView() }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Row views

    @ViewBuilder
    private func draftRow(_ draft: InZentoryListing) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title ?? "Untitled")
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let sku = draft.sku {
                        Text(sku).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("·").font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = draft.created_at {
                        Text(date.prefix(10)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)

            if let sku = draft.sku {
                printButton(sku: sku, title: draft.title ?? "",
                            asin: draft.asin ?? "", isbn: draft.isbn ?? "", upc: draft.upc ?? "",
                            conditionRaw: Int(draft.condition ?? "") ?? 0,
                            itemId: "d-\(draft.id)")
            }

            Button { onReopen(payload(from: draft)) } label: {
                Image(systemName: "arrow.uturn.left").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.mini)

            Button(role: .destructive) {
                draftPendingDelete = draft
            } label: {
                if isDeletingDraft && draftPendingDelete?.id == draft.id {
                    ProgressView().scaleEffect(0.65).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "trash").font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func listedRow(_ item: AoBClient.AoBItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.sku).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)

            printButton(sku: item.sku, title: item.title,
                        author: item.author ?? "", asin: item.asin ?? "", isbn: item.isbn ?? "", upc: item.upc ?? "",
                        conditionRaw: item.conditionRaw ?? 0,
                        itemId: "a-\(item.sku)")

            Button { onReopen(payload(from: item)) } label: {
                Image(systemName: "arrow.uturn.left").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func printButton(
        sku: String, title: String,
        author: String = "", asin: String = "", isbn: String = "", upc: String = "",
        conditionRaw: Int = 0,
        itemId: String
    ) -> some View {
        Button {
            Task { await printLabel(sku: sku, title: title, author: author,
                                    asin: asin, isbn: isbn, upc: upc, conditionRaw: conditionRaw, itemId: itemId) }
        } label: {
            if printingItemId == itemId {
                ProgressView().scaleEffect(0.65).frame(width: 16, height: 16)
            } else {
                Image(systemName: "printer").font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(settings.selectedPrinterId == 0 || printingItemId != nil)
    }

    // MARK: - ReopenPayload builders

    private func payload(from draft: InZentoryListing) -> ReopenPayload {
        // Prefer p9 if the backend returns it; fall back to the local UserDefaults cache.
        let itemType: ItemType
        if let p9 = draft.p9 {
            itemType = p9 == "surplus" ? .surplus : .media
        } else {
            itemType = settings.draftItemType(for: draft.id)
        }
        return ReopenPayload(
            inzentoryDraftId: draft.id,
            sku:       draft.sku,
            type:      itemType,
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
            photoURLs: draft.photos?.map(\.url) ?? [],
            description:      draft.description ?? "",
            brand:            draft.brand ?? "",
            cost:             draft.cost.map { String($0) } ?? "",
            minPrice:         draft.minPrice.map { String($0) } ?? "",
            rsPrice:          draft.rspPrice.map { String($0) } ?? "",
            msrp:             draft.msrp.map { String($0) } ?? "",
            packageLength:    draft.packageLength.map { String($0) } ?? "",
            packageWidth:     draft.packageWidth.map { String($0) } ?? "",
            packageDepth:     draft.packageDepth.map { String($0) } ?? "",
            ebyCat:            draft.ebayCat ?? "",
            ebyCatName:        draft.ebayCatName ?? "",
            ebayConditionCode: draft.ebayConditionCode ?? "",
            ebayItemSpecifics: draft.ebayItemSpecifics ?? [:]
        )
    }

    private func payload(from item: AoBClient.AoBItem) -> ReopenPayload {
        ReopenPayload(
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
        )
    }

    // MARK: - Data loading

    private func loadAll() async {
        async let d: () = loadDrafts()
        async let r: () = loadRecent()
        _ = await (d, r)
    }

    private func loadDrafts() async {
        isLoadingDrafts = true
        draftsError = nil
        do {
            drafts = try await APIClient.shared.fetchDrafts()
        } catch {
            draftsError = error.localizedDescription
        }
        isLoadingDrafts = false
    }

    private func loadRecent() async {
        guard let username = auth.username, !username.isEmpty else {
            recentError = "Not logged in to InZentory."
            return
        }
        isLoadingRecent = true
        recentError = nil
        do {
            recentListed = try await AoBClient.shared.fetchMyItems(inzentoryUsername: username)
        } catch {
            recentError = error.localizedDescription
        }
        isLoadingRecent = false
    }

    // MARK: - Delete

    private func deleteDraft(_ draft: InZentoryListing) async {
        isDeletingDraft = true
        defer { isDeletingDraft = false; draftPendingDelete = nil }
        do {
            try await APIClient.shared.deleteListing(id: draft.id)
            drafts.removeAll { $0.id == draft.id }
            settings.clearDraftItemType(for: draft.id)
        } catch {
            printError = error.localizedDescription   // reuse the existing error alert
        }
    }

    // MARK: - Print

    private func printLabel(
        sku: String, title: String,
        author: String = "", asin: String = "", isbn: String = "", upc: String = "",
        conditionRaw: Int = 0,
        itemId: String
    ) async {
        guard settings.selectedPrinterId > 0 else { return }
        printingItemId = itemId
        defer { printingItemId = nil }
        do {
            try await PrintNodeClient.shared.printSKULabel(
                sku: sku, title: title, author: author,
                asin: asin, isbn: isbn, upc: upc, conditionRaw: conditionRaw,
                printerId: settings.selectedPrinterId,
                format: settings.labelFormat,
                orientation: settings.labelOrientation,
                zplDpi: settings.zplDpi
            )
        } catch {
            printError = error.localizedDescription
        }
    }
}
