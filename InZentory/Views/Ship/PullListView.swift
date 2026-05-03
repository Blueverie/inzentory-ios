//
//  PullListView.swift
//  InZentory
//

import SwiftUI
#if os(iOS)
import VisionKit
#endif

// MARK: - ViewModel

@Observable
final class PullListViewModel {
    enum ViewMode  { case list, scanner }
    enum SortMode  { case byOrder, byLocation }

    enum ScanFeedback: Equatable {
        case matched(label: String, orderComplete: Bool)
        case noMatch
    }

    let targetStatus   = "1"
    var mode: ViewMode  = .list
    var sortMode: SortMode = .byOrder
    var orders: [AoBClient.AoBOrder] = []
    var isLoading      = false
    var errorMessage: String?
    var scannerActive  = false
    var scanFeedback: ScanFeedback?

    /// Item IDs that have been marked as picked in the UI.
    var checkedItemIds: Set<String> = []

    /// All items across every order, sorted by location — used in .byLocation mode.
    var flatItems: [(item: AoBClient.AoBOrderItem, order: AoBClient.AoBOrder)] {
        orders
            .flatMap { order in order.items.map { (item: $0, order: order) } }
            .sorted { locationPrecedes($0.item.location ?? "", $1.item.location ?? "") }
    }

    // uppercased SKU → (orderId, itemId)
    private var skuIndex: [String: (orderId: String, itemId: String)] = [:]

    // MARK: Data

    func reload() async {
        isLoading      = true
        errorMessage   = nil
        checkedItemIds = []
        do {
            var fetched = try await AoBClient.shared.fetchOrders(sublist: "N")
            // Sort items within each order by location, then sort orders by
            // their first item's location so the list reads like a shelf walk.
            fetched = fetched.map { order in
                AoBClient.AoBOrder(
                    id:         order.id,
                    buyerName:  order.buyerName,
                    buyerEmail: order.buyerEmail,
                    orderDate:  order.orderDate,
                    aobStatus:  order.aobStatus,
                    items: order.items.sorted {
                        locationPrecedes($0.location ?? "", $1.location ?? "")
                    }
                )
            }
            fetched.sort {
                locationPrecedes(
                    $0.items.first?.location ?? "",
                    $1.items.first?.location ?? "")
            }
            orders = fetched
            rebuildIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: Pull (API call — fires when all items in an order are checked)

    func pull(orderId: String) async {
        do {
            try await AoBClient.shared.updateOrderStatus(orderId: orderId, aobStatus: targetStatus)
            if let order = orders.first(where: { $0.id == orderId }) {
                for item in order.items { checkedItemIds.remove(item.id) }
            }
            orders.removeAll { $0.id == orderId }
            rebuildIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Per-item check (shared by list UI and scanner)

    /// Marks an item as picked. Automatically fires the API when every item
    /// in the parent order has been checked.
    func checkItem(itemId: String, orderId: String) async {
        checkedItemIds.insert(itemId)
        guard let order = orders.first(where: { $0.id == orderId }) else { return }
        if order.items.allSatisfy({ checkedItemIds.contains($0.id) }) {
            await pull(orderId: orderId)
        }
    }

    // MARK: Scanner

    func handleScan(_ sku: String) async {
        scannerActive = false
        let key = sku.uppercased()
        if let (orderId, itemId) = skuIndex[key] {
            // Was this the last unchecked item in the order?
            let order = orders.first(where: { $0.id == orderId })
            let remainingBefore = order?.items.filter { !checkedItemIds.contains($0.id) }.count ?? 1
            let label = order?.items.first(where: { $0.id == itemId })?.title ?? sku
            await checkItem(itemId: itemId, orderId: orderId)
            scanFeedback = .matched(label: label, orderComplete: remainingBefore == 1)
            try? await Task.sleep(for: .seconds(2))
        } else {
            scanFeedback = .noMatch
            try? await Task.sleep(for: .seconds(1))
        }
        scanFeedback = nil
        scannerActive = true
    }

    // MARK: Private

    private func rebuildIndex() {
        var idx: [String: (orderId: String, itemId: String)] = [:]
        for order in orders {
            for item in order.items {
                if let sku = item.sku, !sku.isEmpty {
                    idx[sku.uppercased()] = (orderId: order.id, itemId: item.id)
                }
            }
        }
        skuIndex = idx
    }
}

// MARK: - Location sort helpers

/// Compares two shelf-location strings so that within the same row prefix the
/// order is: single-digit numerics (1–9) → alpha suffixes (A–Z) → multi-digit
/// numerics (10, 11, …).  Falls back to a standard string compare for anything
/// that doesn't match these patterns.
private func locationPrecedes(_ a: String, _ b: String) -> Bool {
    let (rowA, suffA) = locationParts(a)
    let (rowB, suffB) = locationParts(b)
    if rowA != rowB { return rowA < rowB }
    let ka = locationSuffixKey(suffA)
    let kb = locationSuffixKey(suffB)
    if ka.tier != kb.tier { return ka.tier < kb.tier }
    if ka.num != kb.num   { return ka.num  < kb.num  }
    return ka.str < kb.str
}

/// Splits "D9" → ("D", "9"),  "DA" → ("D", "A"),  "D10" → ("D", "10").
private func locationParts(_ loc: String) -> (row: String, suffix: String) {
    let row = String(loc.prefix(while: { $0.isLetter }))
    let suffix = String(loc.dropFirst(row.count))
    return (row, suffix)
}

private struct LocationKey { let tier: Int; let num: Int; let str: String }

/// tier 0 = single-digit numeric (1–9), tier 1 = alpha, tier 2 = multi-digit numeric (10+)
private func locationSuffixKey(_ suffix: String) -> LocationKey {
    if suffix.allSatisfy(\.isNumber), let n = Int(suffix) {
        return n < 10
            ? LocationKey(tier: 0, num: n, str: "")
            : LocationKey(tier: 2, num: n, str: "")
    }
    return LocationKey(tier: 1, num: 0, str: suffix)
}

// MARK: - PullListView

struct PullListView: View {
    @State private var vm = PullListViewModel()

    var body: some View {
        listContent
            .navigationTitle("Pull List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await vm.reload() }
            .refreshable { await vm.reload() }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .fullScreenCover(isPresented: Binding(
                get: { vm.mode == .scanner },
                set: { if !$0 { vm.mode = .list; vm.scannerActive = false } }
            )) {
                ScannerOverlayView(vm: vm)
            }
    }

    // MARK: List Content

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading && vm.orders.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.orders.isEmpty {
            ContentUnavailableView(
                "No New Orders",
                systemImage: "tray",
                description: Text("There are no new orders to pull.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if vm.sortMode == .byOrder {
                    ForEach(vm.orders) { order in
                        OrderRow(
                            order: order,
                            checkedItemIds: vm.checkedItemIds,
                            onCheckItem: { itemId in
                                Task { await vm.checkItem(itemId: itemId, orderId: order.id) }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparatorTint(Color(.separator))
                    }
                } else {
                    ForEach(vm.flatItems, id: \.item.id) { entry in
                        FlatItemRow(
                            item: entry.item,
                            order: entry.order,
                            isChecked: vm.checkedItemIds.contains(entry.item.id),
                            onAction: {
                                Task { await vm.checkItem(itemId: entry.item.id, orderId: entry.order.id) }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparatorTint(Color(.separator))
                    }
                }
            }
            .listStyle(.plain)
            .overlay(alignment: .top) {
                if vm.isLoading {
                    ProgressView().scaleEffect(0.7).padding(.top, 4)
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                vm.sortMode = vm.sortMode == .byOrder ? .byLocation : .byOrder
            } label: {
                Image(systemName: vm.sortMode == .byOrder
                      ? "list.bullet.indent"
                      : "location.fill.viewfinder")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                vm.scannerActive = true
                vm.mode = .scanner
            } label: {
                Label("Scan", systemImage: "barcode.viewfinder")
            }
        }
    }

}

// MARK: - Order Row

private struct OrderRow: View {
    let order: AoBClient.AoBOrder
    let checkedItemIds: Set<String>
    let onCheckItem: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(order.items) { item in
                ItemPickRow(
                    item: item,
                    isChecked: checkedItemIds.contains(item.id),
                    isMultiItem: order.items.count > 1,
                    onAction: { onCheckItem(item.id) }
                )
            }
        }
        // No internal dividers — the List row separator handles order boundaries
    }
}

// MARK: - Flat Item Row (by-location mode)

/// A single item row for the flat, location-sorted view.  Always shows a
/// checkbox (the auto-pull fires in the VM when every item in the order is
/// checked) and includes a buyer-name sub-label for order context.
private struct FlatItemRow: View {
    let item:      AoBClient.AoBOrderItem
    let order:     AoBClient.AoBOrder
    let isChecked: Bool
    let onAction:  () -> Void

    private let imgW: CGFloat = 100
    private let imgH: CGFloat = 130

    var body: some View {
        HStack(alignment: .top, spacing: 14) {

            AsyncImage(url: item.imageURL.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imgW, height: imgH)
                        .clipped()
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: imgW, height: imgH)
                        .overlay(
                            Image(systemName: "book.closed.fill")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .frame(width: imgW, height: imgH)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isChecked ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 6) {

                if let qty = item.qty, qty > 1 {
                    Text("×\(qty)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }

                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(isChecked, color: .secondary)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                }

                // Buyer name as order context
                if let buyer = order.buyerName, !buyer.isEmpty {
                    Text(buyer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let source = item.source, !source.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let media = item.media, !media.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(media)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    if let location = item.location, !location.isEmpty {
                        Text(location)
                            .font(.custom("Menlo", size: 20).bold())
                            .foregroundStyle(isChecked ? Color(.secondaryLabel) : Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isChecked
                                    ? Color(.systemGray4)
                                    : Color(hue: 0.08, saturation: 0.88, brightness: 0.80)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    Button {
                        guard !isChecked else { return }
                        onAction()
                    } label: {
                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isChecked ? .green : Color(.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .disabled(isChecked)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Item Pick Row

private struct ItemPickRow: View {
    let item: AoBClient.AoBOrderItem
    let isChecked: Bool
    let isMultiItem: Bool    // drives checkbox vs Pull button
    let onAction: () -> Void

    @State private var pulling = false

    private let imgW: CGFloat = 100
    private let imgH: CGFloat = 130

    var body: some View {
        HStack(alignment: .top, spacing: 14) {

            // ── Cover image ──────────────────────────────────────────────
            AsyncImage(url: item.imageURL.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imgW, height: imgH)
                        .clipped()
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: imgW, height: imgH)
                        .overlay(
                            Image(systemName: "book.closed.fill")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .frame(width: imgW, height: imgH)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isChecked ? 0.35 : 1)

            // ── Text column (fills remaining width) ──────────────────────
            VStack(alignment: .leading, spacing: 6) {

                // Qty badge — only when more than one copy is ordered
                if let qty = item.qty, qty > 1 {
                    Text("×\(qty)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }

                // Title
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(isChecked, color: .secondary)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                }

                // SKU · Source — same line
                HStack(spacing: 5) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let source = item.source, !source.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let media = item.media, !media.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(media)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                // Location badge + action — same line, pinned to bottom
                HStack(spacing: 10) {
                    if let location = item.location, !location.isEmpty {
                        Text(location)
                            .font(.custom("Menlo", size: 20).bold())
                            .foregroundStyle(isChecked ? Color(.secondaryLabel) : Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isChecked
                                    ? Color(.systemGray4)
                                    : Color(hue: 0.08, saturation: 0.88, brightness: 0.80)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    if isMultiItem {
                        // Per-item checkbox for multi-item orders
                        Button {
                            guard !isChecked else { return }
                            onAction()
                        } label: {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(isChecked ? .green : Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                        .disabled(isChecked)
                    } else {
                        // Single-item: direct Pull button
                        Button {
                            pulling = true
                            onAction()
                        } label: {
                            Group {
                                if pulling {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Text("Pull")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(pulling ? Color.gray : Color.accentColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(pulling)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Scanner Overlay

private struct ScannerOverlayView: View {
    let vm: PullListViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            if DataScannerViewController.isSupported {
                BarcodeScannerView(
                    isActive: Binding(
                        get: { vm.scannerActive },
                        set: { vm.scannerActive = $0 }
                    )
                ) { sku in
                    Task { await vm.handleScan(sku) }
                }
                .ignoresSafeArea()
            } else {
                ContentUnavailableView("Scanner Not Available", systemImage: "camera.slash")
                    .foregroundStyle(.white)
            }
            #endif
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { pullPanel }
        .overlay(alignment: .top) {
            if let fb = vm.scanFeedback {
                feedbackBanner(fb)
                    .padding(.top, 72)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.scanFeedback)
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanner Mode")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(vm.orders.count) order\(vm.orders.count == 1 ? "" : "s") pending")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button {
                vm.mode = .list
                vm.scannerActive = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.horizontal)
        .padding(.top, 56)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: Pull Panel

    private var pullPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.clipboard").foregroundStyle(.secondary)
                Text("Pull List").font(.headline)
                Spacer()
                Text("\(vm.orders.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(vm.orders.isEmpty ? Color.gray : Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            if vm.orders.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundStyle(.green)
                        Text("All orders pulled!").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.orders) { order in
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(order.items) { item in
                                    let checked = vm.checkedItemIds.contains(item.id)
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 16))
                                            .foregroundStyle(checked ? Color.green : Color(.systemGray3))
                                            .padding(.top, 1)

                                        // Thumbnail
                                        AsyncImage(url: item.imageURL.flatMap(URL.init)) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 36, height: 48)
                                                    .clipped()
                                            default:
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(.systemGray5))
                                                    .frame(width: 36, height: 48)
                                                    .overlay(
                                                        Image(systemName: "book.closed.fill")
                                                            .font(.caption2)
                                                            .foregroundStyle(.tertiary)
                                                    )
                                            }
                                        }
                                        .frame(width: 36, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .opacity(checked ? 0.35 : 1)

                                        VStack(alignment: .leading, spacing: 4) {
                                            // Qty badge — only when more than one copy
                                            if let qty = item.qty, qty > 1 {
                                                Text("×\(qty)")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(Color.orange)
                                                    .clipShape(Capsule())
                                            }

                                            // Title
                                            if let title = item.title, !title.isEmpty {
                                                Text(title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .strikethrough(checked, color: .secondary)
                                                    .foregroundStyle(checked ? .secondary : .primary)
                                            }

                                            // Location badge · SKU
                                            HStack(spacing: 6) {
                                                if let location = item.location, !location.isEmpty {
                                                    Text(location)
                                                        .font(.custom("Menlo", size: 16).bold())
                                                        .foregroundStyle(checked ? Color(.secondaryLabel) : Color.white)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 4)
                                                        .background(
                                                            checked
                                                                ? Color(.systemGray4)
                                                                : Color(hue: 0.08, saturation: 0.88, brightness: 0.80)
                                                        )
                                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                                }
                                                if let sku = item.sku, !sku.isEmpty {
                                                    Text(sku)
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(.secondary)
                                                        .strikethrough(checked)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    // MARK: Feedback Banner

    @ViewBuilder
    private func feedbackBanner(_ feedback: PullListViewModel.ScanFeedback) -> some View {
        switch feedback {
        case .matched(let label, let orderComplete):
            HStack(spacing: 12) {
                Image(systemName: orderComplete ? "shippingbox.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(orderComplete ? .blue : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(orderComplete ? "Order Pulled!" : "Item Checked")
                        .font(.subheadline.weight(.semibold))
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

        case .noMatch:
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                Text("Not in pull list").font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview {
    NavigationStack {
        PullListView()
    }
}
