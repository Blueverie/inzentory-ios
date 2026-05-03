//
//  SurplusListingTemplate.swift
//  InZentory
//

import Foundation

// MARK: - Template Data

/// Unified data bag for surplus listing templates.
/// Populated from ListFormView (full data) or AoBItem (partial data).
struct SurplusTemplateData: Sendable {
    let title: String
    let description: String
    let condition: String       // ItemCondition.displayName
    let ebayCondition: String   // eBay condition name (e.g. "Used - Good")
    let notes: String
    let rspPrice: Double?       // RSP / sale price
    let msrp: Double?
    let price: Double?          // AoB listing price
    let cost: Double?           // cost of goods (for Mercari min price)
    let sku: String
    let brand: String
    let ebayCatName: String
    let weightOz: Double?       // always in ounces
    let lengthIn: Double?
    let widthIn: Double?
    let depthIn: Double?
    let shippingRate: EasyPostClient.Rate?
}

// MARK: - Template Rows

/// A single row rendered in SurplusTemplateSheet.
enum TemplateRow {
    /// Single-line value with a Copy button.
    case copyField(label: String, value: String)
    /// Multi-line block with a Copy button.
    case copyBlock(label: String, text: String)
    /// Display-only info row (no copy).
    case infoField(label: String, value: String)
}

// MARK: - Template Enum

enum SurplusListingTemplate: String, CaseIterable, Identifiable {
    case facebookGroups      = "FB Groups"
    case facebookMarketplace = "Marketplace"
    case mercari             = "Mercari"

    var id: String { rawValue }
    var displayName: String { rawValue }

    func rows(from data: SurplusTemplateData) -> [TemplateRow] {
        switch self {
        case .facebookGroups:      return fbGroupsRows(data)
        case .facebookMarketplace: return fbMarketplaceRows(data)
        case .mercari:             return mercariRows(data)
        }
    }
}

// MARK: - Row Builders

private extension SurplusListingTemplate {

    func fbGroupsRows(_ d: SurplusTemplateData) -> [TemplateRow] {
        var lines: [String] = []
        lines.append("🛍️ \(d.title)")

        if !d.description.isEmpty {
            lines.append("📝 \(d.description)")
        }

        let condNotes = [d.condition, d.notes].filter { !$0.isEmpty }.joined(separator: ", ")
        if !condNotes.isEmpty {
            lines.append("🏷️ \(condNotes)")
        }

        if let rsp = d.rspPrice {
            lines.append("💰 Price: $\(formatPrice(rsp))")
        }

        if let msrp = d.msrp {
            lines.append("🧾 Retail: \(formatPrice(msrp))")
        }

        lines.append("📍 Pick up in Ashland, Ohio")
        lines.append("📦 Delivery/shipping available")
        lines.append("💸 Offers always considered")

        return [.copyBlock(label: "Re Supply Pros", text: lines.joined(separator: "\n"))]
    }

    func fbMarketplaceRows(_ d: SurplusTemplateData) -> [TemplateRow] {
        var rows: [TemplateRow] = []

        rows.append(.copyField(label: "Title", value: d.title))

        if let price = d.price {
            rows.append(.copyField(label: "Price", value: "$\(formatRounded(price))"))
        }

        if !d.ebayCatName.isEmpty {
            rows.append(.copyField(label: "Category", value: d.ebayCatName))
        }

        // Description block
        var descLines: [String] = []
        if !d.description.isEmpty { descLines.append(d.description) }
        let condNotes = [d.ebayCondition, d.notes].filter { !$0.isEmpty }.joined(separator: ", ")
        if !condNotes.isEmpty { descLines.append(condNotes) }
        descLines.append("")
        descLines.append("Pick up in Ashland, Ohio")
        descLines.append("Delivery/shipping available")
        descLines.append("")
        descLines.append("Find more deals and exclusive discounts: www.Facebook.com/groups/ReSupplyPros")
        rows.append(.copyBlock(label: "Description", text: descLines.joined(separator: "\n")))

        if !d.sku.isEmpty   { rows.append(.copyField(label: "SKU",   value: d.sku)) }
        if !d.brand.isEmpty { rows.append(.copyField(label: "Brand", value: d.brand)) }

        // Info-only fields
        if let rate = d.shippingRate {
            rows.append(.infoField(label: "Shipping (\(rate.carrier) \(rate.service))",
                                   value: String(format: "$%.2f", rate.rate)))
        }
        if let oz = d.weightOz {
            rows.append(.infoField(label: "Weight", value: formatWeight(oz)))
        }
        if let l = d.lengthIn, let w = d.widthIn, let h = d.depthIn {
            rows.append(.infoField(label: "Dimensions",
                                   value: String(format: "%.1f\" × %.1f\" × %.1f\"", l, w, h)))
        }

        return rows
    }

    func mercariRows(_ d: SurplusTemplateData) -> [TemplateRow] {
        var rows: [TemplateRow] = []

        // Description block
        var descLines: [String] = []
        if !d.description.isEmpty { descLines.append(d.description) }
        let condNotes = [d.ebayCondition, d.notes].filter { !$0.isEmpty }.joined(separator: ", ")
        if !condNotes.isEmpty { descLines.append(condNotes) }
        descLines.append("")
        if !d.sku.isEmpty { descLines.append(d.sku) }
        rows.append(.copyBlock(label: "Description", text: descLines.joined(separator: "\n")))

        if !d.ebayCatName.isEmpty   { rows.append(.copyField(label: "Category",  value: d.ebayCatName)) }
        if !d.brand.isEmpty         { rows.append(.copyField(label: "Brand",     value: d.brand)) }
        if !d.ebayCondition.isEmpty { rows.append(.copyField(label: "Condition", value: d.ebayCondition)) }

        if let price = d.price {
            rows.append(.copyField(label: "Price", value: "$\(formatRounded(price))"))
        }

        // Min price: (cost + shipping) / 0.9
        if let cost = d.cost {
            let shipping = d.shippingRate?.rate ?? 0.0
            let minPrice = (cost + shipping) / 0.9
            rows.append(.copyField(label: "Min Price", value: String(format: "$%.2f", minPrice)))
        }

        return rows
    }
}

// MARK: - Formatting Helpers

/// Formats a price, dropping unnecessary decimal places (e.g. 49.00 → "49", 9.95 → "9.95").
private func formatPrice(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.2f", value)
}

/// Rounds to the nearest $5 increment (e.g. 99.95 → "100", 12.00 → "10").
private func formatRounded(_ price: Double) -> String {
    let rounded = (price / 5.0).rounded() * 5.0
    return String(format: "%.0f", rounded)
}

/// Converts ounces to a human-readable "X lbs Y oz" string.
private func formatWeight(_ oz: Double) -> String {
    let totalOz = Int(oz)
    let lbs = totalOz / 16
    let remOz = oz - Double(lbs * 16)

    if lbs > 0 {
        if remOz >= 0.05 {
            return String(format: "%d lbs %.0f oz", lbs, remOz)
        }
        return "\(lbs) lbs"
    }
    return String(format: "%.0f oz", oz)
}
