//
//  ScoutHistoryView.swift
//  InZentory
//
//  Shows the last 18 scout scans with cover, title, author, verdict, and timestamp.
//

import SwiftUI

// MARK: - Scan record

struct ScoutScanRecord: Identifiable {
    let id = UUID()
    let barcode: String
    let productData: AoBClient.ProductData?
    let catData: AoBClient.CatData?
    let mode: ScoutMode
    let costEntries: [ScoutCostEntry]   // snapshot at scan time (for Per Item)
    let bagPrice: Double                // snapshot at scan time (for Bag Sale)
    let timestamp: Date

    /// Top-level verdict shown in history list.
    var headlineVerdict: ScoutHeadlineVerdict {
        guard let cat = catData else { return .reject }
        switch mode {
        case .sort:
            switch cat.verdict() {
            case .list:          return .buy
            case .borderline:    return .borderline
            case .reject:        return .reject
            case .noMarketData:  return .reject
            }
        case .perItem:
            return costEntries.contains { cat.buyPrice >= $0.cost } ? .buy : .reject
        case .bagSale:
            return cat.buyPrice >= (bagPrice / 25.0) ? .buy : .reject
        }
    }
}

enum ScoutHeadlineVerdict {
    case buy, borderline, reject

    var label: String {
        switch self {
        case .buy:        return "BUY"
        case .borderline: return "BORDERLINE"
        case .reject:     return "REJECT"
        }
    }

    var color: Color {
        switch self {
        case .buy:        return .green
        case .borderline: return .orange
        case .reject:     return .red
        }
    }

    var systemImage: String {
        switch self {
        case .buy:        return "checkmark.circle.fill"
        case .borderline: return "exclamationmark.triangle.fill"
        case .reject:     return "xmark.circle.fill"
        }
    }
}

// MARK: - History sheet

struct ScoutHistoryView: View {
    let records: [ScoutScanRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No Recent Scans",
                        systemImage: "barcode.viewfinder",
                        description: Text("Scans will appear here as you scout.")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            ScoutHistoryRow(record: record)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - History row

private struct ScoutHistoryRow: View {
    let record: ScoutScanRecord

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            coverImage
                .frame(width: 38, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Title / author / timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    record.productData?.title.isEmpty == false
                        ? record.productData!.title
                        : record.barcode
                )
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

                if let author = record.productData?.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let cat = record.catData {
                    HStack(spacing: 8) {
                        Text(String(format: "Buy $%.2f", cat.buyPrice))
                        Text("·").foregroundStyle(.tertiary)
                        Text(String(format: "Margin $%.2f", cat.abeMargin))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Text(record.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Verdict chip
            let v = record.headlineVerdict
            Label(v.label, systemImage: v.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(v.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(v.color.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var coverImage: some View {
        if let urlStr = record.productData?.imageURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fit)
                default:
                    placeholderRect
                }
            }
        } else {
            placeholderRect
        }
    }

    private var placeholderRect: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
    }
}
