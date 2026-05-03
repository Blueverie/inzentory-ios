//
//  ActivityView.swift
//  InZentory
//

import SwiftUI

struct ActivityView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(AppNavigator.self) private var navigator

    @State private var drafts: [InZentoryListing] = []
    @State private var recentListed: [AoBClient.AoBItem] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var recentError: String? = nil
    @State private var showPrinterPicker = false
    @State private var printingItemId: String? = nil
    @State private var printError: String? = nil
    @State private var showTemplateSheet = false
    @State private var pendingTemplateData: SurplusTemplateData? = nil
    @State private var draftPendingDelete: InZentoryListing? = nil
    @State private var isDeletingDraft = false

    var body: some View {
        List {
            printerChipRow

            Section {
                if isLoading && drafts.isEmpty {
                    loadingRow
                } else if drafts.isEmpty {
                    Text("No open drafts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(drafts) { (draft: InZentoryListing) in
                        draftRow(draft)
                    }
                }
            } header: {
                Text("Open Drafts")
            }

            Section {
                if isLoading && recentListed.isEmpty && recentError == nil {
                    loadingRow
                } else if let err = recentError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                        Button("Retry") { Task { await loadRecent() } }
                            .font(.callout)
                    }
                } else if recentListed.isEmpty {
                    Text("No recent listings")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentListed) { (item: AoBClient.AoBItem) in
                        listedRow(item)
                    }
                }
            } header: {
                Text("Recently Listed")
            }
        }
        .navigationTitle("Activity")
        .refreshable { await loadAll() }
        .task { await loadAll() }
        .alert("Load Error", isPresented: .init(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("Retry") { Task { await loadAll() } }
            Button("OK", role: .cancel) { loadError = nil }
        } message: { Text(loadError ?? "") }
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
        .sheet(isPresented: $showTemplateSheet) {
            if let data = pendingTemplateData {
                SurplusTemplateSheet(data: data)
            }
        }
    }

    // MARK: - Shared rows

    private var loadingRow: some View {
        HStack {
            ProgressView()
            Text("Loading…")
                .foregroundStyle(.secondary)
        }
    }

    private var printerChipRow: some View {
        Button { showPrinterPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "printer")
                if settings.selectedPrinterName.isEmpty {
                    Text("No printer selected — tap to configure")
                        .foregroundStyle(.secondary)
                } else {
                    Text(settings.selectedPrinterName)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(settings.selectedPrinterName.isEmpty ? .secondary : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Draft row

    @ViewBuilder
    private func draftRow(_ draft: InZentoryListing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.title ?? "Untitled")
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let sku = draft.sku {
                        Text(sku)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let dateStr = draft.updated_at ?? draft.created_at {
                        Text(isoDate(dateStr))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            reopenButton { reopen(draft) }

            Button(role: .destructive) {
                draftPendingDelete = draft
            } label: {
                if isDeletingDraft && draftPendingDelete?.id == draft.id {
                    ProgressView().scaleEffect(0.65).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Listed row

    @ViewBuilder
    private func listedRow(_ item: AoBClient.AoBItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .lineLimit(1)
                Text(item.sku)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.p9 == "surplus" {
                surplusTemplateButton(item)
            }
            printButton(sku: item.sku, title: item.title,
                        author: item.author ?? "", asin: item.asin ?? "", isbn: item.isbn ?? "", upc: item.upc ?? "",
                        conditionRaw: item.conditionRaw ?? 0,
                        itemId: "a-\(item.sku)")
            reopenButton { reopen(item) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func surplusTemplateButton(_ item: AoBClient.AoBItem) -> some View {
        Button {
            pendingTemplateData = SurplusTemplateData(
                title:         item.title,
                description:   "",
                condition:     item.conditionRaw.flatMap { ItemCondition(rawValue: $0) }?.displayName ?? "",
                ebayCondition: "",
                notes:         item.notes ?? "",
                rspPrice:      nil,
                msrp:          nil,
                price:         item.price.flatMap { Double($0) },
                cost:          nil,
                sku:           item.sku,
                brand:         item.publisher ?? "",
                ebayCatName:   "",
                weightOz:      item.weight.flatMap { Double($0) },
                lengthIn:      nil,
                widthIn:       nil,
                depthIn:       nil,
                shippingRate:  nil
            )
            showTemplateSheet = true
        } label: {
            Image(systemName: "doc.text")
        }
        .buttonStyle(.bordered)
        .tint(.hotPink)
        .controlSize(.small)
    }

    // MARK: - Shared action buttons

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
                ProgressView().scaleEffect(0.7).frame(width: 18, height: 18)
            } else {
                Image(systemName: "printer")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(settings.selectedPrinterId == 0 || printingItemId != nil)
    }

    private func reopenButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.left")
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .controlSize(.small)
    }

    // MARK: - Reopen actions

    private func reopen(_ draft: InZentoryListing) {
        // Prefer p9 if the backend returns it; fall back to the local UserDefaults cache.
        let itemType: ItemType
        if let p9 = draft.p9 {
            itemType = p9 == "surplus" ? .surplus : .media
        } else {
            itemType = settings.draftItemType(for: draft.id)
        }
        navigator.pendingReopenPayload = ReopenPayload(
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
            description: "", cost: "", rsPrice: "", msrp: "",
            packageLength: "", packageWidth: "", packageDepth: "", ebyCat: "",
            ebayItemSpecifics: draft.ebayItemSpecifics ?? [:]
        )
        navigator.selectedTab = .list
    }

    private func reopen(_ item: AoBClient.AoBItem) {
        let itemType: ItemType = item.p9 == "surplus" ? .surplus : .media
        navigator.pendingReopenPayload = ReopenPayload(
            inzentoryDraftId: nil,
            sku:       item.sku,
            type:      itemType,
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
            photoURLs: item.imageURL.map { [$0] } ?? [],
            description: "", cost: "", rsPrice: "", msrp: "",
            packageLength: "", packageWidth: "", packageDepth: "", ebyCat: ""
        )
        navigator.selectedTab = .list
    }

    // MARK: - Data loading

    private func loadAll() async {
        isLoading = true
        loadError = nil
        recentError = nil
        async let draftTask: () = loadDrafts()
        async let recentTask: () = loadRecent()
        _ = await (draftTask, recentTask)
        isLoading = false
    }

    private func loadDrafts() async {
        do {
            drafts = try await APIClient.shared.fetchDrafts()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadRecent() async {
        guard let username = auth.username, !username.isEmpty else {
            recentError = "Not signed in. Please log out and sign back in."
            return
        }
        do {
            recentListed = try await AoBClient.shared.fetchMyItems(inzentoryUsername: username)
        } catch {
            recentError = error.localizedDescription
        }
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
            printError = error.localizedDescription
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

    // MARK: - Helpers

    private func isoDate(_ str: String) -> String {
        String(str.prefix(10))
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
    .environment(AppSettings.shared)
    .environment(AuthService())
    .environment(AppNavigator())
}
