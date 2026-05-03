//
//  EbayModels.swift
//  InZentory
//

import Foundation

// MARK: - Category tree

struct EbayCategory: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let children: [EbayCategory]?

    var isLeaf: Bool { (children ?? []).isEmpty }

    /// Returns children only for non-leaf nodes so `List(children:)` collapses leaves.
    var optionalChildren: [EbayCategory]? {
        guard let c = children, !c.isEmpty else { return nil }
        return c
    }
}

// MARK: - Category specifics response

struct EbayConditionCode: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct EbayItemSpecific: Codable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    /// "free text" or "selection only"
    let mode: String
    let values: [String]?
    /// min > 0 means the field is required (API returns as string)
    let min: String?

    var isRequired: Bool { (Int(min ?? "0") ?? 0) > 0 }
    var isFreeText: Bool { mode.lowercased().contains("free") }
}

struct EbaySpecificsData: Sendable {
    let condition_codes: [EbayConditionCode]?
    let itemspecifics: [EbayItemSpecific]?
}

extension EbaySpecificsData: Codable {
    enum CodingKeys: String, CodingKey {
        case condition_codes, itemspecifics
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        condition_codes = try c.decodeIfPresent([EbayConditionCode].self, forKey: .condition_codes)
        itemspecifics   = try c.decodeIfPresent([EbayItemSpecific].self, forKey: .itemspecifics)
    }
}
