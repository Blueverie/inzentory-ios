//
//  ReopenPayload.swift
//  InZentory
//

/// Carries all form-fillable data when re-opening a draft or previously listed item.
struct ReopenPayload: Sendable, Equatable {
    var inzentoryDraftId: Int?  // non-nil when reopening an InZentory draft
    var sku: String?
    var type: ItemType
    var asin: String?
    var isbn: String?
    var upc: String?
    var title: String
    var author: String
    var publisher: String
    var pubDate: String
    var itemMedia: String
    var weight: String
    var qty: String
    var price: String
    var condition: ItemCondition?
    var source: String
    var location: String
    var notes: String
    var photoURLs: [String]
    // Surplus-only fields
    var description: String = ""
    var brand: String = ""
    var cost: String = ""
    var minPrice: String = ""
    var rsPrice: String = ""
    var msrp: String = ""
    var packageLength: String = ""
    var packageWidth: String = ""
    var packageDepth: String = ""
    var ebyCat: String = ""
    var ebyCatName: String = ""
    var ebayConditionCode: String = ""
    var ebayConditionName: String = ""
    var ebayItemSpecifics: [String: String] = [:]
}
