//
//  InventoryView.swift
//  InZentory
//

#if os(iOS)
import SwiftUI
import VisionKit

struct InventoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppNavigator.self) private var navigator

    @State private var sku       = ""
    @State private var isbn      = ""
    @State private var upc       = ""
    @State private var title     = ""
    @State private var author    = ""
    @State private var media     = ""
    @State private var publisher = ""
    @State private var qty       = ""
    @State private var source    = ""
    @State private var location  = ""
    @State private var price     = ""
    @State private var condition: ItemCondition? = nil

    @State private var results: [AoBClient.AoBItem] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var loadError: String? = nil

    @State private var showPrinterPicker = false
    @State private var printingItemId: String? = nil
    @State private var printError: String? = nil
    @State private var showTemplateSheet = false
    @State private var pendingTemplateData: SurplusTemplateData? = nil

    // Scanner
    private enum ScanField: Identifiable { case sku, isbn, upc; var id: Self { self } }
    @State private var activeScanField: ScanField? = nil
    @State private var isCameraScanning = false

    var body: some View {
        List {
            printerChipRow

            Section {
                scannableField("SKU", text: $sku, field: .sku)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                scannableField("ISBN", text: $isbn, field: .isbn)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                scannableField("UPC", text: $upc, field: .upc)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                TextField("Title",     text: $title)
                TextField("Author",    text: $author)
                TextField("Media",     text: $media).autocorrectionDisabled()
                TextField("Publisher", text: $publisher)
                TextField("Qty",       text: $qty).keyboardType(.numberPad)
                TextField("Source",    text: $source).autocorrectionDisabled()
                TextField("Location",  text: $location).autocorrectionDisabled()
                TextField("Price",     text: $price).keyboardType(.decimalPad)
                Picker("Condition", selection: $condition) {
                    Text("Any").tag(ItemCondition?.none)
                    ForEach(ItemCondition.allCases, id: \.self) { c in
                        Text(c.displayName).tag(Optional(c))
                    }
                }
            } header: {
                Text("Search")
            } footer: {
                HStack {
                    Button("Clear", role: .destructive) { clear() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                    Button {
                        Task { await search() }
                    } label: {
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading || !hasAnyQuery)
                }
                .padding(.top, 6)
            }

            Section {
                if isLoading && results.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Searching…").foregroundStyle(.secondary)
                    }
                } else if !hasSearched {
                    Text("Enter one or more fields, then Search.")
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("No items found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { item in
                        resultRow(item)
                    }
                }
            } header: {
                Text("Results\(results.isEmpty ? "" : " (\(results.count))")")
            }
        }
        .navigationTitle("Inventory")
        .keyboardDoneButton()
        .alert("Search Error", isPresented: .init(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: { Text(loadError ?? "") }
        .alert("Print Error", isPresented: .init(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) { printError = nil }
        } message: { Text(printError ?? "") }
        .sheet(isPresented: $showPrinterPicker) {
            NavigationStack { PrintNodeSettingsView() }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTemplateSheet) {
            if let data = pendingTemplateData {
                SurplusTemplateSheet(data: data)
            }
        }
        .sheet(item: $activeScanField) { field in
            scannerSheet(for: field)
        }
    }

    // MARK: - Scanner support

    // Conformance so ScanField can be used as sheet item
    private var hasAnyQuery: Bool {
        !sku.isEmpty || !isbn.isEmpty || !upc.isEmpty || !title.isEmpty
            || !author.isEmpty || !media.isEmpty || !publisher.isEmpty
            || !qty.isEmpty || !source.isEmpty || !location.isEmpty
            || !price.isEmpty || condition != nil
    }

    @ViewBuilder
    private func scannableField(_ label: String, text: Binding<String>, field: ScanField) -> some View {
        HStack {
            TextField(label, text: text)
            Button {
                activeScanField = field
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func scannerSheet(for field: ScanField) -> some View {
        ZStack {
            if DataScannerViewController.isSupported {
                BarcodeScannerView(isActive: $isCameraScanning) { barcode in
                    isCameraScanning = false
                    activeScanField = nil
                    switch field {
                    case .sku:  sku  = barcode
                    case .isbn: isbn = barcode
                    case .upc:  upc  = barcode
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        await search()
                    }
                }
                .ignoresSafeArea()
                .onAppear  { isCameraScanning = true  }
                .onDisappear { isCameraScanning = false }
            } else {
                ContentUnavailableView("Camera Unavailable",
                    systemImage: "camera.slash",
                    description: Text("This device doesn't support barcode scanning."))
            }
        }
    }

    // MARK: - Rows

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

    @ViewBuilder
    private func resultRow(_ item: AoBClient.AoBItem) -> some View {
        let isZeroQty = item.qty == 0
        VStack(alignment: .leading, spacing: 8) {
            // Image + title row
            HStack(alignment: .top, spacing: 10) {
                if let urlStr = item.imageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit()
                                .frame(width: 56, height: 72)
                                .cornerRadius(4)
                        default:
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemFill))
                                .frame(width: 56, height: 72)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(isZeroQty ? .red : .primary)
                    if let author = item.author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Metadata chips
            HStack(spacing: 6) {
                chip(item.sku, mono: true)
                if let cond = item.conditionRaw.flatMap({ ItemCondition(rawValue: $0) }) {
                    chip(cond.shortName)
                }
                if let q = item.qty {
                    chip("qty \(q)", color: isZeroQty ? .red : nil)
                }
                if let p = item.price, !p.isEmpty {
                    chip("$\(p)")
                }
                if let loc = item.location, !loc.isEmpty {
                    chip(loc)
                }
            }
            .lineLimit(1)

            // Action buttons
            HStack(spacing: 8) {
                Spacer()
                if item.p9 == "surplus" {
                    surplusTemplateButton(item)
                }
                printButton(item)
                reopenButton { reopen(item) }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func chip(_ text: String, mono: Bool = false, color: Color? = nil) -> some View {
        Text(text)
            .font(mono ? .caption.monospaced() : .caption)
            .foregroundStyle(color ?? Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((color ?? Color.secondary).opacity(0.12), in: Capsule())
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

    @ViewBuilder
    private func printButton(_ item: AoBClient.AoBItem) -> some View {
        let id = "i-\(item.sku)"
        Button {
            Task { await printLabel(item: item, itemId: id) }
        } label: {
            if printingItemId == id {
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

    // MARK: - Actions

    private func clear() {
        sku = ""; isbn = ""; upc = ""; title = ""; author = ""; media = ""
        publisher = ""; qty = ""; source = ""; location = ""; price = ""
        condition = nil
        results = []
        hasSearched = false
    }

    private func search() async {
        var params: [String: String] = [:]
        let fields: [(String, String)] = [
            ("sku", sku), ("upc", upc), ("title", title),
            ("author", author), ("media", media), ("publisher", publisher),
            ("qty", qty), ("source", source), ("location", location), ("price", price),
        ]
        for (k, v) in fields {
            let trimmed = v.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { params[k] = trimmed }
        }
        let isbnTrimmed = isbn.trimmingCharacters(in: .whitespaces)
        if !isbnTrimmed.isEmpty {
            params["isbn"] = isbn13ToIsbn10(isbnTrimmed) ?? isbnTrimmed
        }
        if let c = condition { params["condition"] = String(c.rawValue) }

        guard !params.isEmpty else { return }

        isLoading = true
        hasSearched = true
        defer { isLoading = false }
        do {
            results = try await AoBClient.shared.fetchItems(params: params)
        } catch {
            loadError = error.localizedDescription
            results = []
        }
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

    /// Converts a 13-digit ISBN-13 (978-prefix only) to its ISBN-10 equivalent.
    /// Returns nil if the input isn't a convertible ISBN-13.
    private func isbn13ToIsbn10(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 13, digits.hasPrefix("978") else { return nil }
        let nine = digits.dropFirst(3).prefix(9).map { $0.wholeNumberValue! }
        let sum = zip(nine, stride(from: 10, through: 2, by: -1)).reduce(0) { $0 + $1.0 * $1.1 }
        let check = (11 - (sum % 11)) % 11
        let checkChar = check == 10 ? "X" : String(check)
        return nine.map(String.init).joined() + checkChar
    }

    private func printLabel(item: AoBClient.AoBItem, itemId: String) async {
        guard settings.selectedPrinterId > 0 else { return }
        printingItemId = itemId
        defer { printingItemId = nil }
        do {
            try await PrintNodeClient.shared.printSKULabel(
                sku:          item.sku,
                title:        item.title,
                author:       item.author ?? "",
                asin:         item.asin ?? "",
                isbn:         item.isbn ?? "",
                upc:          item.upc ?? "",
                conditionRaw: item.conditionRaw ?? 0,
                printerId:    settings.selectedPrinterId,
                format:       settings.labelFormat,
                orientation:  settings.labelOrientation,
                zplDpi:       settings.zplDpi
            )
        } catch {
            printError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        InventoryView()
    }
    .environment(AppSettings.shared)
    .environment(AppNavigator())
}
#endif
