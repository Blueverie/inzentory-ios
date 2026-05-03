//
//  SourceRecord.swift
//  InZentory
//
//  API-backed sourcing record. Sources are stored on the InZentory backend so
//  they sync across devices — the iOS app does not persist them locally.
//

import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case itemized, bulk, auction

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .itemized: return "Itemized"
        case .bulk:     return "Bulk"
        case .auction:  return "Auction"
        }
    }

    var icon: String {
        switch self {
        case .itemized: return "list.bullet.rectangle"
        case .bulk:     return "shippingbox.fill"
        case .auction:  return "gavel"
        }
    }
}

enum SourceState: String, Codable, CaseIterable, Sendable {
    case open, closed
}

struct SourceCost: Identifiable, Hashable, Sendable {
    let id: Int
    var label: String?
    var price: Double
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, label, price
        case createdAt = "created_at"
    }
}

extension SourceCost: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(Int.self,           forKey: .id)
        label     = try c.decodeIfPresent(String.self, forKey: .label)
        price     = try c.decode(Double.self,        forKey: .price)
        createdAt = try c.decodeIfPresent(Date.self,   forKey: .createdAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(label,     forKey: .label)
        try c.encode(price,              forKey: .price)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct SourceRecord: Identifiable, Hashable, Sendable {
    let id: Int
    let userId: Int
    var name: String
    var kindRaw: String
    var stateRaw: String
    var date: Date
    var notes: String?
    var closedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var costs: [SourceCost]

    enum CodingKeys: String, CodingKey {
        case id, name, notes, costs, date
        case userId    = "user_id"
        case kindRaw   = "kind"
        case stateRaw  = "state"
        case closedAt  = "closed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var kind: SourceKind { SourceKind(rawValue: kindRaw) ?? .bulk }
    var state: SourceState { SourceState(rawValue: stateRaw) ?? .open }

    var totalCost: Double { costs.reduce(0) { $0 + $1.price } }
}

extension SourceRecord: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(Int.self,    forKey: .id)
        userId    = try c.decode(Int.self,    forKey: .userId)
        name      = try c.decode(String.self, forKey: .name)
        kindRaw   = try c.decode(String.self, forKey: .kindRaw)
        stateRaw  = try c.decode(String.self, forKey: .stateRaw)
        date      = try c.decode(Date.self,   forKey: .date)
        notes     = try c.decodeIfPresent(String.self, forKey: .notes)
        closedAt  = try c.decodeIfPresent(Date.self,   forKey: .closedAt)
        createdAt = try c.decodeIfPresent(Date.self,   forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self,   forKey: .updatedAt)
        costs     = try c.decodeIfPresent([SourceCost].self, forKey: .costs) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(userId,    forKey: .userId)
        try c.encode(name,      forKey: .name)
        try c.encode(kindRaw,   forKey: .kindRaw)
        try c.encode(stateRaw,  forKey: .stateRaw)
        try c.encode(date,      forKey: .date)
        try c.encodeIfPresent(notes,     forKey: .notes)
        try c.encodeIfPresent(closedAt,  forKey: .closedAt)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encode(costs,     forKey: .costs)
    }
}
