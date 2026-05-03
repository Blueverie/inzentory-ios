//
//  PrintNodeClient.swift
//  InZentory
//

import Foundation
import UIKit
import CoreImage

actor PrintNodeClient {
    static let shared = PrintNodeClient()
    private let baseURL = URL(string: "https://api.printnode.com")!

    // MARK: - Nested types

    struct Printer: Sendable, Identifiable {
        let id: Int
        let name: String
        let description: String
        let online: Bool
        let computerId: Int
        let computerName: String
    }

    enum PrintNodeError: LocalizedError {
        case missingApiKey
        case noPrinterSelected
        case httpError(Int, String)
        case networkError(Error)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return "PrintNode API key not set. Check Settings → Credentials."
            case .noPrinterSelected:
                return "No printer selected. Check Settings → Printing."
            case .httpError(let code, let msg):
                return "PrintNode HTTP \(code): \(msg)"
            case .networkError(let err):
                return err.localizedDescription
            case .parseError(let msg):
                return "PrintNode: \(msg)"
            }
        }
    }

    // MARK: - Public API

    func fetchPrinters() async throws -> [Printer] {
        guard let apiKey = try? await SharedCredentialsService.shared.getPrintNodeKey(),
              !apiKey.isEmpty else { throw PrintNodeError.missingApiKey }

        var request = URLRequest(url: baseURL.appendingPathComponent("printers"))
        request.setValue(basicAuth(apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await fetchData(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PrintNodeError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PrintNodeError.parseError("expected JSON array from /printers")
        }

        return arr.compactMap { d -> Printer? in
            guard let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
            let desc = d["description"] as? String ?? ""
            let computer = d["computer"] as? [String: Any]
            let online = (computer?["state"] as? String) == "connected"
            let computerId = computer?["id"] as? Int ?? 0
            let computerName = computer?["name"] as? String ?? "Unknown"
            return Printer(id: id, name: name, description: desc, online: online,
                           computerId: computerId, computerName: computerName)
        }
    }

    func printSKULabel(
        sku: String,
        title: String,
        author: String,
        asin: String,
        isbn: String,
        upc: String,
        conditionRaw: Int,
        copies: Int = 1,
        printerId: Int,
        format: LabelFormat = .pdf,
        orientation: LabelOrientation = .portrait,
        zplDpi: ZplDpi = .dpi203
    ) async throws {
        guard let apiKey = try? await SharedCredentialsService.shared.getPrintNodeKey(),
              !apiKey.isEmpty else { throw PrintNodeError.missingApiKey }

        let body: [String: Any]

        switch format {
        case .pdf:
            let pdfData = await MainActor.run {
                Self.makeLabelPDFData(sku: sku, title: title, author: author,
                                      asin: asin, isbn: isbn, upc: upc, conditionRaw: conditionRaw,
                                      orientation: orientation)
            }
            body = [
                "printerId":   printerId,
                "title":       "SKU \(sku)",
                "contentType": "pdf_base64",
                "content":     pdfData.base64EncodedString(),
                "source":      "InZentory",
                "qty":         max(1, copies),
                "options":     ["fit_to_page": false, "rotate": 0]
            ]

        case .zpl:
            let zpl = Self.makeZPLString(sku: sku, title: title, author: author,
                                         asin: asin, isbn: isbn, upc: upc,
                                         conditionRaw: conditionRaw, dpi: zplDpi.rawValue)
            body = [
                "printerId":   printerId,
                "title":       "SKU \(sku)",
                "contentType": "raw_base64",
                "content":     Data(zpl.utf8).base64EncodedString(),
                "source":      "InZentory",
                "qty":         max(1, copies)
            ]
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("printjobs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuth(apiKey), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await fetchData(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PrintNodeError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Private

    private func fetchData(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw PrintNodeError.networkError(error)
        }
    }

    private func basicAuth(_ apiKey: String) -> String {
        let encoded = Data("\(apiKey):".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Label PDF

    /// Renders the SKU label as PDF data sized for a DYMO 30334 (2.25" × 1.25").
    /// Uses CGContext directly so the media box is exactly 162×90pt — UIGraphicsPDFRenderer
    /// ignores small bounds and falls back to US Letter.
    @MainActor
    static func makeLabelPDFData(
        sku: String,
        title: String,
        author: String,
        asin: String,
        isbn: String,
        upc: String,
        conditionRaw: Int,
        orientation: LabelOrientation = .portrait
    ) -> Data {
        let condCode: String
        switch conditionRaw {
        case 11:     condCode = "N"
        case 1, 5:   condCode = "L"
        case 2, 6:   condCode = "V"
        case 3, 7:   condCode = "G"
        case 4, 8:   condCode = "A"
        default:     condCode = ""
        }

        let pid = !isbn.isEmpty ? isbn : (!upc.isEmpty ? upc : asin)

        // DYMO 30334: 2.25" × 1.25". The drawing canvas is always 162×90 UIKit points
        // (landscape). Two PDF page orientations are supported:
        //
        //  .portrait  — 90×162pt page, content swapped onto the page with a 90° rotation.
        //               Prints correctly on Mac DYMO drivers (default).
        //
        //  .landscape — 162×90pt page, content drawn with a standard UIKit y-flip.
        //               Use when the portrait PDF prints sideways on Windows DYMO drivers.
        let pageW: CGFloat = orientation == .portrait ? 90  : 162
        let pageH: CGFloat = orientation == .portrait ? 162 : 90
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        ctx.beginPDFPage(nil)
        UIGraphicsPushContext(ctx)

        switch orientation {
        case .portrait:
            // Maps the 162×90 UIKit canvas onto the 90×162 portrait page:
            //   CG_x = y_u,  CG_y = x_u  (swaps axes)
            ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
        case .landscape:
            // Standard UIKit y-flip: origin at top-left, y increases downward.
            ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: pageH))
        }

        // Barcode — taller, margin halved vs original DYMO template
        if let barcodeImg = makeBarcodeImage(for: sku) {
            barcodeImg.draw(in: CGRect(x: 3, y: 3, width: 156, height: 44))
        }

        // Font: Inconsolata has a slashed zero; fall back to Menlo (also slashed zero) then system mono
        let font9 = UIFont(name: "Inconsolata", size: 9)
                 ?? UIFont(name: "Menlo-Regular", size: 9)
                 ?? UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let font8 = UIFont(name: "Inconsolata", size: 8)
                 ?? UIFont(name: "Menlo-Regular", size: 8)
                 ?? UIFont.monospacedSystemFont(ofSize: 8, weight: .regular)

        func attrs(_ font: UIFont, alignment: NSTextAlignment, clip: Bool = true) -> [NSAttributedString.Key: Any] {
            let ps = NSMutableParagraphStyle()
            ps.alignment = alignment
            ps.lineBreakMode = clip ? .byClipping : .byTruncatingTail
            return [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: ps]
        }

        // Layout constants (all in the 162×90 UIKit canvas, y from top)
        let lx: CGFloat = 7.2          // left margin — SKU aligns with title/author
        let rx: CGFloat = 154.8        // right margin edge
        let rowY: CGFloat = 49         // row 1 top (barcode 44pt + 2pt gap + 3pt top margin)
        let rowH: CGFloat = 12
        let titleY: CGFloat = rowY + rowH + 1   // 62
        let authorY: CGFloat = titleY + 9       // 71 — tighter than original 13.68pt spacing

        // Row 1: SKU (left) | Condition (centered in gap or full width) | PID (right)
        let skuAttrs  = attrs(font9, alignment: .left)
        let pidAttrs  = attrs(font9, alignment: .right)
        let condAttrs = attrs(font9, alignment: .center)

        let skuW: CGFloat = 72        // max SKU column width
        let pidW: CGFloat = 72        // wide enough for ISBN-13 at Menlo 9pt (~5.4pt/char × 13 = 70pt)
        let pidX = rx - pidW

        (sku as NSString).draw(in: CGRect(x: lx, y: rowY, width: skuW, height: rowH),
                               withAttributes: skuAttrs)

        if pid.isEmpty {
            // No product ID — center condition across the full label width
            (condCode as NSString).draw(in: CGRect(x: lx, y: rowY, width: rx - lx, height: rowH),
                                        withAttributes: condAttrs)
        } else {
            // Normal: condition centered in the gap between SKU and PID texts
            let skuMeasured = min((sku as NSString).size(withAttributes: skuAttrs).width, skuW)
            let pidMeasured = min((pid as NSString).size(withAttributes: pidAttrs).width, pidW)
            let skuRight  = lx + skuMeasured
            let pidLeft   = rx - pidMeasured
            let condCX    = (skuRight + pidLeft) / 2
            let condW: CGFloat = 10

            (condCode as NSString).draw(in: CGRect(x: condCX - condW / 2, y: rowY, width: condW, height: rowH),
                                        withAttributes: condAttrs)
            (pid as NSString).draw(in: CGRect(x: pidX, y: rowY, width: pidW, height: rowH),
                                   withAttributes: pidAttrs)
        }

        // Title and author — clipped (no ellipsis), tighter line spacing
        (title as NSString).draw(in: CGRect(x: lx, y: titleY,  width: rx - lx, height: 9),
                                 withAttributes: attrs(font8, alignment: .left))
        (author as NSString).draw(in: CGRect(x: lx, y: authorY, width: rx - lx, height: 9),
                                  withAttributes: attrs(font8, alignment: .left))

        UIGraphicsPopContext()
        ctx.endPDFPage()
        ctx.closePDF()

        return pdfData as Data
    }

    // MARK: - Label ZPL

    /// Generates ZPL for a Zebra printer matching the DYMO label layout (2.25" × 1.25").
    /// Coordinates are derived by converting the 162×90pt PDF canvas at the given DPI.
    static func makeZPLString(
        sku: String,
        title: String,
        author: String,
        asin: String,
        isbn: String,
        upc: String,
        conditionRaw: Int,
        dpi: Int = 203
    ) -> String {
        let condCode: String
        switch conditionRaw {
        case 11:     condCode = "N"
        case 1, 5:   condCode = "L"
        case 2, 6:   condCode = "V"
        case 3, 7:   condCode = "G"
        case 4, 8:   condCode = "A"
        default:     condCode = ""
        }

        let pid = !isbn.isEmpty ? isbn : (!upc.isEmpty ? upc : asin)

        // Convert PDF UIKit points (72pt/inch) → ZPL dots at the target DPI.
        // The PDF drawing canvas is always 162×90pt (landscape 2.25"×1.25").
        func d(_ pt: Double) -> Int { Int((pt * Double(dpi) / 72.0).rounded()) }

        let labelW  = d(162)    // print width in dots
        let labelH  = d(90)     // label length in dots
        let font9H  = d(9)      // cell height for 9pt fields
        let font8H  = d(8)      // cell height for 8pt fields
        let font9W  = font9H
        let font8W  = font8H

        // Use a larger top margin and a tighter barcode/text gap for Zebra labels.
        let barcodeY = font9H
        let barcodeH = d(44)
        let barcodeTextGap = max(1, font9H / 2)
        let rowY     = barcodeY + barcodeH + barcodeTextGap
        let titleY   = rowY + font9H + 1
        let authorY  = titleY + font8H + 1
        let lx       = d(7.2)    // left text margin
        let rx       = d(154.8)  // right text margin edge
        let fieldW   = rx - lx   // usable field width from lx to rx
        let pidW     = d(72)
        let pidBoxX  = rx - pidW
        let condW    = max(font9W, d(6))

        // Narrow bar width: 2 dots at 203 DPI, 3 dots at 300 DPI
        let narrowBar = dpi >= 300 ? 3 : 2

        // Strip ZPL control characters from field data
        func z(_ s: String) -> String { s.filter { $0 != "^" && $0 != "~" } }

        func textWidth(_ text: String, charWidth: Int, maxWidth: Int? = nil) -> Int {
            let measured = text.count * charWidth
            if let maxWidth {
                return min(measured, maxWidth)
            }
            return measured
        }

        func clippedLine(_ text: String, charWidth: Int, fieldWidth: Int) -> String {
            guard !text.isEmpty, charWidth > 0, fieldWidth > 0 else { return "" }
            let maxChars = max(1, fieldWidth / charWidth)
            return String(text.prefix(maxChars))
        }

        // Code 128 width in modules: 11 per symbol, plus start/checksum/stop.
        let barcodeModules = max(0, (sku.count * 11) + 35)
        let barcodeW = barcodeModules * narrowBar
        let barcodeX = max(d(3), (labelW - barcodeW) / 2)

        print(
            "[ZPL Layout] sku=\(sku) dpi=\(dpi) labelW=\(labelW) barcodeW=\(barcodeW) barcodeX=\(barcodeX)"
        )

        let skuMeasured = textWidth(sku, charWidth: font9W, maxWidth: pidW)
        let clippedTitle = clippedLine(title, charWidth: font8W, fieldWidth: fieldW)
        let clippedAuthor = clippedLine(author, charWidth: font8W, fieldWidth: fieldW)
        let condX: Int = {
            if pid.isEmpty {
                return lx + ((fieldW - condW) / 2)
            }
            let skuRight = lx + skuMeasured
            let condCenter = (skuRight + pidBoxX) / 2
            return max(lx, min(rx - condW, condCenter - (condW / 2)))
        }()

        var lines: [String] = []
        lines.append("^XA")
        lines.append("^LH0,0")
        lines.append("^LT0")
        lines.append("^PW\(labelW)")
        lines.append("^LL\(labelH)")
        lines.append("^CI28")   // UTF-8 encoding

        // Code 128 barcode (no human-readable line — we print our own text below)
        lines.append("^FO\(barcodeX),\(barcodeY)^BY\(narrowBar)^BCN,\(barcodeH),N,N,N^FD\(z(sku))^FS")

        // Row 1: SKU (left), condition (between SKU and PID), PID (right)
        lines.append("^FO\(lx),\(rowY)^A0N,\(font9H),\(font9W)^FB\(fieldW),1,0,L,0^FD\(z(sku))^FS")
        if !condCode.isEmpty {
            lines.append("^FO\(condX),\(rowY)^A0N,\(font9H),\(font9W)^FD\(condCode)^FS")
        }
        if !pid.isEmpty {
            lines.append("^FO\(pidBoxX),\(rowY)^A0N,\(font9H),\(font9W)^FB\(pidW),1,0,R,0^FD\(z(pid))^FS")
        }

        // Title and author are pre-clipped to a single line to avoid Zebra reflow/overprint.
        if !clippedTitle.isEmpty {
            lines.append("^FO\(lx),\(titleY)^A0N,\(font8H),\(font8W)^FD\(z(clippedTitle))^FS")
        }
        if !clippedAuthor.isEmpty {
            lines.append("^FO\(lx),\(authorY)^A0N,\(font8H),\(font8W)^FD\(z(clippedAuthor))^FS")
        }

        lines.append("^XZ")
        return lines.joined(separator: "\n")
    }

    /// Generates a Code128 barcode image scaled to ~300 DPI for the barcode area width.
    private static func makeBarcodeImage(for string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator"),
              let data = string.data(using: .ascii) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        guard let ciImage = filter.outputImage else { return nil }

        // CICode128BarcodeGenerator outputs 1px per bar module; scale up so the raster
        // image is ~300 DPI when rendered into the 156pt-wide barcode area on the PDF.
        // 156pt at 300 DPI = 650px; native width is typically 40-100px, so scale ≈ 8×.
        let targetWidth: CGFloat = 650
        let scale = targetWidth / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
