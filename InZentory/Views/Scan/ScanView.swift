//
//  ScanView.swift
//  InZentory
//

import SwiftUI
import SwiftData

#if os(iOS)
import VisionKit
import AVFoundation
#endif

struct ScanResult: Sendable {
    let barcode: String
    let productData: AoBClient.ProductData?
    let catData: AoBClient.CatData?
}

private enum PartialLookup: Sendable {
    case product(AoBClient.ProductData?)
    case cat(AoBClient.CatData?)
}

struct ScanView: View {
    let onResult: (ScanResult) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isScannerActive = true
    @State private var torchOn = false
    @State private var isLoading = false
    @State private var lookupError: String? = nil
    @State private var scanResult: ScanResult? = nil
    @State private var showManualInput = false
    @State private var manualBarcode = ""
    @FocusState private var manualInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                #if os(iOS)
                if DataScannerViewController.isSupported {
                    BarcodeScannerView(isActive: $isScannerActive) { barcode in
                        Task { await lookup(barcode) }
                    }
                    .ignoresSafeArea(.container)
                } else {
                    cameraUnavailablePlaceholder
                }
                #else
                cameraUnavailablePlaceholder
                #endif

                VStack(spacing: 0) {
                    HStack {
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
                        .padding(.leading)
                        .padding(.top, 8)

                        Spacer()

                        Button {
                            showManualInput.toggle()
                            if showManualInput {
                                isScannerActive = false
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(50))
                                    manualInputFocused = true
                                }
                            } else {
                                isScannerActive = true
                                manualBarcode = ""
                            }
                        } label: {
                            Image(systemName: showManualInput ? "keyboard.chevron.compact.down.fill" : "keyboard")
                                .font(.title3)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(showManualInput ? Color.accentColor : .primary)
                        }
                        .padding(.trailing, 8)
                        .padding(.top, 8)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(.primary)
                        }
                        .padding(.trailing)
                        .padding(.top, 8)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let error = lookupError {
                        Button {
                            lookupError = nil
                            isScannerActive = !showManualInput
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(error)
                                    .lineLimit(2)
                            }
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .padding(.horizontal)
                    }

                    Spacer()

                    if let result = scanResult {
                        ScanResultOverlay(
                            barcode: result.barcode,
                            productData: result.productData,
                            catData: result.catData,
                            onList: { listItem(result) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: scanResult != nil)
                .animation(.spring(duration: 0.3), value: lookupError != nil)
            }

            // Manual input lives outside the camera ZStack so the sheet's
            // keyboard avoidance correctly lifts it above the keyboard.
            if showManualInput {
                HStack(spacing: 8) {
                    TextField("Enter barcode", text: $manualBarcode)
                        .keyboardType(.numberPad)
                        .focused($manualInputFocused)
                        .submitLabel(.search)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .onSubmit { submitManual() }
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                manualInputFocused = true
                            }
                        }

                    Button(action: submitManual) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .disabled(manualBarcode.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showManualInput)
        .onChange(of: isScannerActive) { _, active in
            if !active && torchOn {
                torchOn = false
                setTorch(false)
            }
        }
        .onAppear {
            guard !isLoading else { return }
            isScannerActive = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                isScannerActive = true
            }
        }
    }

    // MARK: - Subviews

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

    // MARK: - Actions

    private func submitManual() {
        let barcode = manualBarcode.trimmingCharacters(in: .whitespaces)
        guard !barcode.isEmpty else { return }
        manualInputFocused = false
        Task { await lookup(barcode) }
    }

    private func lookup(_ barcode: String) async {
        guard !isLoading else { return }
        isScannerActive = false
        isLoading = true
        scanResult = nil
        lookupError = nil
        manualBarcode = ""

        if barcode.uppercased().hasPrefix("X") {
            await lookupFNSKU(barcode)
        } else {
            await lookupConcurrent(barcode)
        }

        isLoading = false
    }

    private func lookupConcurrent(_ barcode: String) async {
        var product: AoBClient.ProductData? = nil
        var cat: AoBClient.CatData? = nil

        do {
            try await withThrowingTaskGroup(of: PartialLookup.self) { group in
                group.addTask { .product(try await AoBClient.shared.productData(for: barcode)) }
                group.addTask { .cat(try await AoBClient.shared.catData(for: barcode)) }

                for try await partial in group {
                    switch partial {
                    case .product(let p): product = p
                    case .cat(let c):     cat = c
                    }
                    scanResult = ScanResult(barcode: barcode, productData: product, catData: cat)
                }
            }
        } catch {
            scanResult = nil
            lookupError = error.localizedDescription
            isScannerActive = true
            return
        }

        let final = ScanResult(barcode: barcode, productData: product, catData: cat)
        if case .list = cat?.verdict() {
            listItem(final)
        } else {
            scanResult = final
            isScannerActive = true
        }
    }

    private func lookupFNSKU(_ fnsku: String) async {
        let cat: AoBClient.CatData?
        do {
            cat = try await AoBClient.shared.catData(for: fnsku)
        } catch {
            lookupError = error.localizedDescription
            isScannerActive = true
            return
        }

        let asin = cat?.asin
        let effectiveID = asin ?? fnsku

        scanResult = ScanResult(barcode: effectiveID, productData: nil, catData: cat)

        let product: AoBClient.ProductData?
        if let asin {
            product = try? await AoBClient.shared.productData(for: asin)
        } else {
            product = nil
        }

        let final = ScanResult(barcode: effectiveID, productData: product, catData: cat)
        if case .list = cat?.verdict() {
            listItem(final)
        } else {
            scanResult = final
            isScannerActive = true
        }
    }

    private func listItem(_ result: ScanResult) {
        onResult(result)
        dismiss()
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
    ScanView(onResult: { _ in })
        .modelContainer(for: ListingItem.self, inMemory: true)
}
