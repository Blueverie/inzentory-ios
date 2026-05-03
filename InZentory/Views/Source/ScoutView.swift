//
//  ScoutView.swift
//  InZentory
//
//  Full-screen scout scanner. Shares the same AoB lookup backend and
//  result overlay look as the List tab, but:
//  • Never navigates to the List tab — always stays on this screen
//  • Shows Buy / Reject / Borderline verdicts (mode-dependent)
//  • Maintains a permanent barcode field that captures camera scans,
//    hardware barcode scanners (Bluetooth keyboard emulation), or manual input
//  • Keeps a rolling history of the last 18 scans
//

import SwiftUI
import SwiftData

#if os(iOS)
import VisionKit
import AVFoundation
#endif

// Local re-declaration of the partial-lookup helper (private to this file)
private enum ScoutPartialLookup: Sendable {
    case product(AoBClient.ProductData?)
    case cat(AoBClient.CatData?)
}

struct ScoutView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var isScannerActive = true
    @State private var torchOn         = false
    @State private var isLoading       = false
    @State private var lookupError: String?   = nil
    @State private var scanResult: ScanResult? = nil

    @State private var history: [ScoutScanRecord] = []
    @State private var showHistory  = false
    @State private var showSettings = false

    // Barcode field
    @State private var barcodeText  = ""
    @State private var showKeypad   = false

    var body: some View {
        ZStack {
            // Camera background
            #if os(iOS)
            if DataScannerViewController.isSupported {
                BarcodeScannerView(isActive: $isScannerActive) { barcode in
                    Task { await lookup(barcode) }
                }
                .ignoresSafeArea()
            } else {
                cameraUnavailablePlaceholder
            }
            #else
            cameraUnavailablePlaceholder
            #endif

            VStack(spacing: 0) {
                topBar
                barcodeFieldBar

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if let error = lookupError {
                    errorBanner(error)
                }

                Spacer()

                if let result = scanResult {
                    ScoutResultOverlay(
                        barcode: result.barcode,
                        productData: result.productData,
                        catData: result.catData,
                        settings: settings
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: scanResult != nil)
            .animation(.spring(duration: 0.3), value: lookupError != nil)
        }
        .onChange(of: isScannerActive) { _, active in
            if !active && torchOn { torchOn = false; setTorch(false) }
        }
        .onAppear { restartScanner() }
        .sheet(isPresented: $showHistory) {
            ScoutHistoryView(records: history)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { ScoutSettingsView() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Close
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.primary)
            }

            // Torch
            Button {
                torchOn.toggle()
                setTorch(torchOn)
            } label: {
                Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(torchOn ? .yellow : .primary)
            }

            Spacer()

            // Mode badge
            Text(settings.scoutMode.displayName.uppercased())
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.primary)

            Spacer()

            // History
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.primary)
            }

            // Settings
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Barcode field bar

    private var barcodeFieldBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "barcode")
                .foregroundStyle(.secondary)
                .font(.callout)

            #if os(iOS)
            HardwareScannerTextField(
                text: $barcodeText,
                showKeyboard: showKeypad,
                onSubmit: submitBarcodeField
            )
            .frame(height: 36)
            #else
            TextField("Barcode / ID", text: $barcodeText)
                .textFieldStyle(.plain)
                .onSubmit { submitBarcodeField() }
            #endif

            if !barcodeText.isEmpty {
                Button { barcodeText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            // Toggle keypad / hardware-scanner mode
            Button {
                showKeypad.toggle()
            } label: {
                Image(systemName: showKeypad ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.callout)
                    .foregroundStyle(showKeypad ? .blue : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        Button {
            lookupError = nil
            isScannerActive = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(message).lineLimit(2)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
        }
        .padding(.horizontal)
    }

    // MARK: - Camera unavailable

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            Text("Camera not available on this device")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lookup

    private func submitBarcodeField() {
        let trimmed = barcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await lookup(trimmed) }
    }

    private func lookup(_ barcode: String) async {
        guard !isLoading else { return }
        isScannerActive = false
        isLoading       = true
        scanResult      = nil
        lookupError     = nil
        barcodeText     = barcode

        var product: AoBClient.ProductData? = nil
        var cat:     AoBClient.CatData?     = nil
        let effectiveBarcode: String

        if barcode.uppercased().hasPrefix("X") {
            // FNSKU path
            do {
                cat = try await AoBClient.shared.catData(for: barcode)
            } catch {
                lookupError = error.localizedDescription
                isScannerActive = true
                isLoading = false
                return
            }
            let asin = cat?.asin
            effectiveBarcode = asin ?? barcode
            if let asin {
                product = try? await AoBClient.shared.productData(for: asin)
            }
        } else {
            effectiveBarcode = barcode
            do {
                try await withThrowingTaskGroup(of: ScoutPartialLookup.self) { group in
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
                lookupError = error.localizedDescription
                isScannerActive = true
                isLoading = false
                return
            }
        }

        isLoading       = false
        scanResult      = ScanResult(barcode: effectiveBarcode, productData: product, catData: cat)
        isScannerActive = true

        // Append to history (keep newest first, cap at 18)
        let record = ScoutScanRecord(
            barcode:      effectiveBarcode,
            productData:  product,
            catData:      cat,
            mode:         settings.scoutMode,
            costEntries:  settings.scoutCostEntries,
            bagPrice:     settings.scoutBagPrice,
            timestamp:    Date()
        )
        history.insert(record, at: 0)
        if history.count > 18 { history = Array(history.prefix(18)) }
    }

    private func clearResult() {
        scanResult  = nil
        barcodeText = ""
        isScannerActive = true
    }

    private func restartScanner() {
        guard !isLoading else { return }
        isScannerActive = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            isScannerActive = true
        }
    }

    private func setTorch(_ on: Bool) {
        #if os(iOS)
        Task.detached(priority: .userInitiated) {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {}
        }
        #endif
    }
}

#Preview {
    ScoutView()
        .environment(AppSettings.shared)
}
