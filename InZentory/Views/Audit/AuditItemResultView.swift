//
//  AuditItemResultView.swift
//  InZentory
//

import SwiftUI

/// A self-contained result card for a single audited item.
/// Designed to sit inside a Form `Section` as a single row
/// (use `.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)` at the call site).
struct AuditItemResultView: View {

    let result: AuditItemResult
    /// Called when the user taps "Delete" on a retained item.
    let onDelete: () async -> Void
    /// Called when the user confirms a new quantity. Receives the new qty value.
    let onUpdateQty: (Int) async -> Void

    @Environment(AppSettings.self) private var settings

    @State private var isPrinting     = false
    @State private var isDeleting     = false
    @State private var isUpdatingQty  = false
    @State private var showQtyAlert   = false
    @State private var qtyAlertInput  = ""
    @State private var printError: String?

    private var effectivelyDeleted: Bool {
        result.verdict == .autoDeleted || result.isDeleted
    }

    // MARK: - Body

    private var cardAccentColor: Color { effectivelyDeleted ? .red : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            verdictBanner
            Divider()
            headerRow
            Divider()
            detailRows
            Divider()
            marginRows

            if result.verdict == .retain && !result.isDeleted {
                Divider()
                actionRow
            }

            if let err = printError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
        }
        .background(cardAccentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(cardAccentColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            coverImage
            VStack(alignment: .leading, spacing: 3) {
                Text(result.item.title.isEmpty ? "(No title)" : result.item.title)
                    .font(.headline)
                    .lineLimit(2)
                if let author = result.item.author,
                   !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(author.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let media = result.item.media, !media.isEmpty {
                    Text(media)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
    }

    // MARK: - Detail rows

    private var detailRows: some View {
        VStack(spacing: 0) {
            kvRow("SKU", result.item.sku)
            let displayLocation = result.effectiveLocation ?? result.item.location
            if let loc = displayLocation, !loc.isEmpty {
                Divider().padding(.leading)
                kvRow("Location", loc +
                      (result.effectiveLocation != nil && result.effectiveLocation != result.item.location
                       ? " ↑ moved" : ""))
            }
            if let condRaw = result.item.conditionRaw,
               let cond = ItemCondition(rawValue: condRaw) {
                Divider().padding(.leading)
                kvRow("Condition", cond.displayName)
            }
            if let price = result.item.price, !price.isEmpty {
                Divider().padding(.leading)
                kvRow("Price", "$\(price)")
            }
            let displayQty = result.currentQty ?? result.item.qty
            if let qty = displayQty {
                Divider().padding(.leading)
                kvRow("Qty on Hand", "\(qty)")
            }
        }
    }

    // MARK: - Margin rows

    private var marginRows: some View {
        VStack(spacing: 0) {
            if let cat = result.catData {
                coloredMarginRow("AMZ Margin", cat.amzMargin)
                Divider().padding(.leading)
                coloredMarginRow("ABE Margin", cat.abeMargin)
                if cat.salesRank < 999_999_998 {
                    Divider().padding(.leading)
                    kvRow("Sales Rank", cat.salesRank.formatted())
                }
            } else {
                HStack {
                    Text("Margin data unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Verdict banner

    private var verdictBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: effectivelyDeleted ? "trash.fill" : "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
            Text(verdictText)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(effectivelyDeleted ? .red : .green)
        .padding()
        .background((effectivelyDeleted ? Color.red : Color.green).opacity(0.12))
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 0) {
            if settings.selectedPrinterId > 0 {
                Button {
                    Task { await doPrint() }
                } label: {
                    Label(isPrinting ? "Printing…" : "Print Label",
                          systemImage: isPrinting ? "hourglass" : "printer")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderless)
                .disabled(isPrinting || isDeleting || isUpdatingQty)

                Divider().frame(height: 36)
            }

            Button {
                qtyAlertInput = "\(result.currentQty ?? result.item.qty ?? 1)"
                showQtyAlert = true
            } label: {
                Label(isUpdatingQty ? "Updating…" : "Update Qty",
                      systemImage: isUpdatingQty ? "hourglass" : "number.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderless)
            .disabled(isDeleting || isPrinting || isUpdatingQty)
            .alert("Update Quantity", isPresented: $showQtyAlert) {
                TextField("Quantity", text: $qtyAlertInput)
                    .keyboardType(.numberPad)
                Button("Update") {
                    guard let qty = Int(qtyAlertInput), qty >= 0 else { return }
                    Task {
                        isUpdatingQty = true
                        await onUpdateQty(qty)
                        isUpdatingQty = false
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let qty = result.currentQty ?? result.item.qty
                if let q = qty {
                    Text("Current quantity on hand: \(q). Enter a new value to update.")
                } else {
                    Text("Enter the quantity on hand for this item.")
                }
            }

            Divider().frame(height: 36)

            Button {
                Task {
                    isDeleting = true
                    await onDelete()
                    isDeleting = false
                }
            } label: {
                Label(isDeleting ? "Deleting…" : "Delete",
                      systemImage: isDeleting ? "hourglass" : "trash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderless)
            .disabled(isDeleting || isPrinting || isUpdatingQty)
        }
    }

    // MARK: - Cover image

    private var coverImage: some View {
        Group {
            if let urlStr = result.item.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 52, height: 52)
            .overlay(
                Image(systemName: "book.closed")
                    .foregroundStyle(.tertiary)
            )
    }

    // MARK: - Helpers

    private func kvRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
    }

    private func coloredMarginRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "$%.2f", value))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(value < 0 ? .red : .primary)
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
    }

    private var verdictText: String {
        switch (result.verdict, result.isDeleted) {
        case (.autoDeleted, _): return "Deleted — both margins negative"
        case (.retain, true):   return "Deleted"
        case (.retain, false):  return "Retained"
        }
    }

    // MARK: - Print

    private func doPrint() async {
        isPrinting = true
        printError = nil
        defer { isPrinting = false }
        do {
            try await PrintNodeClient.shared.printSKULabel(
                sku:          result.item.sku,
                title:        result.item.title,
                author:       result.item.author ?? "",
                asin:         result.item.asin  ?? "",
                isbn:         result.item.isbn  ?? "",
                upc:          result.item.upc   ?? "",
                conditionRaw: result.item.conditionRaw ?? 3,
                copies:       1,
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
