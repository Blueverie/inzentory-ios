//
//  ItemCondition.swift
//  InZentory
//

import Foundation

// Declaration order determines CaseIterable order (display order)
enum ItemCondition: Int, CaseIterable, Equatable {
    case new = 11
    case likeNew = 1
    case veryGood = 2
    case good = 3
    case acceptable = 4
    case refurbished = 10  // Surplus only
    case damaged = 9       // Surplus only

    var displayName: String {
        switch self {
        case .new:         return "New"
        case .likeNew:     return "Like New"
        case .veryGood:    return "Very Good"
        case .good:        return "Good"
        case .acceptable:  return "Acceptable"
        case .refurbished: return "Refurbished"
        case .damaged:     return "Damaged"
        }
    }

    var shortName: String {
        switch self {
        case .new:         return "New"
        case .likeNew:     return "LN"
        case .veryGood:    return "VG"
        case .good:        return "Good"
        case .acceptable:  return "Acc"
        case .refurbished: return "Rfb"
        case .damaged:     return "Dmg"
        }
    }

    /// Cases shown in the Stories (media) condition picker.
    static let storiesCases: [ItemCondition] = [.new, .likeNew, .veryGood, .good, .acceptable]
    /// Cases shown in the Surplus condition picker.
    static let surplusCases: [ItemCondition] = [.new, .refurbished, .good, .damaged]
}
