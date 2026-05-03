//
//  AuditView.swift
//  InZentory
//

import SwiftUI
#if os(iOS)
import VisionKit
import AVFoundation
#endif

// MARK: - Mode

private enum AuditMode: String, CaseIterable {
    case audit = "Audit"
    case move  = "Move"
}

struct AuditView: View {

    // MARK: - State

    @State private var engine              = AuditEngine()
    @State private var mode: AuditMode    = .audit

    // Audit mode fields
    @State private var location           = ""
    @State private var sku                = ""
    @FocusState private var locationFocused: Bool
    @FocusState private var skuFocused: Bool

    // Move mode fields
    @State private var moveLocation       = ""
    @State private var moveSku            = ""
    @FocusState private var moveLocationFocused: Bool
    @FocusState private var moveSkuFocused: Bool

    // Scanner
    @State private var isScannerActive          = false
    @State private var isCameraScanning         = false
    @State private var isMoveLocationEditing    = false   // location overlay in scanner

    // Qty alert queue (fires when a retained item has qty > 1)
    @State private var pendingQtyAlerts: [(id: UUID, qty: Int, sku: String)] = []
    @State private var activeQtyAlert: (id: UUID, qty: Int, sku: String)?
    @State private var qtyAlertInput            = ""
    @State private var qtyAlertedIDs: Set<UUID> = []

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                modePicker
                switch mode {
                case .audit:
                    locationSection
                    skuSection
                    actionsSection
                case .move:
                    moveLocationSection
                    moveSkuSection
                    moveActionsSection
                }
                resultContent
            }
            .navigationTitle(mode == .audit ? "Audit" : "Move Items")
            .keyboardDoneButton()
            .onChange(of: mode) { _, _ in
                engine.reset()
                sku     = ""
                moveSku = ""
                isMoveLocationEditing = false
            }
            .sheet(isPresented: $isScannerActive) {
                scannerSheet
            }
            .onChange(of: engine.resultChangeCount) { _, _ in
                guard mode == .audit else { return }
                enqueueQtyAlerts(for: engine.state)
            }
            .alert("Quantity Check", isPresented: Binding(
                get: { activeQtyAlert != nil },
                set: { shown in if !shown { activeQtyAlert = nil; dequeueNextQtyAlert() } }
            ), presenting: activeQtyAlert) { data in
                TextField("Quantity", text: $qtyAlertInput)
                    .keyboardType(.numberPad)
                Button("Update") {
                    guard let qty = Int(qtyAlertInput), qty >= 0 else { return }
                    let id = data.id
                    Task { await engine.updateQty(id: id, qty: qty) }
                }
                Button("Keep \(data.qty)", role: .cancel) { }
            } message: { data in
                Text("This item (\(data.sku)) has a quantity of \(data.qty) on hand. Update if the count has changed.")
            }
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(AuditMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Audit: Location section

    private var locationSection: some View {
        Section("Location") {
            TextField("Location", text: $location)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .focused($locationFocused)
        }
    }

    // MARK: - Audit: SKU / ISBN / UPC section

    private var skuSection: some View {
        Section("SKU / ISBN / UPC") {
            HStack {
                TextField("Scan or enter barcode", text: $sku)
                    .keyboardType(.asciiCapableNumberPad)
                    .autocorrectionDisabled()
                    .focused($skuFocused)
                    .onSubmit { submitSkuLookup() }

                if !sku.isEmpty {
                    Button { sku = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    skuFocused = false
                    isScannerActive = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Audit: Actions section

    private var actionsSection: some View {
        Section {
            Button {
                submitSkuLookup()
            } label: {
                Label("Look Up SKU / ISBN / UPC", systemImage: "magnifyingglass")
            }
            .disabled(sku.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)

            Button {
                Task { await engine.loadLocation(location) }
            } label: {
                Label("Load Entire Location", systemImage: "tray.full")
            }
            .disabled(location.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        } footer: {
            if engine.scannedSKUs.count > 0 {
                let n = engine.scannedSKUs.count
                Label("\(n) item\(n == 1 ? "" : "s") scanned this session",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Move: Location section

    private var moveLocationSection: some View {
        Section {
            TextField("Destination location", text: $moveLocation)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .focused($moveLocationFocused)
        } header: {
            Text("Destination Location")
        } footer: {
            Text("Location persists between scans until changed.")
        }
    }

    // MARK: - Move: SKU section

    private var moveSkuSection: some View {
        Section("SKU / ISBN / UPC") {
            HStack {
                TextField("Scan or enter barcode", text: $moveSku)
                    .keyboardType(.asciiCapableNumberPad)
                    .autocorrectionDisabled()
                    .focused($moveSkuFocused)
                    .onSubmit { submitMoveItem() }

                if !moveSku.isEmpty {
                    Button { moveSku = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    moveSkuFocused = false
                    isScannerActive = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Move: Actions section

    private var moveActionsSection: some View {
        Section {
            Button {
                submitMoveItem()
            } label: {
                Label("Move to Location", systemImage: "arrow.triangle.turn.up.right.circle")
            }
            .disabled(
                moveSku.trimmingCharacters(in: .whitespaces).isEmpty ||
                moveLocation.trimmingCharacters(in: .whitespaces).isEmpty ||
                isLoading
            )
        }
    }

    // MARK: - Result content (adaptive per engine state)

    @ViewBuilder
    private var resultContent: some View {
        switch engine.state {
        case .idle:
            EmptyView()

        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking up…")
                        .foregroundStyle(.secondary)
                }
            }

        case .notFound:
            Section {
                if engine.lastLoadSkippedCount > 0 {
                    let n = engine.lastLoadSkippedCount
                    Label("All \(n) item\(n == 1 ? "" : "s") in this location were already scanned this session.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    Label("No items found for that entry.", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Button("Clear") {
                    engine.reset()
                    if mode == .move { moveSku = "" } else { sku = "" }
                }
            }

        case .locationPicker(let items):
            locationPickerSection(items: items)

        case .locationMismatch(let results, let itemLocation, let enteredLocation):
            locationMismatchSection(results: results, itemLocation: itemLocation, enteredLocation: enteredLocation)

        case .singleResult(let result):
            Section {
                AuditItemResultView(result: result) {
                    await engine.deleteRetained(id: result.id)
                } onUpdateQty: { qty in
                    await engine.updateQty(id: result.id, qty: qty)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }
            if engine.lastLoadSkippedCount > 0 {
                let n = engine.lastLoadSkippedCount
                Section {
                    Label("\(n) item\(n == 1 ? "" : "s") already scanned this session were skipped.",
                          systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("New Lookup") { engine.reset(); sku = "" }
            }

        case .multiResult(let results):
            ForEach(results) { result in
                Section(result.item.sku) {
                    AuditItemResultView(result: result) {
                        await engine.deleteRetained(id: result.id)
                    } onUpdateQty: { qty in
                        await engine.updateQty(id: result.id, qty: qty)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            if engine.lastLoadSkippedCount > 0 {
                let n = engine.lastLoadSkippedCount
                Section {
                    Label("\(n) item\(n == 1 ? "" : "s") already scanned this session were skipped.",
                          systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("New Lookup") { engine.reset(); sku = "" }
            }

        case .moved(let item, let toLocation):
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Moved to \"\(toLocation)\"")
                            .font(.headline)
                        if !item.title.isEmpty {
                            Text(item.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(item.sku)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                Button("Move Another") { engine.reset(); moveSku = "" }
            }

        case .error(let message):
            Section {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                Button("Dismiss") { engine.reset() }
            }
        }
    }

    // MARK: - Location picker section

    @ViewBuilder
    private func locationPickerSection(items: [AoBClient.AoBItem]) -> some View {
        let locations = Array(Set(items.compactMap { $0.location })).sorted()
        Section {
            ForEach(locations, id: \.self) { loc in
                let locItems  = items.filter { $0.location == loc }
                let totalQty  = locItems.compactMap { $0.qty }.reduce(0, +)
                let isZeroQty = locItems.allSatisfy { ($0.qty ?? 0) == 0 }
                Button {
                    if mode == .move {
                        Task { await engine.confirmMoveFromLocation(loc, items: items, toLocation: moveLocation) }
                    } else {
                        Task { await engine.selectLocation(loc, from: items) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc)
                                .font(.body)
                                .foregroundStyle(.primary)
                            HStack(spacing: 10) {
                                Text("\(locItems.count) item\(locItems.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Label("Qty: \(totalQty)", systemImage: isZeroQty ? "exclamationmark.circle.fill" : "number")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(isZeroQty ? .red : .secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .listRowBackground(isZeroQty ? Color.red.opacity(0.08) : nil)
            }
        } header: {
            Text(mode == .move ? "Select source location to move from" : "Multiple locations — select one")
        } footer: {
            Text("The scanned/entered barcode was found in \(locations.count) different locations.")
        }
        Section {
            Button("Cancel") {
                engine.reset()
                if mode == .move { moveSku = "" } else { sku = "" }
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - Location mismatch section (audit only)

    @ViewBuilder
    private func locationMismatchSection(results: [AuditItemResult],
                                         itemLocation: String,
                                         enteredLocation: String) -> some View {
        Section {
            Label("Location mismatch", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("This item is stored in \"\(itemLocation)\", but your location is set to \"\(enteredLocation)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Section {
            Button {
                Task { await engine.resolveLocationMismatch(keepOriginal: true, results: results, enteredLocation: enteredLocation) }
            } label: {
                Label("Keep \"\(itemLocation)\"", systemImage: "mappin")
            }
            Button {
                Task { await engine.resolveLocationMismatch(keepOriginal: false, results: results, enteredLocation: enteredLocation) }
            } label: {
                Label("Move to \"\(enteredLocation)\"", systemImage: "arrow.triangle.turn.up.right.circle")
            }
        }
        Section {
            Button("Cancel") { engine.reset(); sku = "" }
                .foregroundStyle(.red)
        }
    }

    // MARK: - Scanner sheet

    private var scannerSheet: some View {
        ZStack {
            #if os(iOS)
            if DataScannerViewController.isSupported {
                BarcodeScannerView(isActive: $isCameraScanning) { barcode in
                    if mode == .move {
                        moveSku = barcode
                        isCameraScanning = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            submitMoveItem()
                        }
                    } else {
                        sku = barcode
                        isCameraScanning = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            submitSkuLookup()
                        }
                    }
                }
                .ignoresSafeArea()
                .onAppear  { isCameraScanning = true  }
                .onDisappear { isCameraScanning = false }
            } else {
                cameraUnavailablePlaceholder
            }
            #else
            cameraUnavailablePlaceholder
            #endif

            // Top bar overlay (mode-specific)
            if mode == .move {
                moveScannerTopBar
            } else {
                auditScannerTopBar
            }

            // Result panel
            VStack(spacing: 0) {
                Spacer()
                if !isEngineIdle {
                    scannerResultPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isEngineIdle)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Auto-advance in move mode after a successful move
        .onChange(of: isMovedState) { _, isMoved in
            guard isMoved, mode == .move else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                engine.reset()
                moveSku = ""
                isCameraScanning = true
            }
        }
    }

    // MARK: - Audit scanner top bar

    private var auditScannerTopBar: some View {
        VStack {
            HStack {
                if engine.scannedSKUs.count > 0 {
                    let n = engine.scannedSKUs.count
                    Label("\(n)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.green)
                        .padding(.leading)
                }
                Spacer()
                Button {
                    engine.reset()
                    sku = ""
                    isScannerActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(.primary)
                }
                .padding()
            }
            Spacer()
            if isEngineIdle {
                Text("Point camera at barcode")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 48)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEngineIdle)
    }

    // MARK: - Move scanner top bar

    private var moveScannerTopBar: some View {
        VStack {
            HStack(alignment: .center, spacing: 8) {
                // Location chip / inline editor
                if isMoveLocationEditing {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        TextField("Destination location", text: $moveLocation)
                            .focused($moveLocationFocused)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .font(.subheadline.weight(.semibold))
                            .onSubmit { isMoveLocationEditing = false }
                        Button {
                            isMoveLocationEditing = false
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.leading)
                    .onAppear { moveLocationFocused = true }
                } else {
                    Button {
                        isMoveLocationEditing = true
                    } label: {
                        Label(
                            moveLocation.isEmpty ? "Set location…" : "→ \(moveLocation)",
                            systemImage: "mappin.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(moveLocation.isEmpty ? .orange : .primary)
                    }
                    .padding(.leading)
                }

                Spacer()

                Button {
                    engine.reset()
                    moveSku = ""
                    isMoveLocationEditing = false
                    isScannerActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(.primary)
                }
                .padding(.trailing)
            }
            .padding(.top, 4)

            Spacer()

            if isEngineIdle {
                Group {
                    if moveLocation.isEmpty {
                        Text("Tap the location chip to set a destination")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Point camera at SKU barcode")
                    }
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 48)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEngineIdle)
        .animation(.easeInOut(duration: 0.18), value: isMoveLocationEditing)
    }

    // MARK: - Scanner result panel

    private var scannerResultPanel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                scannerResultContent
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .frame(maxHeight: 500)

            if !isEngineLoading && !isMovedState {
                Divider()
                Button {
                    engine.reset()
                    sku = ""
                    moveSku = ""
                    isCameraScanning = true
                } label: {
                    Label("Scan Next", systemImage: "barcode.viewfinder")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var scannerResultContent: some View {
        switch engine.state {
        case .idle:
            EmptyView()

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Looking up…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)

        case .notFound:
            Label("No items found for that entry.", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .padding(.vertical, 24)

        case .locationPicker(let items):
            scannerLocationPicker(items: items)

        case .locationMismatch(let results, let itemLocation, let enteredLocation):
            scannerLocationMismatch(results: results, itemLocation: itemLocation, enteredLocation: enteredLocation)

        case .singleResult(let result):
            AuditItemResultView(result: result) {
                await engine.deleteRetained(id: result.id)
            } onUpdateQty: { qty in
                await engine.updateQty(id: result.id, qty: qty)
            }
            .padding(.vertical, 4)

        case .multiResult(let results):
            VStack(spacing: 12) {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.item.sku)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        AuditItemResultView(result: result) {
                            await engine.deleteRetained(id: result.id)
                        } onUpdateQty: { qty in
                            await engine.updateQty(id: result.id, qty: qty)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

        case .moved(let item, let toLocation):
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Moved successfully")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }

                HStack(spacing: 16) {
                    Label(item.sku, systemImage: "barcode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(toLocation, systemImage: "mappin.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
            .padding(.vertical, 4)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .font(.subheadline)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Scanner location picker (shared, mode-aware)

    @ViewBuilder
    private func scannerLocationPicker(items: [AoBClient.AoBItem]) -> some View {
        let locations = Array(Set(items.compactMap { $0.location })).sorted()
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .move ? "Select source location to move from" : "Multiple locations — select one")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text("The scanned barcode was found in \(locations.count) locations.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            ForEach(locations, id: \.self) { loc in
                let locItems = items.filter { $0.location == loc }
                let totalQty = locItems.compactMap { $0.qty }.reduce(0, +)
                let isZero   = locItems.allSatisfy { ($0.qty ?? 0) == 0 }
                Button {
                    if mode == .move {
                        Task { await engine.confirmMoveFromLocation(loc, items: items, toLocation: moveLocation) }
                    } else {
                        Task { await engine.selectLocation(loc, from: items) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc).font(.body).foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                Text("\(locItems.count) item\(locItems.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Label("Qty: \(totalQty)",
                                      systemImage: isZero ? "exclamationmark.circle.fill" : "number")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(isZero ? .red : .secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        isZero ? Color.red.opacity(0.08) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
            }
        }
    }

    // MARK: - Scanner location mismatch (audit only)

    @ViewBuilder
    private func scannerLocationMismatch(results: [AuditItemResult],
                                         itemLocation: String,
                                         enteredLocation: String) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.orange)
                Text("Location Mismatch")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            Text("This item is in **\"\(itemLocation)\"**, but your location is set to **\"\(enteredLocation)\"**.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                Button {
                    Task { await engine.resolveLocationMismatch(keepOriginal: true,
                                                               results: results,
                                                               enteredLocation: enteredLocation) }
                } label: {
                    HStack {
                        Image(systemName: "mappin").frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep original location").font(.subheadline.weight(.semibold))
                            Text("\"\(itemLocation)\"").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.primary)

                Button {
                    Task { await engine.resolveLocationMismatch(keepOriginal: false,
                                                               results: results,
                                                               enteredLocation: enteredLocation) }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.circle").frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Move to entered location").font(.subheadline.weight(.semibold))
                            Text("\"\(enteredLocation)\"").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
    }

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Camera not available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var isLoading: Bool {
        if case .loading = engine.state { return true }
        return false
    }

    private var isEngineIdle: Bool {
        if case .idle = engine.state { return true }
        return false
    }

    private var isEngineLoading: Bool {
        if case .loading = engine.state { return true }
        return false
    }

    private var isMovedState: Bool {
        if case .moved = engine.state { return true }
        return false
    }

    private func enqueueQtyAlerts(for newState: AuditEngine.State) {
        var candidates: [(id: UUID, qty: Int, sku: String)] = []
        switch newState {
        case .singleResult(let result):
            if result.verdict == .retain && !result.isDeleted,
               let qty = result.currentQty ?? result.item.qty, qty > 1,
               !qtyAlertedIDs.contains(result.id) {
                candidates.append((result.id, qty, result.item.sku))
            }
        case .multiResult(let results):
            for result in results {
                if result.verdict == .retain && !result.isDeleted,
                   let qty = result.currentQty ?? result.item.qty, qty > 1,
                   !qtyAlertedIDs.contains(result.id) {
                    candidates.append((result.id, qty, result.item.sku))
                }
            }
        default:
            return
        }
        for c in candidates { qtyAlertedIDs.insert(c.id) }
        pendingQtyAlerts.append(contentsOf: candidates)
        if activeQtyAlert == nil { dequeueNextQtyAlert() }
    }

    private func dequeueNextQtyAlert() {
        guard !pendingQtyAlerts.isEmpty else { return }
        let next = pendingQtyAlerts.removeFirst()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            qtyAlertInput = "\(next.qty)"
            activeQtyAlert = next
        }
    }

    private func submitSkuLookup() {
        let trimmed = sku.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        skuFocused = false
        locationFocused = false
        Task { await engine.lookupSku(input: trimmed, location: location) }
    }

    private func submitMoveItem() {
        let trimmedSku = moveSku.trimmingCharacters(in: .whitespaces)
        let trimmedLoc = moveLocation.trimmingCharacters(in: .whitespaces)
        guard !trimmedSku.isEmpty, !trimmedLoc.isEmpty else { return }
        moveSkuFocused = false
        moveLocationFocused = false
        Task { await engine.moveItem(sku: trimmedSku, toLocation: trimmedLoc) }
    }
}

#Preview {
    AuditView()
        .environment(AppSettings.shared)
}
