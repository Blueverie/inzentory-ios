//
//  ListFormView.swift
//  InZentory
//

import SwiftUI
import SwiftData
import PhotosUI
import Combine

struct ListFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppNavigator.self) private var navigator
    @Environment(AppSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(EbayCategoryCache.self) private var ebayCategoryCache

    // ── Scan context ────────────────────────────────────────────────────
    @State private var productImageURL: String? = nil
    @State private var catData: AoBClient.CatData? = nil

    // ── Form fields ──────────────────────────────────────────────────────
    @State private var itemType: ItemType = .media
    @State private var sku = ""
    @State private var asin = ""
    @State private var isbn = ""
    @State private var upc = ""
    @State private var condition: ItemCondition? = nil
    @State private var isExLibrary = false
    @State private var title = ""
    @State private var author = ""
    @State private var publisher = ""
    @State private var pubDate = ""
    @State private var itemMedia = ""
    @State private var weight = ""          // total oz — source of truth sent to AoB
    @State private var weightLbs = ""       // display field: whole pounds
    @State private var weightOzPart = ""    // display field: remaining oz
    @State private var isNormalizingWeight = false
    @State private var qty = "1"
    @State private var price = ""
    @State private var source = ""
    @State private var location = ""
    @State private var notes = ""
    // ── Surplus-only fields ───────────────────────────────────────────────
    @State private var itemDescription = ""
    @State private var cost = ""
    @State private var minPrice = ""
    @State private var rsPrice = ""
    @State private var msrp = ""
    @State private var packageLength = ""
    @State private var packageWidth = ""
    @State private var packageDepth = ""
    @State private var ebyCat = ""
    @State private var ebyCatName = ""
    // ── eBay specifics (loaded on demand after category selection) ────────
    @State private var ebyConditionCodes: [EbayConditionCode] = []
    @State private var ebyConditionCode = ""
    @State private var ebyItemSpecifics: [EbayItemSpecific] = []
    @State private var ebySpecificValues: [String: String] = [:]
    @State private var isLoadingSpecifics = false
    @State private var specificsError: String? = nil
    // ── eBay Business Policies (loaded once for surplus form) ─────────────
    @State private var businessPolicies: AoBClient.BusinessPolicies? = nil
    @State private var ebyShippingPolicy = ""
    @State private var ebyReturnPolicy = ""
    // ── Shipping rate calculator ──────────────────────────────────────────
    @State private var shippingRateZip:  EasyPostClient.Rate? = nil
    @State private var shippingRateFull: EasyPostClient.Rate? = nil
    @State private var isCalculatingShipping = false
    @State private var shippingRateError: String? = nil

    // ── Photos ───────────────────────────────────────────────────────────
    @State private var photoURLs: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var capturedCameraImage: UIImage?
    @State private var showPhotoSourceDialog = false
    @State private var dropTargetIndex: Int? = nil

    // ── Draft / reopen state ──────────────────────────────────────────────
    @State private var inzentoryDraftId: Int? = nil  // non-nil while editing an InZentory draft
    @State private var isReopened = false             // true when editing any re-opened item
    @State private var isSavingDraft = false
    @State private var showPrinterPicker = false
    @State private var printError: String? = nil
    @State private var isPrinting = false
    // ── Surplus template sheet ────────────────────────────────────────────
    @State private var showTemplateSheet = false
    @State private var pendingTemplateData: SurplusTemplateData? = nil

    // ── Crop review ──────────────────────────────────────────────────────
    @StateObject private var cropCoordinator = CropReviewCoordinator()

    // ── UI state ─────────────────────────────────────────────────────────
    @State private var enlargedImageURL: String? = nil
    @State private var showStockPhrases = false
    @State private var showSurplusNotesPhrases = false
    @State private var showSurplusDescPhrases = false
    @State private var showEbyCategoryPicker = false
    @State private var skuGenerating = false
    @State private var isSubmitting = false
    @State private var submitError: String? = nil
    @State private var showSubmitSuccess = false
    @State private var submittedTitle = ""
    @State private var showScanner = false
    @State private var scannerDeliveredResult = false
    @State private var lookupText = ""
    @State private var isLookupLoading = false
    @State private var scanLookupError: String? = nil
    @State private var showLookup = false
    @State private var showTitleSearch = false
    @State private var titleSearchCache: TitleSearchResults? = nil
    @State private var recentRefreshID = UUID()
    @State private var lastListedProductId = ""
    @State private var showDuplicateProductAlert = false

    // Cached once at view construction — UIImagePickerController.isSourceTypeAvailable
    // can be slow to call repeatedly inside a button label.
    #if os(iOS)
    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    #endif

    enum Field { case asin, isbn, upc, price, source, location, title, author, publisher, pubDate, media, weight, weightOz, qty, notes, desc, cost, rsPrice, msrp, packageLength, packageWidth, packageDepth, ebyCat }
    @FocusState private var focusedField: Field?
    @FocusState private var lookupFocused: Bool

    private enum LookupPartial: Sendable {
        case product(AoBClient.ProductData?)
        case cat(AoBClient.CatData?)
    }

    private var isEditMode: Bool { isReopened }

    private var accentColor: Color {
        itemType == .media ? .orange : .hotPink
    }

    private var canList: Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        let l = location.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !l.isEmpty, condition != nil else { return false }
        if itemType == .media {
            return !price.trimmingCharacters(in: .whitespaces).isEmpty ||
                   !asin.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true  // surplus: title + location + condition is sufficient
    }


    var body: some View { withLifecycle }

    private var withLifecycle: some View {
        withSheets
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await uploadPickedPhotos(items) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { saveFormSnapshot() }
            }
            .onAppear {
                loadPending()
                if !isReopened { restoreFormSnapshotIfNeeded() }
                if businessPolicies == nil {
                    Task { businessPolicies = try? await AoBClient.shared.fetchBusinessPolicies() }
                }
                // Warm the category cache so the picker opens instantly.
                // No-op if cache is already fresh (< 30 days old).
                Task { await ebayCategoryCache.cachedOrFetch() }
                guard !isReopened, itemType == .media else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    lookupFocused = true
                }
            }
            .onChange(of: navigator.selectedTab) { _, tab in
                guard tab == .list, !isReopened, itemType == .media else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    lookupFocused = true
                }
            }
            .onChange(of: navigator.pendingVersion) { _, _ in
                clearForm()
                itemType = .media   // scans always route to Stories
                loadPending()
                Task { await generateSku() }
            }
            .onChange(of: navigator.pendingReopenPayload) { _, payload in
                guard let payload else { return }
                reopenItem(payload)
                navigator.pendingReopenPayload = nil
            }
    }

    private var withSheets: some View {
        scrollContent
            .sheet(isPresented: $showScanner, onDismiss: {
                if !scannerDeliveredResult {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        lookupFocused = true
                    }
                }
                scannerDeliveredResult = false
            }) {
                ScanView { result in
                    scannerDeliveredResult = true
                    titleSearchCache = nil
                    clearForm()
                    applyResult(result)
                    Task { await generateSku() }
                }
            }
            .sheet(isPresented: $showStockPhrases) {
                StockPhrasesSheet(phrases: settings.stockPhrases) { phrase in
                    notes += (notes.isEmpty ? "" : "; ") + phrase
                    showStockPhrases = false
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSurplusNotesPhrases) {
                StockPhrasesSheet(phrases: settings.surplusNotesPhrases) { phrase in
                    notes += (notes.isEmpty ? "" : "; ") + phrase
                    showSurplusNotesPhrases = false
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSurplusDescPhrases) {
                StockPhrasesSheet(phrases: settings.surplusDescriptionPhrases) { phrase in
                    itemDescription += (itemDescription.isEmpty ? "" : "; ") + phrase
                    showSurplusDescPhrases = false
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showEbyCategoryPicker) {
                EbayCategoryPickerSheet { id, name in
                    ebyCat = id
                    ebyCatName = name
                    // Reset previous specifics when category changes
                    ebyConditionCodes = []
                    ebyConditionCode = ""
                    ebyItemSpecifics = []
                    ebySpecificValues = [:]
                }
            }
            .sheet(isPresented: $showPrinterPicker) {
                NavigationStack { PrintNodeSettingsView() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showLookup) {
                SKULookupSheet { payload in
                    reopenItem(payload)
                }
            }
            .sheet(isPresented: $showTitleSearch) {
                TitleSearchSheet(cached: $titleSearchCache) { asin in
                    lookupText = asin
                    Task { await performLookup(asin) }
                }
            }
            .sheet(isPresented: .init(
                get: { enlargedImageURL != nil },
                set: { if !$0 { enlargedImageURL = nil } }
            )) {
                if let urlStr = enlargedImageURL, let url = URL(string: urlStr) {
                    ImageFullScreenView(url: url)
                }
            }
            .sheet(item: .init(
                get: { cropCoordinator.pending },
                set: { if $0 == nil { cropCoordinator.resolveWithOriginal() } }
            )) { pending in
                CropPreviewSheet(pending: pending) { chosen in
                    cropCoordinator.resolve(chosen)
                }
            }
            .sheet(isPresented: $showTemplateSheet) {
                if let data = pendingTemplateData {
                    SurplusTemplateSheet(data: data)
                }
            }
            .photosPicker(
                isPresented: $showPhotoLibrary,
                selection: $pickerItems,
                maxSelectionCount: max(1, 12 - photoURLs.count),
                matching: .images
            )
    }

    private var scrollContent: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if itemType == .media {
                        if let cat = catData { VerdictBanner(cat: cat).padding(.horizontal) }
                    }
                    photoStrip
                    formFields.padding(.horizontal)
                    RecentListingsSection(onReopen: reopenItem)
                        .padding(.horizontal)
                        .id(recentRefreshID)
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) {
                if itemType == .media {
                    lookupBar
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(.bar)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
            }

            // Floating banner — always visible regardless of scroll position
            successBanner
                .padding(.top, 8)
                .zIndex(1)
        }
        .navigationTitle(isEditMode ? "Edit Listing" : itemType.displayName)
        .tint(accentColor)
        .onChange(of: source)   { _, v in settings.setSource(v, for: itemType) }
        .onChange(of: location) { _, v in settings.setLocation(v, for: itemType) }
        .onChange(of: weightLbs) { _, newVal in
            guard !isNormalizingWeight else { return }
            // Decimal entered in lb field → split fractional part into oz
            if newVal.contains("."), !newVal.hasSuffix("."),
               let val = Double(newVal), val >= 0 {
                let lbs = Int(val)
                let oz  = Int(((val - Double(lbs)) * 16).rounded())
                isNormalizingWeight = true
                weightLbs    = lbs > 0 ? String(lbs) : ""
                weightOzPart = oz  > 0 ? String(oz)  : ""
                isNormalizingWeight = false
            }
            updateWeightFromParts()
        }
        .onChange(of: weightOzPart) { _, newVal in
            guard !isNormalizingWeight else { return }
            // oz > 15 → carry over into lbs
            if let val = Int(newVal), val > 15 {
                let newLbs = (Int(weightLbs) ?? 0) + val / 16
                let newOz  = val % 16
                isNormalizingWeight = true
                weightLbs    = newLbs > 0 ? String(newLbs) : ""
                weightOzPart = newOz  > 0 ? String(newOz)  : ""
                isNormalizingWeight = false
            }
            updateWeightFromParts()
        }
        #if os(iOS)
        .sheet(isPresented: $showCamera, onDismiss: {
            Task { await processPendingCameraCapture() }
        }) {
            CameraPickerView { image in
                capturedCameraImage = image
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil; lookupFocused = false; UIApplication.dismissKeyboard() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    switchFormType()
                } label: {
                    Text(itemType == .media ? "Switch to Surplus" : "Switch to Stories")
                        .font(.subheadline)
                }
            }
        }
        #endif
    }

    private var lookupBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLookupLoading)

                Button {
                    showTitleSearch = true
                } label: {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(isLookupLoading)

                TextField("Barcode / ISBN / ASIN", text: $lookupText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($lookupFocused)
                    .onSubmit {
                        guard !lookupText.isEmpty else { return }
                        titleSearchCache = nil
                        Task { await performLookup(lookupText) }
                    }

                if isLookupLoading {
                    ProgressView()
                        .frame(width: 44)
                } else if !lookupText.isEmpty {
                    Button("Go") {
                        titleSearchCache = nil
                        Task { await performLookup(lookupText) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let error = scanLookupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var successBanner: some View {
        if showSubmitSuccess {
            let verb = isEditMode ? "updated" : "listed"
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("\"\(submittedTitle)\" \(verb)!").fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(.white)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.green, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            if itemType == .surplus {
                // Save Draft + Print SKU Label row
                HStack(spacing: 12) {
                    Button {
                        Task { await saveDraft() }
                    } label: {
                        Group {
                            if isSavingDraft {
                                ProgressView()
                            } else {
                                Label("Save Draft", systemImage: "tray.and.arrow.down")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingDraft)

                    Button {
                        Task { await printSkuLabel() }
                    } label: {
                        Group {
                            if isPrinting {
                                ProgressView()
                            } else {
                                Label("Print Label", systemImage: "printer.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPrinting || sku.isEmpty || settings.selectedPrinterId == 0)
                }
            }

            // Printer chip + List + Clear in one row
            HStack(spacing: 10) {
                // Compact printer chip
                Button { showPrinterPicker = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "printer")
                            .font(.callout)
                        Text(settings.selectedPrinterName.isEmpty ? "No printer" : settings.selectedPrinterName)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(settings.selectedPrinterName.isEmpty ? .secondary : .primary)
                }
                .buttonStyle(.plain)

                Button(action: clearForm) {
                    Label("Clear", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isSubmitting)

                Button {
                    let productId = asin.trimmingCharacters(in: .whitespaces).isEmpty
                        ? upc.trimmingCharacters(in: .whitespaces)
                        : asin.trimmingCharacters(in: .whitespaces)
                    if itemType == .media && !productId.isEmpty && productId == lastListedProductId {
                        showDuplicateProductAlert = true
                    } else {
                        Task { await submitListing() }
                    }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Label(isEditMode ? "Update" : "List",
                                  systemImage: isEditMode ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSubmitting || !canList)
            }
        }
        .alert("Duplicate Product ID", isPresented: $showDuplicateProductAlert) {
            Button("List Anyway") { Task { await submitListing() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This product ID (\(asin.isEmpty ? upc : asin)) was just listed. Are you sure you want to list it again?")
        }
        .alert("Listing Failed", isPresented: .init(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("OK", role: .cancel) { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
        .alert("Print Error", isPresented: .init(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) { printError = nil }
        } message: {
            Text(printError ?? "")
        }
    }

    // MARK: - Form fields

    @ViewBuilder
    private var formFields: some View {
        if itemType == .media {
            storiesFields
        } else {
            surplusFields
        }
    }

    // MARK: Stories fields

    @ViewBuilder
    private var storiesFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            skuRow

            // ASIN / ISBN / UPC row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("ASIN")
                    TextField("10 chars", text: $asin)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .asin)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("ISBN")
                    TextField("978…", text: $isbn)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .isbn)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("UPC")
                    TextField("", text: $upc)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .upc)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }

            // Condition
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fieldLabel("Condition")
                    Spacer()
                    Toggle(isOn: $isExLibrary) {
                        Text("Ex-Library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.button)
                    .controlSize(.mini)
                    .tint(.orange)
                    .onChange(of: isExLibrary) { _, exLib in
                        if exLib {
                            if condition != .good && condition != .acceptable {
                                condition = nil
                            } else {
                                notes = exLibraryNote(for: condition)
                            }
                        }
                    }
                }
                ConditionPicker(
                    selection: $condition,
                    cases: ItemCondition.storiesCases,
                    tint: .orange,
                    disabledCases: isExLibrary
                        ? Set(ItemCondition.storiesCases.filter { $0 != .good && $0 != .acceptable })
                        : []
                )
                .onChange(of: condition) { _, newCond in
                    if isExLibrary {
                        notes = exLibraryNote(for: newCond)
                    }
                }
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fieldLabel("Title")
                    Spacer()
                    Text("\(title.count)/80")
                        .font(.caption)
                        .foregroundStyle(title.count > 72 ? (title.count >= 80 ? .red : .orange) : .secondary)
                        .monospacedDigit()
                }
                TextField("Item title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                    .onChange(of: title) { _, new in
                        if new.count > 80 { title = String(new.prefix(80)) }
                    }
            }

            // Author / Publisher row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Author")
                    TextField("Author", text: $author)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .author)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Publisher")
                    TextField("Publisher", text: $publisher)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .publisher)
                }
            }

            // Pub Date / Media / Weight row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Pub Date")
                    TextField("YYYY-MM-DD", text: $pubDate)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .pubDate)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Media")
                    TextField("e.g. Hardcover", text: $itemMedia)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .media)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Weight")
                    HStack(spacing: 4) {
                        TextField("lb", text: $weightLbs)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .focused($focusedField, equals: .weight)
                        Text("lb").font(.caption2).foregroundStyle(.secondary)
                        TextField("oz", text: $weightOzPart)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .focused($focusedField, equals: .weightOz)
                        Text("oz").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // Qty / Source / Location row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Qty")
                    TextField("1", text: $qty)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($focusedField, equals: .qty)
                        .frame(maxWidth: 60)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Source")
                    SourcePickerField(source: $source, placeholder: "Source")
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Location")
                    TextField("Location", text: $location)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .location)
                }
            }

            // Price
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Price")
                TextField("0.00", text: $price)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .focused($focusedField, equals: .price)
                    .frame(maxWidth: 120)
            }

            notesRow
        }
    }

    // MARK: Surplus fields

    @ViewBuilder
    private var surplusFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            skuRow

            // Title
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fieldLabel("Title")
                    Spacer()
                    Text("\(title.count)/80")
                        .font(.caption)
                        .foregroundStyle(title.count > 72 ? (title.count >= 80 ? .red : .orange) : .secondary)
                        .monospacedDigit()
                }
                TextField("Item title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                    .onChange(of: title) { _, new in
                        if new.count > 80 { title = String(new.prefix(80)) }
                    }
            }

            // Description with its own phrase picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fieldLabel("Description")
                    Spacer()
                    Button { showSurplusDescPhrases = true } label: {
                        Label("Phrases", systemImage: "text.badge.plus")
                            .font(.caption)
                    }
                }
                TextField("Item description", text: $itemDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
                    .focused($focusedField, equals: .desc)
            }

            // Brand / Manufacturer
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Brand / Manufacturer")
                TextField("Brand", text: $publisher)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .publisher)
            }

            // UPC
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("UPC")
                TextField("", text: $upc)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($focusedField, equals: .upc)
            }

            // Condition
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Condition")
                ConditionPicker(selection: $condition, cases: ItemCondition.surplusCases, tint: .hotPink)
            }

            // Surplus-specific notes (separate phrase list from Stories)
            surplusNotesRow

            // ── eBay Category ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    fieldLabel("eBay Category")
                    Spacer()
                    Button { showEbyCategoryPicker = true } label: {
                        Label("Browse", systemImage: "list.triangle")
                            .font(.caption)
                    }
                    if !ebyCat.isEmpty {
                        Button {
                            Task { await loadEbySpecifics() }
                        } label: {
                            if isLoadingSpecifics {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Label("Load Specifics", systemImage: "arrow.down.circle")
                                    .font(.caption)
                            }
                        }
                        .disabled(isLoadingSpecifics)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Category ID", text: $ebyCat)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($focusedField, equals: .ebyCat)
                        .frame(maxWidth: 120)
                    if !ebyCatName.isEmpty {
                        Text(ebyCatName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let err = specificsError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            // ── eBay Condition (from category specifics) ──────────────────
            if !ebyConditionCodes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("eBay Condition")
                    Picker("eBay Condition", selection: $ebyConditionCode) {
                        Text("Select…").tag("")
                        ForEach(ebyConditionCodes) { code in
                            Text(code.name).tag(code.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.hotPink)
                }
            }

            // ── Item Specifics (dynamic, loaded per-category) ─────────────
            ForEach(ebyItemSpecifics) { spec in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 2) {
                        fieldLabel(spec.name)
                        if spec.isRequired {
                            Text("*").font(.caption).bold().foregroundStyle(.red)
                        }
                    }
                    if spec.isFreeText {
                        TextField(spec.name, text: ebySpecificBinding(spec.name))
                            .textFieldStyle(.roundedBorder)
                        if let suggestions = spec.values, !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(suggestions, id: \.self) { val in
                                        Button(val) {
                                            ebySpecificValues[spec.name] = val
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(ebySpecificValues[spec.name] == val ? .hotPink : .secondary)
                                        .font(.caption)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } else {
                        Picker(spec.name, selection: ebySpecificBinding(spec.name)) {
                            Text("Select…").tag("")
                            ForEach(spec.values ?? [], id: \.self) { val in
                                Text(val).tag(val)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.hotPink)
                    }
                }
            }

            // ── Pricing ───────────────────────────────────────────────────
            // Price / Cost row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Price")
                    TextField("0.00", text: $price)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .price)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Cost")
                    TextField("0.00", text: $cost)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .cost)
                }
            }

            if let minP = calculatedMinPrice {
                HStack {
                    Text("Min Price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", minP))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // RSP / MSRP row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("RSP Price")
                    TextField("0.00", text: $rsPrice)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .rsPrice)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("MSRP / Retail")
                    TextField("0.00", text: $msrp)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .msrp)
                }
            }

            // ── Shipping ──────────────────────────────────────────────────
            // Qty / Source / Location row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Qty")
                    TextField("1", text: $qty)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($focusedField, equals: .qty)
                        .frame(maxWidth: 60)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Source")
                    SourcePickerField(source: $source, placeholder: "Auction: Lot")
                }
                surplusLocationRow
            }

            // Dims row
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Length")
                    TextField("in", text: $packageLength)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .packageLength)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Width")
                    TextField("in", text: $packageWidth)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .packageWidth)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Depth")
                    TextField("in", text: $packageDepth)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($focusedField, equals: .packageDepth)
                }
            }

            // Shipping Policy + Return Policy (eBay)
            if let policies = businessPolicies {
                HStack(alignment: .top, spacing: 12) {
                    if !policies.shipping.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Shipping Policy")
                            Picker("Shipping Policy", selection: $ebyShippingPolicy) {
                                Text("Select…").tag("")
                                ForEach(policies.shipping) { policy in
                                    Text(policy.name).tag(policy.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.hotPink)
                        }
                    }
                    if !policies.returnPolicies.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Return Policy")
                            Picker("Return Policy", selection: $ebyReturnPolicy) {
                                Text("Select…").tag("")
                                ForEach(policies.returnPolicies) { policy in
                                    Text(policy.name).tag(policy.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.hotPink)
                        }
                    }
                }
            }

            // ── Shipping rate calculator ──────────────────────────────────
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Weight")
                    HStack(spacing: 4) {
                        TextField("lb", text: $weightLbs)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .focused($focusedField, equals: .weight)
                        Text("lb").font(.caption2).foregroundStyle(.secondary)
                        TextField("oz", text: $weightOzPart)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .focused($focusedField, equals: .weightOz)
                        Text("oz").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await calculateShipping() }
                } label: {
                    if isCalculatingShipping {
                        Label("Calculating…", systemImage: "arrow.clockwise")
                    } else {
                        Label("Calculate Shipping", systemImage: "shippingbox")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.hotPink)
                .disabled(isCalculatingShipping || weight.isEmpty)
            }

            if let rate = shippingRateFull {
                shippingRateRow(rate: rate)
            }

            if let err = shippingRateError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        }
    }

    /// Monospaced Location field used by the Surplus form.
    private var surplusLocationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Location")
            TextField("Location", text: $location)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .focused($focusedField, equals: .location)
        }
    }

    @ViewBuilder
    private func shippingRateRow(rate: EasyPostClient.Rate) -> some View {
        HStack {
            Text(String(format: "$%.2f", rate.rate))
                .fontWeight(.semibold)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(rate.carrier) \(rate.service)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let days = rate.deliveryDays {
                Spacer()
                Text("\(days)d")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Notes row for the Surplus form — uses its own phrase list.
    private var surplusNotesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("Notes")
                Spacer()
                Button { showSurplusNotesPhrases = true } label: {
                    Label("Phrases", systemImage: "text.badge.plus")
                        .font(.caption)
                }
            }
            TextField("Condition, extras…", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($focusedField, equals: .notes)
        }
    }

    // MARK: Shared sub-views

    private var skuRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("SKU")
                if skuGenerating {
                    Text("Generating…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    Text(sku.isEmpty ? "—" : sku)
                        .font(.body.monospaced())
                        .foregroundStyle(sku.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            }
            if !skuGenerating && sku.isEmpty {
                Button { Task { await generateSku() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .padding(.top, 18)
            }
        }
    }

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("Notes")
                Spacer()
                Button { showStockPhrases = true } label: {
                    Label("Phrases", systemImage: "text.badge.plus")
                        .font(.caption)
                }
            }
            TextField("Condition, edition, extras…", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($focusedField, equals: .notes)
        }
    }

    // MARK: - Photo strip

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Stock image (shown when no user photos uploaded)
                if photoURLs.isEmpty, let urlStr = productImageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        Text("Stock").font(.caption2).padding(3)
                            .background(.black.opacity(0.5)).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4)),
                        alignment: .bottomLeading
                    )
                    .onTapGesture { enlargedImageURL = urlStr }
                }

                // Uploaded photos
                ForEach(Array(photoURLs.enumerated()), id: \.element) { i, urlStr in
                    if let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color.secondary.opacity(0.2)
                            }
                        }
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                photoURLs.remove(at: i)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .font(.title3)
                            }
                            .padding(4)
                        }
                        .overlay(
                            Text(i == 0 ? "Primary" : "#\(i+1)").font(.caption2).padding(3)
                                .background(.black.opacity(0.5)).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4)),
                            alignment: .bottomLeading
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor, lineWidth: 2.5)
                                .opacity(dropTargetIndex == i ? 1 : 0)
                        )
                        .onTapGesture { enlargedImageURL = urlStr }
                        .draggable(PhotoDragItem(index: i))
                        .dropDestination(for: PhotoDragItem.self) { items, _ in
                            guard let src = items.first?.index, src != i else { return false }
                            withAnimation(.spring(duration: 0.25)) {
                                photoURLs.move(
                                    fromOffsets: IndexSet(integer: src),
                                    toOffset: src < i ? i + 1 : i
                                )
                            }
                            dropTargetIndex = nil
                            return true
                        } isTargeted: { targeted in
                            dropTargetIndex = targeted ? i : nil
                        }
                    }
                }

                // Add photo button (up to 12)
                if photoURLs.count < 12 {
                    Button {
                        #if os(iOS)
                        if cameraAvailable {
                            showPhotoSourceDialog = true
                        } else {
                            showPhotoLibrary = true
                        }
                        #else
                        showPhotoLibrary = true
                        #endif
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 110, height: 110)
                            VStack(spacing: 6) {
                                if isUploading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "camera.badge.plus")
                                        .font(.title2)
                                    Text("Add Photo")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Add Photo", isPresented: $showPhotoSourceDialog) {
                        Button("Photo Library") { showPhotoLibrary = true }
                        Button("Camera") { showCamera = true }
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 130)
    }

    // MARK: - Helpers

    /// Minimum eBay price: ((cost + shipping) * 1.153) + 1
    private var calculatedMinPrice: Double? {
        guard let costVal = Double(cost), costVal > 0 else { return nil }
        let shipping = shippingRateZip?.rate ?? 0.0
        return ((costVal + shipping) * 1.153) + 1.0
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func exLibraryNote(for cond: ItemCondition?) -> String {
        switch cond {
        case .good:
            return "library discard, withdrawn from circulation; includes identifying marks, stickers, and other artifacts; may include protective plastic"
        case .acceptable:
            return "library discard, withdrawn from circulation; in addition to standard indentifying marks, stickers, and other artifacts, it includes additional cosmetic flaws from removal or significant use"
        default:
            return ""
        }
    }

    /// Recomputes `weight` (total oz) from the lb and oz display fields.
    private func updateWeightFromParts() {
        let lbs   = Int(weightLbs) ?? 0
        let oz    = Int(weightOzPart) ?? 0
        let total = lbs * 16 + oz
        weight = total > 0 ? String(total) : ""
    }

    /// Populates the lb/oz display fields from the current `weight` total-oz string.
    private func syncWeightDisplay() {
        guard let totalOz = Double(weight), totalOz > 0 else {
            weightLbs = ""; weightOzPart = ""; return
        }
        let total = Int(totalOz.rounded())
        weightLbs    = total / 16 > 0 ? String(total / 16) : ""
        weightOzPart = total % 16 > 0 ? String(total % 16) : ""
    }

    /// Two-way binding into the `ebySpecificValues` dict for a given spec name.
    private func ebySpecificBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { ebySpecificValues[name] ?? "" },
            set: { ebySpecificValues[name] = $0 }
        )
    }

    // MARK: - Data loading

    private func loadPending() {
        if let payload = navigator.pendingReopenPayload {
            reopenItem(payload)
            navigator.pendingReopenPayload = nil
            return   // reopenItem populates everything; skip other pending data
        }
        if let pending = navigator.pendingBarcode {
            routeBarcode(pending)
            navigator.pendingBarcode = nil
        }
        if let pending = navigator.pendingTitle {
            title = pending
            navigator.pendingTitle = nil
        }
        if let pd = navigator.pendingProductData {
            if !pd.asin.isEmpty { asin = pd.asin }
            author          = pd.author ?? ""
            publisher       = pd.publisher ?? ""
            pubDate         = pd.releaseDate ?? ""
            itemMedia       = pd.media ?? ""
            weight          = pd.weight ?? ""
            syncWeightDisplay()
            productImageURL = pd.imageURL
            navigator.pendingProductData = nil
        }
        if let cd = navigator.pendingCatData {
            catData = cd
            if asin.isEmpty { asin = cd.asin }
            navigator.pendingCatData = nil
        }
        // Always restore per-type source/location if empty
        if source.isEmpty   { source   = settings.source(for: itemType) }
        if location.isEmpty { location = settings.location(for: itemType) }
    }

    /// Route a scanned barcode to the appropriate field based on format.
    private func routeBarcode(_ code: String) {
        let digits = code.filter(\.isNumber)
        if digits.count == 13 && (digits.hasPrefix("978") || digits.hasPrefix("979")) {
            isbn = code
        } else if digits.count > 10 {
            upc = code
        } else {
            asin = code
        }
    }

    private func generateSku() async {
        guard sku.isEmpty, !skuGenerating else { return }
        skuGenerating = true
        sku = (try? await AoBClient.shared.getAutoSku()) ?? ""
        skuGenerating = false
    }

    private func uploadPickedPhotos(_ items: [PhotosPickerItem]) async {
        isUploading = true
        for item in items {
            guard photoURLs.count < 12,
                  let data = try? await item.loadTransferable(type: Data.self)
            else { continue }
            #if os(iOS)
            if itemType == .media, let image = UIImage(data: data) {
                let processedData = await processedImageData(for: image) ?? data
                await uploadImageData(processedData)
                continue
            }
            #endif
            await uploadImageData(data)
        }
        pickerItems = []
        isUploading = false
    }

    #if os(iOS)
    private func processPendingCameraCapture() async {
        guard let image = capturedCameraImage else { return }
        capturedCameraImage = nil
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(150))
        await uploadCapturedPhoto(image)
    }

    private func uploadCapturedPhoto(_ image: UIImage) async {
        guard photoURLs.count < 12 else { return }
        isUploading = true
        if let data = await processedImageData(for: image) {
            await uploadImageData(data)
        }
        isUploading = false
    }

    private func processedImageData(for image: UIImage) async -> Data? {
        let finalImage: UIImage
        if itemType == .media {
            let result = MediaCropService.cropToSubject(image)
                ?? CropResult(cropped: image, normalizedRect: CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84))
            finalImage = await cropCoordinator.awaitDecision(original: image, cropResult: result)
        } else {
            finalImage = image
        }
        return finalImage.jpegData(compressionQuality: 0.85)
    }
    #endif

    private func uploadImageData(_ data: Data) async {
        guard photoURLs.count < 12 else { return }
        // Ensure a SKU exists before uploading so the filename is always SKU-based
        if sku.isEmpty { await generateSku() }
        let uid = UUID().uuidString.prefix(8)
        let filename = sku.isEmpty ? "inzentory-\(uid).jpg"
                                   : "\(sku)-\(uid).jpg"
        if let url = try? await DOSpacesClient.shared.upload(imageData: data, filename: filename) {
            photoURLs.append(url)
        }
    }

    // MARK: - Reopen

    private func reopenItem(_ payload: ReopenPayload) {
        clearForm()
        isReopened        = true
        inzentoryDraftId  = payload.inzentoryDraftId
        itemType          = payload.type
        if let s = payload.sku, !s.isEmpty {
            sku = s
        } else {
            Task { await generateSku() }
        }
        asin            = payload.asin ?? ""
        isbn            = payload.isbn ?? ""
        upc             = payload.upc ?? ""
        title           = payload.title
        author          = payload.author
        publisher       = payload.publisher
        pubDate         = payload.pubDate
        itemMedia       = payload.itemMedia
        weight          = payload.weight
        syncWeightDisplay()
        qty             = payload.qty.isEmpty ? "1" : payload.qty
        price           = payload.price
        condition       = payload.condition
        source          = payload.source.isEmpty ? settings.source(for: payload.type) : payload.source
        location        = payload.location.isEmpty ? settings.location(for: payload.type) : payload.location
        notes           = payload.notes
        photoURLs       = payload.photoURLs
        // Surplus fields
        itemDescription  = payload.description
        cost             = payload.cost
        minPrice         = payload.minPrice
        rsPrice          = payload.rsPrice
        msrp             = payload.msrp
        packageLength    = payload.packageLength
        packageWidth     = payload.packageWidth
        packageDepth     = payload.packageDepth
        ebyCat            = payload.ebyCat
        ebyCatName        = payload.ebyCatName
        ebyConditionCode  = payload.ebayConditionCode
        // Restore saved specifics values BEFORE loadEbySpecifics() runs,
        // so the filter-to-valid-names step preserves them.
        ebySpecificValues = payload.ebayItemSpecifics
        // Brand stored in publisher for surplus form
        if payload.type == .surplus && !payload.brand.isEmpty {
            publisher = payload.brand
        }
        // Reload condition codes and item specifics for the restored category.
        // loadEbySpecifics() preserves ebyConditionCode when it's already set.
        if payload.type == .surplus && !payload.ebyCat.isEmpty {
            Task { await loadEbySpecifics() }
        }
    }

    // MARK: - Actions

    private func saveDraft() async {
        isSavingDraft = true
        defer { isSavingDraft = false }
        let payload = buildDraftPayload(status: "draft")
        do {
            if let id = inzentoryDraftId {
                _ = try await APIClient.shared.updateListing(id: id, payload)
                settings.setDraftItemType(id, itemType)
            } else {
                let created = try await APIClient.shared.createListing(payload)
                inzentoryDraftId = created.id
                isReopened = true  // now tracking a server-side draft
                settings.setDraftItemType(created.id, itemType)
            }
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func buildDraftPayload(status: String) -> DraftPayload {
        let isSurplus = itemType == .surplus
        // Compute eBay condition name from the loaded codes list
        let ebayCondName: String? = isSurplus && !ebyConditionCode.isEmpty
            ? ebyConditionCodes.first(where: { $0.id == ebyConditionCode })?.name
            : nil
        return DraftPayload(
            status:    status,
            sku:       sku.isEmpty ? nil : sku,
            title:     title.isEmpty ? nil : title,
            qty:       Int(qty),
            isbn:      isbn.isEmpty ? nil : isbn,
            asin:      asin.isEmpty ? nil : asin,
            upc:       upc.isEmpty ? nil : upc,
            weight:    weight.isEmpty ? nil : Double(weight),
            location:  location.isEmpty ? nil : location,
            condition: condition.map { String($0.rawValue) },
            notes:     notes.isEmpty ? nil : notes,
            source:    source.isEmpty ? nil : source,
            price:     price.isEmpty ? nil : Double(price),
            p9:        isSurplus ? "surplus" : "stories",
            description:       isSurplus && !itemDescription.isEmpty ? itemDescription : nil,
            brand:             isSurplus && !publisher.isEmpty       ? publisher       : nil,
            lister:            isSurplus ? auth.username             : nil,
            cost:              isSurplus ? Double(cost)              : nil,
            minPrice:          isSurplus ? Double(minPrice)          : nil,
            rspPrice:          isSurplus ? Double(rsPrice)           : nil,
            msrp:              isSurplus ? Double(msrp)              : nil,
            packageLength:     isSurplus ? Double(packageLength)     : nil,
            packageWidth:      isSurplus ? Double(packageWidth)      : nil,
            packageDepth:      isSurplus ? Double(packageDepth)      : nil,
            ebayCat:           isSurplus && !ebyCat.isEmpty          ? ebyCat          : nil,
            ebayCatName:       isSurplus && !ebyCatName.isEmpty      ? ebyCatName      : nil,
            ebayConditionCode: isSurplus && !ebyConditionCode.isEmpty ? ebyConditionCode : nil,
            ebayConditionName: ebayCondName,
            ebayItemSpecifics: isSurplus && !ebySpecificValues.isEmpty
                ? ebySpecificValues.filter { !$0.value.isEmpty } : nil,
            photos:            photoURLs.isEmpty ? nil : photoURLs
        )
    }

    private func submitListing() async {
        isSubmitting = true
        defer { isSubmitting = false }

        // Capture before save() clears the form
        let currentSku          = sku
        let currentTitle        = title
        let currentAuthor       = author
        let currentAsin         = asin
        let currentIsbn         = isbn
        let currentUpc          = upc
        let currentConditionRaw = condition?.rawValue ?? 0
        let currentQty          = Int(qty) ?? 1
        let currentIsEditMode   = isEditMode

        // Primary image: first user-uploaded photo, falling back to stock product image
        let primaryImage = photoURLs.first ?? productImageURL
        let extraImages  = photoURLs.count > 1 ? Array(photoURLs.dropFirst()) : []

        // Build flex fields based on form type
        let flexFields: [String: String]?
        if itemType == .media {
            flexFields = isbn.isEmpty ? nil : ["isbn13": isbn]
        } else {
            var sf: [String: String] = [:]
            if !rsPrice.isEmpty        { sf["rsp_price"]       = rsPrice }
            if !msrp.isEmpty           { sf["msrp"]            = msrp }
            if !packageLength.isEmpty  { sf["package_length"]  = packageLength }
            if !packageWidth.isEmpty   { sf["package_width"]   = packageWidth }
            if !packageDepth.isEmpty   { sf["package_depth"]   = packageDepth }
            if !ebyCat.isEmpty            { sf["eby_cat1"]            = ebyCat }
            if !ebyShippingPolicy.isEmpty { sf["eby_shipping_policy"] = ebyShippingPolicy }
            if !ebyReturnPolicy.isEmpty   { sf["eby_return_policy"]   = ebyReturnPolicy }
            flexFields = sf.isEmpty ? nil : sf
        }

        // Item specifics (surplus only) — keyed by original field name
        let itemSpecificsToSend: [String: String]? = itemType == .surplus && !ebySpecificValues.isEmpty
            ? ebySpecificValues.filter { !$0.value.isEmpty }
            : nil

        let uploadItem = AoBClient.InventoryItem(
            sku:          currentSku,
            title:        currentTitle,
            description:  itemType == .surplus && !itemDescription.isEmpty ? itemDescription : nil,
            cost:         itemType == .surplus && !cost.isEmpty ? cost : nil,
            author:       author,
            isbn:         asin.isEmpty ? nil : asin,
            upc:          upc.isEmpty ? nil : upc,
            flex:         flexFields,
            price:        price.isEmpty ? nil : price,
            p2:           auth.username,
            location:     location,
            condition:    condition?.rawValue ?? ItemCondition.good.rawValue,
            notes:        notes,
            source:       source,
            qty:          Int(qty) ?? 1,
            p9:           itemType == .media ? "stories" : "surplus",
            publisher:    itemType == .surplus && !publisher.isEmpty ? publisher : nil,
            image:        primaryImage,
            extraImages:  extraImages,
            itemSpecifics: itemSpecificsToSend
        )

        do {
            _ = try await AoBClient.shared.inventoryUpload(item: uploadItem)

            // Mark InZentory draft as ready (background, non-blocking)
            if let draftId = inzentoryDraftId {
                Task { try? await APIClient.shared.updateListing(id: draftId, DraftPayload(status: "ready")) }
            }

            // Capture surplus template data before save() resets the form fields
            if itemType == .surplus {
                let ebayCondName = ebyConditionCode.isEmpty ? ""
                    : ebyConditionCodes.first(where: { $0.id == ebyConditionCode })?.name ?? ""
                pendingTemplateData = SurplusTemplateData(
                    title:         currentTitle,
                    description:   itemDescription,
                    condition:     condition.map(\.displayName) ?? "",
                    ebayCondition: ebayCondName,
                    notes:         notes,
                    rspPrice:      Double(rsPrice),
                    msrp:          Double(msrp),
                    price:         Double(price),
                    cost:          Double(cost),
                    sku:           currentSku,
                    brand:         publisher,
                    ebayCatName:   ebyCatName,
                    weightOz:      Double(weight),
                    lengthIn:      Double(packageLength),
                    widthIn:       Double(packageWidth),
                    depthIn:       Double(packageDepth),
                    shippingRate:  shippingRateZip
                )
            }

            if itemType == .media {
                lastListedProductId = currentAsin.trimmingCharacters(in: .whitespaces).isEmpty
                    ? currentUpc.trimmingCharacters(in: .whitespaces)
                    : currentAsin.trimmingCharacters(in: .whitespaces)
            }
            save(status: .listed)   // clears form, so use captured values below
            recentRefreshID = UUID()

            // Auto-print SKU label in background — Stories only, new listings only, not updates
            // Surplus uses the manual Print Label button instead.
            if itemType == .media && !currentIsEditMode && settings.selectedPrinterId > 0 && !currentSku.isEmpty {
                let printCopies = currentQty
                Task {
                    do {
                        try await PrintNodeClient.shared.printSKULabel(
                            sku: currentSku,
                            title: currentTitle,
                            author: currentAuthor,
                            asin: currentAsin,
                            isbn: currentIsbn,
                            upc: currentUpc,
                            conditionRaw: currentConditionRaw,
                            copies: printCopies,
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

            submittedTitle = currentTitle
            withAnimation(.spring(duration: 0.3)) { showSubmitSuccess = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.spring(duration: 0.3)) { showSubmitSuccess = false }
            }
            if pendingTemplateData != nil {
                showTemplateSheet = true
            }
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func save(status: ListingStatus) {
        let item = ListingItem(
            type:         itemType,
            status:       status,
            sku:          sku.isEmpty ? nil : sku,
            asin:         asin.isEmpty ? nil : asin,
            isbn:         isbn.isEmpty ? nil : isbn,
            upc:          upc.isEmpty ? nil : upc,
            title:        title,
            author:       author,
            publisher:    publisher,
            pubDate:      pubDate,
            itemMedia:    itemMedia,
            weight:       weight,
            qty:          Int(qty) ?? 1,
            price:        price.isEmpty ? nil : price,
            conditionRaw: condition?.rawValue,
            source:       source,
            location:     location,
            notes:        notes,
            photoURLs:    photoURLs
        )
        modelContext.insert(item)
        settings.setSource(source, for: itemType)
        settings.setLocation(location, for: itemType)
        clearForm()
    }

    private func clearForm() {
        clearFormSnapshot()
        focusedField      = nil
        inzentoryDraftId  = nil
        isReopened        = false
        // itemType intentionally kept — use the switch button to change form type
        sku              = ""
        asin             = ""
        isbn             = ""
        upc              = ""
        condition        = nil
        isExLibrary      = false
        title            = ""
        author           = ""
        publisher        = ""
        pubDate          = ""
        itemMedia        = ""
        weight           = ""
        weightLbs        = ""
        weightOzPart     = ""
        qty              = "1"
        price            = ""
        notes            = ""
        photoURLs        = []
        productImageURL  = nil
        catData          = nil
        // Surplus fields
        itemDescription    = ""
        cost               = ""
        minPrice           = ""
        rsPrice            = ""
        msrp               = ""
        packageLength      = ""
        packageWidth       = ""
        packageDepth       = ""
        ebyCat             = ""
        ebyCatName         = ""
        // eBay specifics
        ebyConditionCodes  = []
        ebyConditionCode   = ""
        ebyItemSpecifics   = []
        ebySpecificValues  = [:]
        specificsError     = nil
        ebyShippingPolicy  = ""
        ebyReturnPolicy    = ""
        // Shipping calculator
        shippingRateZip   = nil
        shippingRateFull  = nil
        shippingRateError = nil
        // source/location intentionally kept (per-type, saved via onChange)
    }

    // MARK: - Form snapshot (local autosave)

    private static let draftKey = "listFormDraft"

    /// Lightweight snapshot of the form fields persisted to UserDefaults.
    private struct FormDraft: Codable {
        var itemType: String
        var sku: String; var asin: String; var isbn: String; var upc: String
        var conditionRaw: Int?
        var title: String; var author: String; var publisher: String
        var pubDate: String; var itemMedia: String
        var weight: String; var qty: String; var price: String
        var notes: String
        var photoURLs: [String]
        // Surplus
        var itemDescription: String; var cost: String; var minPrice: String
        var rsPrice: String; var msrp: String
        var packageLength: String; var packageWidth: String; var packageDepth: String
        var ebyCat: String; var ebyCatName: String
        var ebyShippingPolicy: String; var ebyReturnPolicy: String
        var ebySpecificValues: [String: String]

        /// Draft is worth saving/restoring only if the user entered at least one meaningful value.
        var isEmpty: Bool {
            title.isEmpty && asin.isEmpty && isbn.isEmpty && upc.isEmpty
                && photoURLs.isEmpty && itemDescription.isEmpty
        }
    }

    /// Snapshots current form state to UserDefaults.
    /// Called when the app moves to the background. No-op for reopened items or empty forms.
    private func saveFormSnapshot() {
        guard !isReopened else { return }
        let draft = FormDraft(
            itemType: itemType.rawValue,
            sku: sku, asin: asin, isbn: isbn, upc: upc,
            conditionRaw: condition?.rawValue,
            title: title, author: author, publisher: publisher,
            pubDate: pubDate, itemMedia: itemMedia,
            weight: weight, qty: qty, price: price,
            notes: notes,
            photoURLs: photoURLs,
            itemDescription: itemDescription, cost: cost, minPrice: minPrice,
            rsPrice: rsPrice, msrp: msrp,
            packageLength: packageLength, packageWidth: packageWidth, packageDepth: packageDepth,
            ebyCat: ebyCat, ebyCatName: ebyCatName,
            ebyShippingPolicy: ebyShippingPolicy, ebyReturnPolicy: ebyReturnPolicy,
            ebySpecificValues: ebySpecificValues
        )
        guard !draft.isEmpty else { clearFormSnapshot(); return }
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: Self.draftKey)
        }
    }

    /// Removes any saved snapshot from UserDefaults.
    private func clearFormSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
    }

    /// Restores a previously saved snapshot into the form if one exists and the form is currently blank.
    private func restoreFormSnapshotIfNeeded() {
        guard !isReopened,
              navigator.pendingBarcode == nil,
              navigator.pendingReopenPayload == nil else { return }
        // Only restore into a blank form — avoids overwriting scan-populated fields on tab switch
        guard title.isEmpty && asin.isEmpty && isbn.isEmpty && upc.isEmpty && photoURLs.isEmpty else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(FormDraft.self, from: data),
              !draft.isEmpty else { return }

        itemType         = ItemType(rawValue: draft.itemType) ?? .media
        sku              = draft.sku
        asin             = draft.asin
        isbn             = draft.isbn
        upc              = draft.upc
        condition        = draft.conditionRaw.flatMap(ItemCondition.init(rawValue:))
        title            = draft.title
        author           = draft.author
        publisher        = draft.publisher
        pubDate          = draft.pubDate
        itemMedia        = draft.itemMedia
        weight           = draft.weight
        syncWeightDisplay()
        qty              = draft.qty
        price            = draft.price
        notes            = draft.notes
        photoURLs        = draft.photoURLs
        itemDescription  = draft.itemDescription
        cost             = draft.cost
        minPrice         = draft.minPrice
        rsPrice          = draft.rsPrice
        msrp             = draft.msrp
        packageLength    = draft.packageLength
        packageWidth     = draft.packageWidth
        packageDepth     = draft.packageDepth
        ebyCat           = draft.ebyCat
        ebyCatName       = draft.ebyCatName
        ebyShippingPolicy = draft.ebyShippingPolicy
        ebyReturnPolicy   = draft.ebyReturnPolicy
        // Restore saved specifics values BEFORE loadEbySpecifics() runs (same reason as reopenItem).
        ebySpecificValues = draft.ebySpecificValues
        if !draft.ebyCat.isEmpty {
            Task { await loadEbySpecifics() }
        }
    }

    // MARK: - Shipping rate calculator

    private func calculateShipping() async {
        guard let weightOz = Double(weight), weightOz > 0 else { return }
        let lengthIn = Double(packageLength) ?? 1
        let widthIn  = Double(packageWidth)  ?? 1
        let heightIn = Double(packageDepth)  ?? 1

        isCalculatingShipping = true
        shippingRateError     = nil
        shippingRateZip       = nil
        shippingRateFull      = nil

        async let zipResult  = EasyPostClient.shared.cheapestRate(
            weightOz: weightOz, lengthIn: lengthIn, widthIn: widthIn, heightIn: heightIn,
            fullAddress: false
        )
        async let fullResult = EasyPostClient.shared.cheapestRate(
            weightOz: weightOz, lengthIn: lengthIn, widthIn: widthIn, heightIn: heightIn,
            fullAddress: true
        )

        do { shippingRateZip  = try await zipResult  } catch { shippingRateError = error.localizedDescription }
        do { shippingRateFull = try await fullResult } catch { if shippingRateError == nil { shippingRateError = error.localizedDescription } }

        isCalculatingShipping = false
    }

    // MARK: - Form type switch

    private func switchFormType() {
        let newType: ItemType = itemType == .media ? .surplus : .media
        // Save current source/location (already saved continuously via onChange, but be explicit)
        settings.setSource(source, for: itemType)
        settings.setLocation(location, for: itemType)
        clearForm()
        itemType = newType
        // Load the new form type's source/location
        source   = settings.source(for: newType)
        location = settings.location(for: newType)
    }

    // MARK: - eBay Specifics Loader

    private func loadEbySpecifics() async {
        guard !ebyCat.isEmpty else { return }
        isLoadingSpecifics = true
        specificsError = nil
        do {
            let data = try await AoBClient.shared.fetchEbyCategorySpecifics(id: ebyCat)
            ebyConditionCodes  = data.condition_codes ?? []
            ebyItemSpecifics   = data.itemspecifics ?? []
            // Pre-select first condition code if only one option
            if ebyConditionCode.isEmpty, let first = ebyConditionCodes.first {
                ebyConditionCode = first.id
            }
            // Reset values for specifics that no longer apply
            let validNames = Set(ebyItemSpecifics.map(\.name))
            ebySpecificValues = ebySpecificValues.filter { validNames.contains($0.key) }
        } catch {
            specificsError = error.localizedDescription
        }
        isLoadingSpecifics = false
    }

    // MARK: - Manual SKU label print (Surplus)

    private func printSkuLabel() async {
        guard settings.selectedPrinterId > 0, !sku.isEmpty else { return }
        isPrinting = true
        defer { isPrinting = false }
        do {
            try await PrintNodeClient.shared.printSKULabel(
                sku: sku,
                title: title,
                author: author,
                asin: asin,
                isbn: isbn,
                upc: upc,
                conditionRaw: condition?.rawValue ?? 0,
                copies: Int(qty) ?? 1,
                printerId: settings.selectedPrinterId,
                format: settings.labelFormat,
                orientation: settings.labelOrientation,
                zplDpi: settings.zplDpi
            )
        } catch {
            printError = error.localizedDescription
        }
    }

    // MARK: - Lookup

    private func performLookup(_ barcode: String) async {
        guard !isLookupLoading else { return }
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLookupLoading = true
        scanLookupError = nil
        lookupFocused = false

        let result: ScanResult?
        if trimmed.uppercased().hasPrefix("X") {
            result = await lookupFNSKUForField(trimmed)
        } else {
            result = await lookupConcurrentForField(trimmed)
        }

        isLookupLoading = false

        if let result {
            lookupText = ""
            clearForm()
            applyResult(result)
            Task { await generateSku() }
            if case .list = result.catData?.verdict() {
                // list verdict — leave focus on form so user can complete the listing
            } else {
                // reject/borderline — refocus lookup so external scanner can fire immediately
                lookupFocused = true
            }
        }
    }

    private func lookupConcurrentForField(_ barcode: String) async -> ScanResult? {
        var product: AoBClient.ProductData? = nil
        var cat: AoBClient.CatData? = nil

        do {
            try await withThrowingTaskGroup(of: LookupPartial.self) { group in
                group.addTask { .product(try await AoBClient.shared.productData(for: barcode)) }
                group.addTask { .cat(try await AoBClient.shared.catData(for: barcode)) }
                for try await partial in group {
                    switch partial {
                    case .product(let p): product = p
                    case .cat(let c):     cat = c
                    }
                }
            }
        } catch {
            scanLookupError = error.localizedDescription
            return nil
        }

        return ScanResult(barcode: barcode, productData: product, catData: cat)
    }

    private func lookupFNSKUForField(_ fnsku: String) async -> ScanResult? {
        let cat: AoBClient.CatData?
        do {
            cat = try await AoBClient.shared.catData(for: fnsku)
        } catch {
            scanLookupError = error.localizedDescription
            return nil
        }

        let effectiveID = cat?.asin ?? fnsku

        let product: AoBClient.ProductData?
        if let asin = cat?.asin {
            product = try? await AoBClient.shared.productData(for: asin)
        } else {
            product = nil
        }

        return ScanResult(barcode: effectiveID, productData: product, catData: cat)
    }

    private func applyResult(_ result: ScanResult) {
        let barcode = result.catData?.upc ?? result.barcode
        routeBarcode(barcode)

        if let pd = result.productData {
            if !pd.asin.isEmpty { asin = pd.asin }
            title           = pd.title
            author          = pd.author ?? ""
            publisher       = pd.publisher ?? ""
            pubDate         = pd.releaseDate ?? ""
            itemMedia       = pd.media ?? ""
            weight          = pd.weight ?? ""
            syncWeightDisplay()
            productImageURL = pd.imageURL
        }
        if let cd = result.catData {
            catData = cd
            if asin.isEmpty { asin = cd.asin }
        }
        if source.isEmpty   { source   = settings.source(for: itemType) }
        if location.isEmpty { location = settings.location(for: itemType) }
    }
}

// MARK: - Crop review coordinator

@MainActor
private final class CropReviewCoordinator: ObservableObject {
    struct Pending: Identifiable {
        let id = UUID()
        let original: UIImage
        let cropResult: CropResult
    }

    @Published var pending: Pending?
    private var continuation: CheckedContinuation<UIImage, Never>?

    func awaitDecision(original: UIImage, cropResult: CropResult) async -> UIImage {
        await withCheckedContinuation { cont in
            continuation = cont
            pending = Pending(original: original, cropResult: cropResult)
        }
    }

    func resolve(_ image: UIImage) {
        pending = nil
        continuation?.resume(returning: image)
        continuation = nil
    }

    func resolveWithOriginal() {
        guard let pending else { return }
        CropFeedbackStore.shared.record(.rejected)
        resolve(pending.original)
    }
}

// MARK: - Photo drag item

private struct PhotoDragItem: Transferable {
    let index: Int
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation<PhotoDragItem, String>(
            exporting: { String($0.index) },
            importing: { PhotoDragItem(index: Int($0) ?? 0) }
        )
    }
}

// MARK: - Crop preview sheet

#if os(iOS)
private struct CropPreviewSheet: View {
    let pending: CropReviewCoordinator.Pending
    let onChoose: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showManualCrop = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 6) {
                        Image(uiImage: pending.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        Image(uiImage: pending.cropResult.cropped)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Auto-cropped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        Button("Use Original") {
                            CropFeedbackStore.shared.record(.rejected)
                            onChoose(pending.original)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Use Crop") {
                            CropFeedbackStore.shared.record(.accepted)
                            onChoose(pending.cropResult.cropped)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        showManualCrop = true
                    } label: {
                        Label("Crop Manually", systemImage: "crop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.top, 16)
            .navigationTitle("Review Crop")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .fullScreenCover(isPresented: $showManualCrop) {
            ManualCropView(
                image: pending.original,
                initialRect: pending.cropResult.normalizedRect
            ) { croppedImage in
                CropFeedbackStore.shared.record(.manual)
                onChoose(croppedImage)
                dismiss()
            }
        }
    }
}
#endif

// MARK: - Full-screen image viewer

private struct ImageFullScreenView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(20)
            }
        }
    }
}

// MARK: - Camera picker

#if os(iOS)
private struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let capturedImage = info[.originalImage] as? UIImage {
                parent.onCapture(capturedImage)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

// MARK: - Stock phrases sheet

private struct StockPhrasesSheet: View {
    let phrases: [String]
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List(phrases, id: \.self) { phrase in
                Button(phrase) { onSelect(phrase) }
                    .foregroundStyle(.primary)
            }
            .navigationTitle("Stock Phrases")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        ListFormView()
    }
    .modelContainer(for: ListingItem.self, inMemory: true)
    .environment(AppSettings.shared)
    .environment(AppNavigator())
    .environment(AuthService())
}
