//
//  ScoutResultOverlay.swift
//  InZentory
//
//  Scout-specific result overlay. Supports three modes:
//  • Sort     — same verdict algorithm as the List tab; "LIST" label becomes "BUY"
//  • Per Item — shows a Buy/Reject row for each named cost entry
//  • Bag Sale — divides bag price by 25, shows a single Buy/Reject
//

import SwiftUI

struct ScoutResultOverlay: View {
    let barcode: String
    let productData: AoBClient.ProductData?
    let catData: AoBClient.CatData?
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            productHeader

            if let cat = catData {
                Divider()
                statsRow(cat)
                Divider()
                verdictSection(cat)
            } else {
                Divider()
                Text("No catalog data available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Product header

    @ViewBuilder
    private var productHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            if let urlStr = productData?.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    default:
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 72)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(productData?.title.isEmpty == false ? productData!.title : barcode)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                if let author = productData?.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let media = productData?.media, !media.isEmpty {
                    Text(media)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Stats row

    @ViewBuilder
    private func statsRow(_ cat: AoBClient.CatData) -> some View {
        HStack(spacing: 0) {
            let rankLabel = cat.salesRank == 999_999_999 ? "None" : cat.salesRank.formatted()
            statCell(label: "Rank",      value: rankLabel,
                     trend: cat.rankTrend,  higherIsBetter: false)

            Divider().frame(height: 36)

            statCell(
                label: "Buy Price",
                value: String(format: "$%.2f", cat.buyPrice),
                trend: cat.priceTrend,
                higherIsBetter: true,
                secondary: cat.high14Price > cat.buyPrice
                    ? String(format: "hi $%.2f", cat.high14Price) : nil
            )

            Divider().frame(height: 36)

            statCell(label: "Margin",    value: String(format: "$%.2f", cat.abeMargin),
                     trend: .neutral,        higherIsBetter: true)
        }
    }

    private func statCell(
        label: String,
        value: String,
        trend: AoBClient.Trend,
        higherIsBetter: Bool,
        secondary: String? = nil
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(value).font(.callout.weight(.medium))
                trendIcon(trend, higherIsBetter: higherIsBetter)
                    .font(.caption2.weight(.bold))
            }
            Text(secondary ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func trendIcon(_ trend: AoBClient.Trend, higherIsBetter: Bool) -> some View {
        switch trend {
        case .improving:
            Image(systemName: higherIsBetter ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .foregroundStyle(Color.green)
        case .worsening:
            Image(systemName: higherIsBetter ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .foregroundStyle(Color.red)
        case .neutral:
            EmptyView()
        }
    }

    // MARK: - Verdict section (mode-dependent)

    @ViewBuilder
    private func verdictSection(_ cat: AoBClient.CatData) -> some View {
        switch settings.scoutMode {
        case .sort:
            sortVerdict(cat)
        case .perItem:
            perItemVerdicts(cat)
        case .bagSale:
            bagSaleVerdict(cat)
        }
    }

    // Sort: same logic as List tab, "LIST" → "BUY"
    @ViewBuilder
    private func sortVerdict(_ cat: AoBClient.CatData) -> some View {
        switch cat.verdict() {
        case .list(let minCond):
            verdictLabel("BUY", systemImage: "checkmark.circle.fill", color: .green,
                         detail: minCond.map { "\($0) or better" })
        case .borderline(let minCond):
            verdictLabel("BORDERLINE", systemImage: "exclamationmark.triangle.fill", color: .orange,
                         detail: minCond.map { "\($0) or better" })
        case .reject:
            verdictLabel("REJECT", systemImage: "xmark.circle.fill", color: .red, detail: nil)
        case .noMarketData:
            verdictLabel("NO MARKET DATA", systemImage: "questionmark.circle.fill", color: .secondary, detail: nil)
        }
    }

    // Per Item: one Buy/Reject row per cost entry
    @ViewBuilder
    private func perItemVerdicts(_ cat: AoBClient.CatData) -> some View {
        if settings.scoutCostEntries.isEmpty {
            Text("No cost entries. Add them in Scout settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(settings.scoutCostEntries) { entry in
                    let isBuy = cat.buyPrice >= entry.cost
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.label.isEmpty ? "Item" : entry.label)
                                .font(.subheadline.weight(.medium))
                            Text(String(format: "$%.2f cost", entry.cost))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: isBuy ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text(isBuy ? "BUY" : "REJECT")
                                .fontWeight(.bold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(isBuy ? .green : .red)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isBuy ? Color.green : Color.red).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // Bag Sale: bag price ÷ 25 = per-book threshold
    @ViewBuilder
    private func bagSaleVerdict(_ cat: AoBClient.CatData) -> some View {
        let threshold = settings.scoutBagPrice / 25.0
        let isBuy     = cat.buyPrice >= threshold

        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(String(format: "Bag $%.2f", settings.scoutBagPrice))
                    .fontWeight(.medium)
                Text("÷ 25 =")
                Text(String(format: "$%.2f per book", threshold))
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            verdictLabel(
                isBuy ? "BUY" : "REJECT",
                systemImage: isBuy ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: isBuy ? .green : .red,
                detail: nil
            )
        }
    }

    private func verdictLabel(_ text: String, systemImage: String, color: Color, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text).fontWeight(.bold)
            if let detail {
                Text("·").foregroundStyle(color.opacity(0.6))
                Text(detail).font(.caption).foregroundStyle(color.opacity(0.8))
            }
        }
        .font(.subheadline)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

}
