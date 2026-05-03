//
//  ListingItem.swift
//  InZentory
//
//  Created by Blueverie on 3/11/26.
//

import Foundation
import SwiftData

enum ItemType: String, Codable, CaseIterable {
    case media, surplus

    var displayName: String {
        switch self {
        case .media: return "Stories"
        case .surplus: return "Surplus"
        }
    }
}

enum ListingStatus: String, Codable, CaseIterable {
    case draft, listed, rejected

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .listed: return "Listed"
        case .rejected: return "Rejected"
        }
    }
}

@Model
final class ListingItem {
    var id: UUID = UUID()
    var type: ItemType = ItemType.media
    var status: ListingStatus = ListingStatus.draft
    var barcode: String? = nil   // legacy — prefer asin/isbn/upc for new items
    var sku: String? = nil
    var asin: String? = nil
    var isbn: String? = nil
    var upc: String? = nil
    var title: String = ""
    var author: String = ""
    var publisher: String = ""
    var pubDate: String = ""
    var itemMedia: String = ""
    var weight: String = ""
    var qty: Int = 1
    var price: String? = nil
    var conditionRaw: Int? = nil
    var source: String = ""
    var location: String = ""
    var notes: String = ""
    var photoURLs: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        type: ItemType,
        status: ListingStatus = .draft,
        barcode: String? = nil,
        sku: String? = nil,
        asin: String? = nil,
        isbn: String? = nil,
        upc: String? = nil,
        title: String = "",
        author: String = "",
        publisher: String = "",
        pubDate: String = "",
        itemMedia: String = "",
        weight: String = "",
        qty: Int = 1,
        price: String? = nil,
        conditionRaw: Int? = nil,
        source: String = "",
        location: String = "",
        notes: String = "",
        photoURLs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.barcode = barcode
        self.sku = sku
        self.asin = asin
        self.isbn = isbn
        self.upc = upc
        self.title = title
        self.author = author
        self.publisher = publisher
        self.pubDate = pubDate
        self.itemMedia = itemMedia
        self.weight = weight
        self.qty = qty
        self.price = price
        self.conditionRaw = conditionRaw
        self.source = source
        self.location = location
        self.notes = notes
        self.photoURLs = photoURLs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
