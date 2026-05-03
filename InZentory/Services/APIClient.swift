//
//  APIClient.swift
//  InZentory
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, detail: String)
    case decodingError(Error)
    case networkError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .httpError(_, let detail): return detail
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        case .networkError(let err): return err.localizedDescription
        case .unknown: return "An unknown error occurred."
        }
    }

    var isUnauthorized: Bool {
        if case .httpError(401, _) = self { return true }
        return false
    }
}

struct AuthResponse {
    let accessToken: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

extension AuthResponse: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
    }
}

private struct APIDetailError {
    let detail: String
}

extension APIDetailError: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // FastAPI returns a plain string for 4xx/5xx, but an array of objects for 422 validation
        if let str = try? container.decode(String.self, forKey: .detail) {
            detail = str
        } else if let errors = try? container.decode([[String: String]].self, forKey: .detail) {
            detail = errors.compactMap { $0["msg"] }.joined(separator: "; ")
        } else {
            detail = "Unknown error"
        }
    }

    enum CodingKeys: String, CodingKey { case detail }
}

// MARK: - InZentory listing models

struct InZentoryListing: Identifiable, Sendable {
    let id: Int
    var status: String?
    var sku: String?
    var title: String?
    var qty: Int?
    var isbn: String?
    var asin: String?
    var upc: String?
    var weight: Double?
    var location: String?
    var condition: String?
    var notes: String?
    var source: String?
    var price: Double?
    var photos: [InZentoryPhoto]?
    var p9: String?           // "stories" | "surplus" — mirrors the AoB p9 field
    // Surplus — core extras
    var description: String?
    var brand: String?
    var lister: String?
    var store: String?
    // Surplus — pricing
    var cost: Double?
    var minPrice: Double?
    var rspPrice: Double?
    var msrp: Double?
    // Surplus — dimensions
    var packageLength: Double?
    var packageWidth: Double?
    var packageDepth: Double?
    // Surplus — eBay
    var ebayCat: String?
    var ebayCatName: String?
    var ebayConditionCode: String?
    var ebayConditionName: String?
    var ebayShippingPolicy: String?
    var ebayReturnPolicy: String?
    var ebayItemSpecifics: [String: String]?
    var created_at: String?
    var updated_at: String?
}

extension InZentoryListing: Codable {
    enum CodingKeys: String, CodingKey {
        case id, status, sku, title, qty, isbn, asin, upc, weight, location, condition, notes, source, price, photos, p9
        case description, brand, lister, store, cost, msrp
        case minPrice          = "min_price"
        case rspPrice          = "rsp_price"
        case packageLength     = "package_length"
        case packageWidth      = "package_width"
        case packageDepth      = "package_depth"
        case ebayCat            = "ebay_cat"
        case ebayCatName        = "ebay_cat_name"
        case ebayConditionCode  = "ebay_condition_code"
        case ebayConditionName  = "ebay_condition_name"
        case ebayShippingPolicy = "ebay_shipping_policy"
        case ebayReturnPolicy   = "ebay_return_policy"
        case ebayItemSpecifics  = "ebay_item_specifics"
        case created_at, updated_at
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(Int.self,              forKey: .id)
        status             = try c.decodeIfPresent(String.self,  forKey: .status)
        sku                = try c.decodeIfPresent(String.self,  forKey: .sku)
        title              = try c.decodeIfPresent(String.self,  forKey: .title)
        qty                = try c.decodeIfPresent(Int.self,     forKey: .qty)
        isbn               = try c.decodeIfPresent(String.self,  forKey: .isbn)
        asin               = try c.decodeIfPresent(String.self,  forKey: .asin)
        upc                = try c.decodeIfPresent(String.self,  forKey: .upc)
        weight             = try c.decodeIfPresent(Double.self,  forKey: .weight)
        location           = try c.decodeIfPresent(String.self,  forKey: .location)
        condition          = try c.decodeIfPresent(String.self,  forKey: .condition)
        notes              = try c.decodeIfPresent(String.self,  forKey: .notes)
        source             = try c.decodeIfPresent(String.self,  forKey: .source)
        price              = try c.decodeIfPresent(Double.self,  forKey: .price)
        photos             = try c.decodeIfPresent([InZentoryPhoto].self, forKey: .photos)
        p9                 = try c.decodeIfPresent(String.self,  forKey: .p9)
        description        = try c.decodeIfPresent(String.self,  forKey: .description)
        brand              = try c.decodeIfPresent(String.self,  forKey: .brand)
        lister             = try c.decodeIfPresent(String.self,  forKey: .lister)
        store              = try c.decodeIfPresent(String.self,  forKey: .store)
        cost               = try c.decodeIfPresent(Double.self,  forKey: .cost)
        minPrice           = try c.decodeIfPresent(Double.self,  forKey: .minPrice)
        rspPrice           = try c.decodeIfPresent(Double.self,  forKey: .rspPrice)
        msrp               = try c.decodeIfPresent(Double.self,  forKey: .msrp)
        packageLength      = try c.decodeIfPresent(Double.self,  forKey: .packageLength)
        packageWidth       = try c.decodeIfPresent(Double.self,  forKey: .packageWidth)
        packageDepth       = try c.decodeIfPresent(Double.self,  forKey: .packageDepth)
        ebayCat            = try c.decodeIfPresent(String.self,  forKey: .ebayCat)
        ebayCatName        = try c.decodeIfPresent(String.self,  forKey: .ebayCatName)
        ebayConditionCode  = try c.decodeIfPresent(String.self,  forKey: .ebayConditionCode)
        ebayConditionName  = try c.decodeIfPresent(String.self,  forKey: .ebayConditionName)
        ebayShippingPolicy = try c.decodeIfPresent(String.self,             forKey: .ebayShippingPolicy)
        ebayReturnPolicy   = try c.decodeIfPresent(String.self,             forKey: .ebayReturnPolicy)
        ebayItemSpecifics  = try c.decodeIfPresent([String: String].self,   forKey: .ebayItemSpecifics)
        created_at         = try c.decodeIfPresent(String.self,             forKey: .created_at)
        updated_at         = try c.decodeIfPresent(String.self,             forKey: .updated_at)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(status,             forKey: .status)
        try c.encodeIfPresent(sku,                forKey: .sku)
        try c.encodeIfPresent(title,              forKey: .title)
        try c.encodeIfPresent(qty,                forKey: .qty)
        try c.encodeIfPresent(isbn,               forKey: .isbn)
        try c.encodeIfPresent(asin,               forKey: .asin)
        try c.encodeIfPresent(upc,                forKey: .upc)
        try c.encodeIfPresent(weight,             forKey: .weight)
        try c.encodeIfPresent(location,           forKey: .location)
        try c.encodeIfPresent(condition,          forKey: .condition)
        try c.encodeIfPresent(notes,              forKey: .notes)
        try c.encodeIfPresent(source,             forKey: .source)
        try c.encodeIfPresent(price,              forKey: .price)
        try c.encodeIfPresent(photos,             forKey: .photos)
        try c.encodeIfPresent(p9,                 forKey: .p9)
        try c.encodeIfPresent(description,        forKey: .description)
        try c.encodeIfPresent(brand,              forKey: .brand)
        try c.encodeIfPresent(lister,             forKey: .lister)
        try c.encodeIfPresent(store,              forKey: .store)
        try c.encodeIfPresent(cost,               forKey: .cost)
        try c.encodeIfPresent(minPrice,           forKey: .minPrice)
        try c.encodeIfPresent(rspPrice,           forKey: .rspPrice)
        try c.encodeIfPresent(msrp,               forKey: .msrp)
        try c.encodeIfPresent(packageLength,      forKey: .packageLength)
        try c.encodeIfPresent(packageWidth,       forKey: .packageWidth)
        try c.encodeIfPresent(packageDepth,       forKey: .packageDepth)
        try c.encodeIfPresent(ebayCat,            forKey: .ebayCat)
        try c.encodeIfPresent(ebayCatName,        forKey: .ebayCatName)
        try c.encodeIfPresent(ebayConditionCode,  forKey: .ebayConditionCode)
        try c.encodeIfPresent(ebayConditionName,  forKey: .ebayConditionName)
        try c.encodeIfPresent(ebayShippingPolicy, forKey: .ebayShippingPolicy)
        try c.encodeIfPresent(ebayReturnPolicy,   forKey: .ebayReturnPolicy)
        try c.encodeIfPresent(ebayItemSpecifics,  forKey: .ebayItemSpecifics)
        try c.encodeIfPresent(created_at,         forKey: .created_at)
        try c.encodeIfPresent(updated_at,         forKey: .updated_at)
    }
}

struct InZentoryPhoto: Codable, Sendable {
    let key: String
    let url: String
}

/// Write-only payload — only non-nil fields are encoded (omits nil keys entirely).
struct DraftPayload: Encodable, Sendable {
    // Core
    var status: String?
    var sku: String?
    var title: String?
    var qty: Int?
    var isbn: String?
    var asin: String?
    var upc: String?
    var weight: Double?
    var location: String?
    var condition: String?
    var notes: String?
    var source: String?
    var price: Double?
    var p9: String?
    // Surplus — core extras
    var description: String?
    var brand: String?
    var lister: String?
    var store: String?
    // Surplus — pricing
    var cost: Double?
    var minPrice: Double?
    var rspPrice: Double?
    var msrp: Double?
    // Surplus — dimensions
    var packageLength: Double?
    var packageWidth: Double?
    var packageDepth: Double?
    // Surplus — eBay
    var ebayCat: String?
    var ebayCatName: String?
    var ebayConditionCode: String?
    var ebayConditionName: String?
    var ebayShippingPolicy: String?
    var ebayReturnPolicy: String?
    var ebayItemSpecifics: [String: String]?
    // Photos
    var photos: [String]?

    enum CodingKeys: String, CodingKey {
        case status, sku, title, qty, isbn, asin, upc, weight, location, condition
        case notes, source, price, p9
        case description, brand, lister, store, cost, msrp
        case photos
        case minPrice           = "min_price"
        case rspPrice           = "rsp_price"
        case packageLength      = "package_length"
        case packageWidth       = "package_width"
        case packageDepth       = "package_depth"
        case ebayCat            = "ebay_cat"
        case ebayCatName        = "ebay_cat_name"
        case ebayConditionCode  = "ebay_condition_code"
        case ebayConditionName  = "ebay_condition_name"
        case ebayShippingPolicy = "ebay_shipping_policy"
        case ebayReturnPolicy   = "ebay_return_policy"
        case ebayItemSpecifics  = "ebay_item_specifics"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = status             { try c.encode(v, forKey: .status) }
        if let v = sku                { try c.encode(v, forKey: .sku) }
        if let v = title              { try c.encode(v, forKey: .title) }
        if let v = qty                { try c.encode(v, forKey: .qty) }
        if let v = isbn               { try c.encode(v, forKey: .isbn) }
        if let v = asin               { try c.encode(v, forKey: .asin) }
        if let v = upc                { try c.encode(v, forKey: .upc) }
        if let v = weight             { try c.encode(v, forKey: .weight) }
        if let v = location           { try c.encode(v, forKey: .location) }
        if let v = condition          { try c.encode(v, forKey: .condition) }
        if let v = notes              { try c.encode(v, forKey: .notes) }
        if let v = source             { try c.encode(v, forKey: .source) }
        if let v = price              { try c.encode(v, forKey: .price) }
        if let v = p9                 { try c.encode(v, forKey: .p9) }
        if let v = description        { try c.encode(v, forKey: .description) }
        if let v = brand              { try c.encode(v, forKey: .brand) }
        if let v = lister             { try c.encode(v, forKey: .lister) }
        if let v = store              { try c.encode(v, forKey: .store) }
        if let v = cost               { try c.encode(v, forKey: .cost) }
        if let v = minPrice           { try c.encode(v, forKey: .minPrice) }
        if let v = rspPrice           { try c.encode(v, forKey: .rspPrice) }
        if let v = msrp               { try c.encode(v, forKey: .msrp) }
        if let v = packageLength      { try c.encode(v, forKey: .packageLength) }
        if let v = packageWidth       { try c.encode(v, forKey: .packageWidth) }
        if let v = packageDepth       { try c.encode(v, forKey: .packageDepth) }
        if let v = ebayCat            { try c.encode(v, forKey: .ebayCat) }
        if let v = ebayCatName        { try c.encode(v, forKey: .ebayCatName) }
        if let v = ebayConditionCode  { try c.encode(v, forKey: .ebayConditionCode) }
        if let v = ebayConditionName  { try c.encode(v, forKey: .ebayConditionName) }
        if let v = ebayShippingPolicy { try c.encode(v, forKey: .ebayShippingPolicy) }
        if let v = ebayReturnPolicy   { try c.encode(v, forKey: .ebayReturnPolicy) }
        if let v = ebayItemSpecifics, !v.isEmpty { try c.encode(v, forKey: .ebayItemSpecifics) }
        if let v = photos             { try c.encode(v, forKey: .photos) }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://blueverie-share-backend-3p62q.ondigitalocean.app"
    private var bearerToken: String?

    /// Decoder configured to accept the backend's ISO-8601 date strings (with or without fractional seconds).
    private static let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            // Construct the formatters inside the closure so they don't get captured.
            // ISO8601DateFormatter is not Sendable; the cost is negligible vs. JSON parsing.
            let withFrac    = ISO8601DateFormatter(); withFrac.formatOptions    = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFrac = ISO8601DateFormatter(); withoutFrac.formatOptions = [.withInternetDateTime]
            if let date = withFrac.date(from: s) ?? withoutFrac.date(from: s) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Invalid date: \(s)"
            )
        }
        return d
    }()

    private static let isoEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func setToken(_ token: String?) {
        bearerToken = token
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: (any Encodable & Sendable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try APIClient.isoEncoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let detail = (try? JSONDecoder().decode(APIDetailError.self, from: data))?.detail
                ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw APIError.httpError(statusCode: statusCode, detail: detail)
        }

        do {
            return try APIClient.isoDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - No-body requests (DELETE, etc.)

    func requestEmpty(path: String, method: String = "DELETE") async throws {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token = bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let detail = (try? JSONDecoder().decode(APIDetailError.self, from: data))?.detail
                ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw APIError.httpError(statusCode: statusCode, detail: detail)
        }
    }

    // MARK: - InZentory listings

    func fetchDrafts() async throws -> [InZentoryListing] {
        try await request(path: "/inzentory/listings?status=draft")
    }

    func createListing(_ payload: DraftPayload) async throws -> InZentoryListing {
        try await request(path: "/inzentory/listings", method: "POST", body: payload)
    }

    func updateListing(id: Int, _ payload: DraftPayload) async throws -> InZentoryListing {
        try await request(path: "/inzentory/listings/\(id)", method: "PUT", body: payload)
    }

    func deleteListing(id: Int) async throws {
        try await requestEmpty(path: "/inzentory/listings/\(id)")
    }

    // MARK: - Sources

    struct SourceCreatePayload: Encodable, Sendable {
        let name: String
        let kind: String
        let date: Date
        let notes: String?
    }

    struct SourceUpdatePayload: Encodable, Sendable {
        var name: String?
        var state: String?
        var date: Date?
        var notes: String?
    }

    struct SourceCostCreatePayload: Encodable, Sendable {
        let label: String?
        let price: Double
    }

    func fetchSources(state: SourceState? = nil, kind: SourceKind? = nil) async throws -> [SourceRecord] {
        var query: [String] = []
        if let state { query.append("state=\(state.rawValue)") }
        if let kind  { query.append("kind=\(kind.rawValue)") }
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return try await request(path: "/inzentory/sources" + suffix)
    }

    func createSource(name: String, kind: SourceKind, date: Date, notes: String?) async throws -> SourceRecord {
        try await request(
            path: "/inzentory/sources",
            method: "POST",
            body: SourceCreatePayload(name: name, kind: kind.rawValue, date: date, notes: notes)
        )
    }

    func updateSource(id: Int, _ payload: SourceUpdatePayload) async throws -> SourceRecord {
        try await request(path: "/inzentory/sources/\(id)", method: "PUT", body: payload)
    }

    func deleteSource(id: Int) async throws {
        try await requestEmpty(path: "/inzentory/sources/\(id)")
    }

    func addSourceCost(sourceId: Int, label: String?, price: Double) async throws -> SourceCost {
        try await request(
            path: "/inzentory/sources/\(sourceId)/costs",
            method: "POST",
            body: SourceCostCreatePayload(label: label, price: price)
        )
    }

    func deleteSourceCost(sourceId: Int, costId: Int) async throws {
        try await requestEmpty(path: "/inzentory/sources/\(sourceId)/costs/\(costId)")
    }

    // MARK: - Auth

    func login(username: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let username, password: String }
        return try await request(
            path: "/inzentory/auth/login",
            method: "POST",
            body: Body(username: username, password: password),
            authenticated: false
        )
    }

    func register(username: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let username, password: String }
        return try await request(
            path: "/inzentory/auth/register",
            method: "POST",
            body: Body(username: username, password: password),
            authenticated: false
        )
    }
}
