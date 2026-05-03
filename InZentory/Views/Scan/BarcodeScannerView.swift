//
//  BarcodeScannerView.swift
//  InZentory
//

#if os(iOS)
import SwiftUI
import Vision
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var isActive: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [
                .ean13, .ean8, .upce,
                .code128, .code39, .code93,
                .itf14, .pdf417, .dataMatrix, .aztec,
                .i2of5, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited
            ])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if isActive {
            guard !scanner.isScanning else { return }
            try? scanner.startScanning()
        } else {
            scanner.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        nonisolated func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let item = addedItems.first,
                  case .barcode(let barcode) = item
            else { return }
            let payload = barcode.payloadStringValue ?? ""
            Task { @MainActor in
                dataScanner.stopScanning()
                onScan(payload)
            }
        }
    }
}
#endif
