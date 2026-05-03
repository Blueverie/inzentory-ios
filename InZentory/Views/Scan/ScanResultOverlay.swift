//
//  ScanResultOverlay.swift
//  InZentory
//

import SwiftUI

struct ScanResultOverlay: View {
    let barcode: String
    let productData: AoBClient.ProductData?
    let catData: AoBClient.CatData?
    let onList: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            productHeader

            if let cat = catData {
                Divider()
                statsRow(cat)
                verdictBanner(cat)
            } else {
                Divider()
                Text("No catalog data available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            actionButton
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
            statCell(
                label: "Rank",
                value: rankLabel,
                trend: cat.rankTrend,
                higherIsBetter: false
            )

            Divider().frame(height: 36)

            statCell(
                label: "Buy Price",
                value: String(format: "$%.2f", cat.buyPrice),
                trend: cat.priceTrend,
                higherIsBetter: true,
                secondary: cat.high14Price > cat.buyPrice ? String(format: "hi $%.2f", cat.high14Price) : nil
            )

            Divider().frame(height: 36)

            statCell(
                label: "Margin",
                value: String(format: "$%.2f", cat.abeMargin),
                trend: .neutral,
                higherIsBetter: true
            )
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
                Text(value)
                    .font(.callout.weight(.medium))
                trendIcon(trend, higherIsBetter: higherIsBetter)
                    .font(.caption2.weight(.bold))
            }
            // Reserve height for secondary label to keep layout stable
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
            // Rank improving = number went down (↓ green); price improving = went up (↑ green)
            Image(systemName: higherIsBetter ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .foregroundStyle(Color.green)
        case .worsening:
            Image(systemName: higherIsBetter ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .foregroundStyle(Color.red)
        case .neutral:
            EmptyView()
        }
    }

    // MARK: - Verdict banner

    @ViewBuilder
    private func verdictBanner(_ cat: AoBClient.CatData) -> some View {
        switch cat.verdict() {
        case .list(let minCond):
            verdictLabel("LIST", systemImage: "checkmark.circle.fill", color: .green,
                         detail: minCond.map { "\($0) or better" })
        case .borderline(let minCond):
            verdictLabel(
                "BORDERLINE",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange,
                detail: minCond.map { "\($0) or better" }
            )
        case .reject:
            verdictLabel("REJECT", systemImage: "xmark.circle.fill", color: .red, detail: nil)
        case .noMarketData:
            verdictLabel("NO MARKET DATA", systemImage: "questionmark.circle.fill", color: .secondary, detail: nil)
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

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch catData?.verdict() {
        case .some(.reject):
            Button(action: onList) {
                Label("Override", systemImage: "exclamationmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        case .some(.noMarketData), .none:
            Button(action: onList) {
                Label("List Anyway", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        default:
            Button(action: onList) {
                Label("List", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Previews

private func mockProduct() -> AoBClient.ProductData {
    AoBClient.ProductData(
        asin: "0743518209",
        title: "The Blue Nowhere",
        imageURL: "https://m.media-amazon.com/images/I/514GTN0109L.jpg",
        author: "Deaver, Jeffery",
        publisher: nil,
        releaseDate: nil,
        media: "audioCD",
        weight: nil
    )
}

private func previewOverlay(abeMargin: Double, amzMargin: Double = 0, minMargin: Double) -> some View {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ScanResultOverlay(
                barcode: "0743518209",
                productData: mockProduct(),
                catData: AoBClient.CatData(
                    asin: "0743518209",
                    upc: nil,
                    salesRank: 1099,
                    salesRankHistory: [
                        1_770_269_589: 646,
                        1_770_334_522: 382,
                        1_771_957_165: 615,
                    ],
                    buyPrice: 3.0,
                    buyPriceHistory: [
                        1_770_269_589: 4.25,
                        1_770_334_522: 4.25,
                        1_771_957_165: 4.0,
                    ],
                    abeMargin: abeMargin,
                    amzMargin: amzMargin,
                    minMargin: minMargin
                ),
                onList: {}
            )
        }
    }
}

#Preview("LIST") { previewOverlay(abeMargin: 8.75, minMargin: 0.011) }
#Preview("BORDERLINE – Good") { previewOverlay(abeMargin: 6.0, minMargin: 8.0) }
#Preview("BORDERLINE – no cond") { previewOverlay(abeMargin: 0.5, minMargin: 8.0) }
#Preview("REJECT") { previewOverlay(abeMargin: -1.0, minMargin: 0.011) }
