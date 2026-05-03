//
//  VerdictBanner.swift
//  InZentory
//

import SwiftUI

/// Compact scan-result banner shown at the top of the List form.
struct VerdictBanner: View {
    let cat: AoBClient.CatData

    private var verdict: AoBClient.ListingVerdict { cat.verdict() }

    var body: some View {
        VStack(spacing: 6) {
            // Stats row
            HStack(spacing: 0) {
                statCell(
                    label: "Rank",
                    value: cat.salesRank == 999_999_999 ? "None" : cat.salesRank.formatted(),
                    trend: cat.rankTrend,
                    higherIsBetter: false
                )
                Divider().frame(height: 28)
                statCell(
                    label: "Buy Price",
                    value: String(format: "$%.2f", cat.buyPrice),
                    trend: cat.priceTrend,
                    higherIsBetter: true
                )
                Divider().frame(height: 28)
                statCell(
                    label: "Margin",
                    value: String(format: "$%.2f", max(cat.abeMargin, cat.amzMargin)),
                    trend: .neutral,
                    higherIsBetter: true
                )
            }

            // Verdict pill
            verdictPill
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(verdictColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(verdictColor.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var verdictPill: some View {
        HStack(spacing: 5) {
            Image(systemName: verdictIcon)
            Text(verdictLabel).fontWeight(.semibold)
            let condRec: String? = {
                switch verdict {
                case .list(let c), .borderline(let c): return c
                case .reject, .noMarketData: return nil
                }
            }()
            if let cond = condRec {
                Text("· \(cond) or better")
                    .foregroundStyle(verdictColor.opacity(0.8))
            }
        }
        .font(.caption)
        .foregroundStyle(verdictColor)
    }

    private var verdictColor: Color {
        switch verdict {
        case .list:          return .green
        case .borderline:    return .orange
        case .reject:        return .red
        case .noMarketData:  return .secondary
        }
    }

    private var verdictIcon: String {
        switch verdict {
        case .list:          return "checkmark.circle.fill"
        case .borderline:    return "exclamationmark.triangle.fill"
        case .reject:        return "xmark.circle.fill"
        case .noMarketData:  return "questionmark.circle.fill"
        }
    }

    private var verdictLabel: String {
        switch verdict {
        case .list:          return "LIST"
        case .borderline:    return "BORDERLINE"
        case .reject:        return "REJECT"
        case .noMarketData:  return "NO MARKET DATA"
        }
    }


    private func statCell(label: String, value: String, trend: AoBClient.Trend, higherIsBetter: Bool) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(value).font(.caption.weight(.medium))
                trendIcon(trend, higherIsBetter: higherIsBetter)
                    .font(.caption2.weight(.bold))
            }
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
}
