//
//  AoBClient.swift
//  InZentory
//

import Foundation

actor AoBClient {
    static let shared = AoBClient()
    private let baseURL = URL(string: "https://www.theartofbooks.com/api/2.0/")!

    // MARK: - Error

    enum AoBError: LocalizedError {
        case missingCredentials
        case httpError(Int, String)
        case apiError(Int, String)
        case networkError(Error)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Invalid or missing AoB credentials. Check Settings → Credentials."
            case .httpError(let code, let msg):
                return "HTTP \(code): \(msg)"
            case .apiError(let code, let msg):
                return "API error \(code): \(msg)"
            case .networkError(let err):
                return err.localizedDescription
            case .parseError(let msg):
                return "Parse error: \(msg)"
            }
        }
    }

    // MARK: - Models

    enum Trend: Sendable {
        case improving, worsening, neutral
    }

    enum ListingVerdict: Sendable {
        case list(minCondition: String?)
        case borderline(minCondition: String?)
        case reject
        case noMarketData
    }

    struct ProductData: Sendable {
        let asin: String
        let title: String
        let imageURL: String?
        let author: String?
        let publisher: String?
        let releaseDate: String?
        let media: String?
        let weight: String?
    }

    struct CatData: Sendable {
        let asin: String
        let upc: String?
        let salesRank: Int
        let salesRankHistory: [TimeInterval: Double]
        let buyPrice: Double
        let buyPriceHistory: [TimeInterval: Double]
        let abeMargin: Double
        let amzMargin: Double
        let minMargin: Double

        // 90-day rolling average rank (lower number = better rank)
        var avg90Rank: Double {
            let cutoff = Date().timeIntervalSince1970 - 7_776_000
            let recent = salesRankHistory.filter { $0.key >= cutoff }
            guard !recent.isEmpty else { return 0 }
            return recent.values.reduce(0, +) / Double(recent.count)
        }

        // 90-day rolling average buy price
        var avg90Price: Double {
            let cutoff = Date().timeIntervalSince1970 - 7_776_000
            let recent = buyPriceHistory.filter { $0.key >= cutoff }
            guard !recent.isEmpty else { return 0 }
            return recent.values.reduce(0, +) / Double(recent.count)
        }

        // Highest buy price seen in last 14 days (or current price if no history)
        var high14Price: Double {
            let cutoff = Date().timeIntervalSince1970 - 1_209_600
            let recent = buyPriceHistory.filter { $0.key >= cutoff }
            return max(buyPrice, recent.values.max() ?? buyPrice)
        }

        // Lower rank number = better. Improving means rank < avg (went down).
        var rankTrend: Trend {
            let avg = avg90Rank
            guard avg > 0 else { return .neutral }
            if Double(salesRank) < avg { return .improving }
            if Double(salesRank) > avg { return .worsening }
            return .neutral
        }

        // Higher price = better. Improving means price > avg.
        var priceTrend: Trend {
            let avg = avg90Price
            guard avg > 0 else { return .neutral }
            if buyPrice > avg { return .improving }
            if buyPrice < avg { return .worsening }
            return .neutral
        }

        func verdict() -> ListingVerdict {
            let effectiveThreshold = abeMargin > amzMargin ? minMargin / 1.18 : minMargin
            let dominantMargin = Swift.max(abeMargin, amzMargin)
            let fallbackMargin = Swift.min(abeMargin, amzMargin)

            if dominantMargin > effectiveThreshold {
                return .list(minCondition: conditionRec(
                    ratio: effectiveThreshold > 0 ? dominantMargin / effectiveThreshold : 1.0,
                    fallback: fallbackMargin
                ))
            } else if dominantMargin > 0 {
                return .borderline(minCondition: conditionRec(
                    ratio: effectiveThreshold > 0 ? dominantMargin / effectiveThreshold : 1.0,
                    fallback: fallbackMargin
                ))
            } else if buyPrice > 0 || abeMargin != 0 || amzMargin != 0 {
                return .reject
            } else {
                return .noMarketData
            }
        }

        private func conditionRec(ratio: Double, fallback: Double) -> String? {
            // Condition levels ordered from strictest (0) to most relaxed (3)
            // 0 = no recommendation, 1 = Very Good+, 2 = Good+, 3 = any condition
            var level: Int
            if ratio > 0.5      { level = 2 }   // Good or better
            else if ratio > 0.2 { level = 1 }   // Very Good or better
            else                { level = 0 }   // no recommendation

            // Rank adjustment
            if salesRank < 500_000        { level = Swift.min(level + 1, 3) }
            else if salesRank > 2_000_000 { level = Swift.max(level - 1, 0) }

            // Fallback margin adjustment
            if fallback > 0        { level = Swift.min(level + 1, 3) }
            else if fallback < -1  { level = Swift.max(level - 1, 0) }

            switch level {
            case 1:  return "Very Good"
            case 2:  return "Good"
            default: return nil   // 0 = no rec, 3 = any condition (no minimum)
            }
        }
    }

    struct LookupResult: Sendable {
        let barcode: String
        let productData: ProductData?
        let catData: CatData?
    }

    /// Item payload for POST /api/2.0/inventory_upload
    struct InventoryItem: Sendable {
        let sku: String
        let title: String
        let description: String?  // surplus long description
        let cost: String?         // surplus cost (uzsed for min-price calc)
        let author: String
        let isbn: String?       // field name is "isbn" but AoB stores the ASIN here
        let upc: String?
        let flex: [String: String]?  // Perl Dumper hash stored in inv.flex column (e.g. isbn13)
        let price: String?      // listing price
        let p2: String?         // InZentory username
        let location: String
        let condition: Int      // ItemCondition.rawValue (1=LN, 2=VG, 3=Good, 4=Acc, 11=New)
        let notes: String
        let source: String
        let qty: Int
        let p9: String?         // category tag ('stories' for media items, 'surplus' for surplus)
        let publisher: String?  // surplus brand
        let image: String?      // primary photo URL
        let extraImages: [String] // image_2 … image_12
        let itemSpecifics: [String: String]?  // eBay item specifics keyed by field name
    }

    // MARK: - Order Models

    struct AoBOrderItem: Identifiable, Sendable {
        let id: String          // order_item_id
        let sku: String?
        let title: String?
        let qty: Int?
        let price: String?
        let imageURL: String?
        let source: String?
        let location: String?
        let media: String?
        let lister: String?     // p2 — InZentory username of the lister
    }

    struct AoBOrder: Identifiable, Sendable {
        let id: String          // order_id
        let buyerName: String?
        let buyerEmail: String?
        let orderDate: String?
        let aobStatus: String?
        let items: [AoBOrderItem]
    }

    /// Single parsed result from GET /amz_keyword_search
    struct AmzSearchItem: Sendable, Identifiable {
        var id: String { asin }
        let asin: String
        let title: String
        let author: String?
        let brand: String?
        let manufacturer: String?
        let releaseDate: String?
        let websiteDisplayGroup: String       // e.g. "book_display_on_website"
        let websiteDisplayGroupName: String   // e.g. "Book"
        let browseClassification: String?
    }

    /// Parsed result from GET /item search
    struct AoBItem: Sendable, Identifiable {
        var id: String { sku }
        let sku: String
        let title: String
        let asin: String?        // stored in AoB's "isbn" field
        let isbn: String?        // isbn13 from flex field
        let upc: String?
        let conditionRaw: Int?
        let price: String?
        let author: String?
        let publisher: String?
        let media: String?
        let releaseDate: String?
        let notes: String?
        let source: String?
        let location: String?
        let qty: Int?
        let weight: String?
        let imageURL: String?
        let p9: String?
        /// Date the item was listed in AoB (e.g. "2024-11-03"). Nil if not returned by the API.
        let dateListed: String?
    }

    // MARK: - Public API

    /// Search AoB inventory by arbitrary field equality (e.g. ["p2": username]).
    func fetchItems(params: [String: String]) async throws -> [AoBItem] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        let username = creds.username
        let password = creds.password

        var components = URLComponents(url: baseURL.appendingPathComponent("item"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw AoBError.parseError("invalid item search URL") }

        var request = URLRequest(url: url)
        request.setValue(username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(password, forHTTPHeaderField: "AOB-AUTH-PW")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AoBError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        let arr = try parseItemArray(from: data)
        return arr.compactMap { parseAoBItem($0) }
    }

    /// Fetches the most recent items listed by a specific InZentory user (filters by p2 = InZentory username).
    func fetchMyItems(inzentoryUsername: String, limit: Int = 20) async throws -> [AoBItem] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        let username = creds.username
        let password = creds.password

        var components = URLComponents(url: baseURL.appendingPathComponent("item"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "p2",       value: inzentoryUsername),
            URLQueryItem(name: "sort_sku", value: "desc"),
            URLQueryItem(name: "limit",    value: String(limit)),
        ]
        guard let url = components.url else { throw AoBError.parseError("invalid item search URL") }

        var request = URLRequest(url: url)
        request.setValue(username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(password, forHTTPHeaderField: "AOB-AUTH-PW")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AoBError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        let arr = try parseItemArray(from: data)
        return Array(arr.compactMap { parseAoBItem($0) }.prefix(limit))
    }

    /// Parses an item array from a response that may be:
    /// - A plain `[{...}]` array
    /// - `{"results": [{...}]}` wrapped array
    /// - `{"results": {"sku":"...", ...}}` single-item dict (exact-field searches)
    /// - `{"results": {"key1": {...}, "key2": {...}}}` hash of items keyed by sku/id
    private func parseItemArray(from data: Data) throws -> [[String: Any]] {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            throw AoBError.parseError("item response is not valid JSON: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "<binary>")")
        }
        if let arr = parsed as? [[String: Any]] { return arr }
        guard let obj = parsed as? [String: Any] else {
            throw AoBError.parseError("item response has unexpected format: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "<binary>")")
        }
        // null / missing results → empty
        guard let resultsVal = obj["results"] else { return [] }
        // array forms
        if let arr = resultsVal as? [[String: Any]] { return arr }
        if let arr = resultsVal as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        // single item dict (exact-match searches return one item, not wrapped in array)
        if let single = resultsVal as? [String: Any] {
            if single["sku"] != nil { return [single] }
            // hash of items keyed by arbitrary key — extract values that have a sku
            let vals = single.values.compactMap { $0 as? [String: Any] }.filter { $0["sku"] != nil }
            if !vals.isEmpty { return vals }
        }
        return []
    }

    private func parseAoBItem(_ d: [String: Any]) -> AoBItem? {
        guard let sku = d["sku"] as? String, !sku.isEmpty else { return nil }

        let condRaw: Int?
        if let c = d["condition"] as? Int { condRaw = c }
        else if let s = d["condition"] as? String { condRaw = Int(s) }
        else { condRaw = nil }

        let qty: Int?
        if let q = d["qty"] as? Int { qty = q }
        else if let s = d["qty"] as? String { qty = Int(s) }
        else { qty = nil }

        let price: String?
        if let p = d["price"] as? String { price = p }
        else if let p = d["price"] as? Double { price = String(p) }
        else { price = nil }

        let isbn13 = (d["flex"] as? String).flatMap { parseIsbn13FromFlex($0) }

        return AoBItem(
            sku:          sku,
            title:        d["title"] as? String ?? "",
            asin:         d["isbn"] as? String,    // AoB stores ASIN in "isbn"
            isbn:         isbn13,
            upc:          d["upc"] as? String,
            conditionRaw: condRaw,
            price:        price,
            author:       d["author"] as? String,
            publisher:    d["publisher"] as? String,
            media:        d["media"] as? String,
            releaseDate:  d["release_date"] as? String,
            notes:        d["notes"] as? String,
            source:       d["source"] as? String,
            location:     d["location"] as? String,
            qty:          qty,
            weight:       d["weight"] as? String,
            imageURL:     d["image"] as? String,
            p9:           d["p9"] as? String,
            dateListed:   d["date_listed"] as? String ?? d["date"] as? String
        )
    }

    private func parseIsbn13FromFlex(_ flexStr: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"'isbn13'\s*=>\s*'([^']+)'"#) else { return nil }
        let range = NSRange(flexStr.startIndex..., in: flexStr)
        guard let match = regex.firstMatch(in: flexStr, range: range),
              let r = Range(match.range(at: 1), in: flexStr) else { return nil }
        return String(flexStr[r])
    }

    func getAutoSku() async throws -> String {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        let username = creds.username
        let password = creds.password
        let json = try await fetch(endpoint: "auto_sku", username: username, password: password)
        let results = json["results"]
        if let s = results as? String, !s.isEmpty { return s }
        if let i = results as? Int { return String(i) }
        if let d = results as? Double { return String(Int(d)) }
        throw AoBError.parseError("auto_sku: unexpected results format")
    }

    /// POST /api/2.0/inventory_upload  →  returns the AoB batch ID
    func inventoryUpload(item: InventoryItem) async throws -> Int {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        let username = creds.username
        let password = creds.password

        var dict: [String: Any] = [
            "sku":        item.sku,
            "title":      item.title,
            "author":     item.author,
            "location":   item.location,
            "condition":  item.condition,
            "notes":      item.notes,
            "source":     item.source,
            "qty":        item.qty,
            "fba":        "n",
            "list_flags": 0
        ]
        if let isbn = item.isbn { dict["isbn"] = isbn }
        if let upc  = item.upc  { dict["upc"]  = upc }
        // Merge extra images (image_2, image_3, …) into flex so they travel together
        var flexDict = item.flex ?? [:]
        for (i, url) in item.extraImages.enumerated() {
            flexDict["image_\(i + 2)"] = url
        }
        if !flexDict.isEmpty {
            // Perl Data::Dumper compact format: $VAR1 = {'key' => 'value',...};
            let pairs = flexDict.map { "'\($0.key)' => '\($0.value)'" }.joined(separator: ",")
            dict["flex"] = "$VAR1 = {\(pairs)};"
        }
        if let price = item.price               { dict["price"]       = price }
        if let p2 = item.p2, !p2.isEmpty       { dict["p2"]          = p2 }
        if let p9 = item.p9                    { dict["p9"]          = p9 }
        if let d = item.description, !d.isEmpty { dict["description"] = d }
        if let c = item.cost, !c.isEmpty        { dict["cost"]        = c }
        if let p = item.publisher, !p.isEmpty   { dict["publisher"]   = p }
        if let image = item.image               { dict["image"]       = image }
        if let specs = item.itemSpecifics {
            // Strip is_ prefix (stored without it) and encode as ebay_attributes Dumper hash
            let filtered = specs.filter { !$0.value.isEmpty }
            if !filtered.isEmpty {
                let pairs = filtered.map { "'\($0.key)' => '\($0.value)'" }.joined(separator: ",")
                dict["ebay_attributes"] = "$VAR1 = {\(pairs)};"
            }
        }

        let payload = try JSONSerialization.data(withJSONObject: [dict])
        let payloadStr = String(data: payload, encoding: .utf8) ?? "[]"

        // URLComponents leaves RFC 3986 sub-delimiters (= $ ' ; etc.) unencoded, which
        // corrupts Perl's form-data parser. Encode strictly: alphanumerics + -._~ only.
        let formSafe = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let encoded = payloadStr.addingPercentEncoding(withAllowedCharacters: formSafe) ?? ""
        let body = "item_data=\(encoded)"

        let json = try await post(endpoint: "inventory_upload", body: body, username: username, password: password)
        guard let results = json["results"] as? [String: Any] else {
            throw AoBError.parseError("inventory_upload: no results key")
        }
        if let i = results["id"] as? Int    { return i }
        if let d = results["id"] as? Double { return Int(d) }
        if let s = results["id"] as? String, let i = Int(s) { return i }
        throw AoBError.parseError("inventory_upload: unexpected id type")
    }

    /// Lightweight inventory_upload for the Audit tab.
    /// For retain: sends the item with its current qty and list_flags=0.
    /// For delete: sends qty=0 to remove from inventory.
    /// Pass `locationOverride` to move the item to a different location during the upload.
    func auditInventoryUpload(item: AoBItem, qty: Int, locationOverride: String? = nil) async throws {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        var dict: [String: Any] = [
            "sku":        item.sku,
            "title":      item.title,
            "author":     item.author ?? "",
            "location":   locationOverride ?? item.location ?? "",
            "condition":  item.conditionRaw ?? 3,
            "notes":      item.notes ?? "",
            "source":     item.source ?? "",
            "qty":        qty,
            "fba":        "n",
            "list_flags": 0
        ]
        if let asin = item.asin, !asin.isEmpty { dict["isbn"] = asin }
        if let upc  = item.upc,  !upc.isEmpty  { dict["upc"]  = upc  }

        let payload    = try JSONSerialization.data(withJSONObject: [dict])
        let payloadStr = String(data: payload, encoding: .utf8) ?? "[]"
        let formSafe   = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let encoded    = payloadStr.addingPercentEncoding(withAllowedCharacters: formSafe) ?? ""
        _ = try await post(endpoint: "inventory_upload",
                           body: "item_data=\(encoded)",
                           username: creds.username, password: creds.password)
    }

    /// Fetches product metadata for a single product ID (ASIN, ISBN, UPC).
    func productData(for productID: String) async throws -> ProductData? {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        return try await fetchProductData(productID: productID, username: creds.username, password: creds.password)
    }

    /// Fetches catalog/pricing data for a single product ID (ASIN, ISBN, UPC, or FNSKU).
    func catData(for productID: String) async throws -> CatData? {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        return try await fetchCatData(productID: productID, username: creds.username, password: creds.password)
    }

    func lookup(barcode: String) async throws -> LookupResult {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }
        let username = creds.username
        let password = creds.password

        async let productTask = fetchProductData(productID: barcode, username: username, password: password)
        async let catTask = fetchCatData(productID: barcode, username: username, password: password)

        // Both tasks start immediately; await sequentially to collect results
        let product = try await productTask
        let cat = try await catTask
        return LookupResult(barcode: barcode, productData: product, catData: cat)
    }

    // MARK: - Amazon Keyword Search

    /// GET /api/2.0/amz_keyword_search?keywords=...  — title-based ASIN search.
    func amzKeywordSearch(keywords: String) async throws -> [AmzSearchItem] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        var components = URLComponents(url: baseURL.appendingPathComponent("amz_keyword_search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "keywords", value: keywords)]
        guard let url = components.url else {
            throw AoBError.parseError("invalid keyword search URL")
        }

        var request = URLRequest(url: url)
        request.setValue(creds.username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(creds.password, forHTTPHeaderField: "AOB-AUTH-PW")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AoBError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AoBError.parseError("amz_keyword_search: invalid JSON")
        }

        if let errorsVal = json["errors"] {
            let detail: [String: Any]?
            if let dict = errorsVal as? [String: Any] { detail = dict }
            else if let arr = errorsVal as? [[String: Any]] { detail = arr.first }
            else { detail = nil }
            if let code = detail?["error_code"] as? Int, code != 0 {
                let text = detail?["error_text"] as? String ?? "Unknown error"
                if text.localizedCaseInsensitiveContains("bad token") { throw AoBError.missingCredentials }
                throw AoBError.apiError(code, text)
            }
        }

        guard let results = json["results"] as? [String: Any],
              let items = results["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { parseAmzSearchItem($0) }
    }

    private func parseAmzSearchItem(_ d: [String: Any]) -> AmzSearchItem? {
        guard let asin = d["asin"] as? String, !asin.isEmpty else { return nil }
        let summaries = d["summaries"] as? [[String: Any]] ?? []
        guard let s = summaries.first else { return nil }

        var author: String? = nil
        if let contributors = s["contributors"] as? [[String: Any]] {
            let authors = contributors.compactMap { c -> String? in
                guard let role = c["role"] as? [String: Any],
                      let roleValue = role["value"] as? String,
                      roleValue == "author",
                      let name = c["value"] as? String else { return nil }
                return name
            }
            if !authors.isEmpty {
                author = authors.joined(separator: ", ")
            } else if let first = contributors.first, let name = first["value"] as? String {
                author = name
            }
        }

        let browse = (s["browseClassification"] as? [String: Any])?["displayName"] as? String

        return AmzSearchItem(
            asin: asin,
            title: s["itemName"] as? String ?? "",
            author: author,
            brand: s["brand"] as? String,
            manufacturer: s["manufacturer"] as? String,
            releaseDate: s["releaseDate"] as? String,
            websiteDisplayGroup: s["websiteDisplayGroup"] as? String ?? "other",
            websiteDisplayGroupName: s["websiteDisplayGroupName"] as? String ?? "Other",
            browseClassification: browse
        )
    }

    // MARK: - Orders API

    /// GET /orders/<sublist>  — returns orders for the given sublist (N, H, A, P, C, 1-99).
    func fetchOrders(sublist: String = "N") async throws -> [AoBOrder] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        let url = baseURL.appendingPathComponent("orders/\(sublist)")
        var request = URLRequest(url: url)
        request.setValue(creds.username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(creds.password, forHTTPHeaderField: "AOB-AUTH-PW")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AoBError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AoBError.parseError("orders: invalid JSON")
        }

        // Surface API errors
        if let errorsVal = json["errors"] {
            let detail: [String: Any]?
            if let dict = errorsVal as? [String: Any] { detail = dict }
            else if let arr = errorsVal as? [[String: Any]] { detail = arr.first }
            else { detail = nil }
            if let code = detail?["error_code"] as? Int, code != 0 {
                let text = detail?["error_text"] as? String ?? "Unknown error"
                throw AoBError.apiError(code, text)
            }
        }

        // Response may be a direct order dict or wrapped under "results"
        let orderDict: [String: Any]
        if let results = json["results"] as? [String: Any] {
            orderDict = results
        } else {
            orderDict = json.filter { $0.key != "errors" }
        }

        var orders: [AoBOrder] = []
        for (orderId, value) in orderDict {
            guard let orderData = value as? [String: Any] else { continue }

            let itemsRaw = orderData["order_items"] as? [[String: Any]] ?? []
            let items: [AoBOrderItem] = itemsRaw.map { d in
                let qty: Int?
                if let q = d["qty"] as? Int { qty = q }
                else if let s = d["qty"] as? String { qty = Int(s) }
                else { qty = nil }

                let price: String?
                if let p = d["price"] as? String { price = p }
                else if let p = d["price"] as? Double { price = String(format: "%.2f", p) }
                else { price = nil }

                return AoBOrderItem(
                    id: d["order_item_id"] as? String ?? UUID().uuidString,
                    sku: d["sku"] as? String,
                    title: d["title"] as? String,
                    qty: qty,
                    price: price,
                    imageURL: d["image"] as? String,
                    source: d["source"] as? String,
                    location: d["location"] as? String,
                    media: d["media"] as? String,
                    lister: d["p2"] as? String
                )
            }

            orders.append(AoBOrder(
                id: orderId,
                buyerName: orderData["buyer_name"] as? String ?? orderData["name"] as? String,
                buyerEmail: orderData["buyer_email"] as? String ?? orderData["email"] as? String,
                orderDate: orderData["order_date"] as? String ?? orderData["date"] as? String,
                aobStatus: orderData["aob_status"] as? String,
                items: items
            ))
        }

        return orders.sorted { ($0.orderDate ?? "0") > ($1.orderDate ?? "0") }
    }

    /// POST /order_status  — moves a single order to the given aob_status (N, H, A, P, C, 1-99).
    func updateOrderStatus(orderId: String, aobStatus: String) async throws {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        let body = "order_id=\(orderId)&aob_status=\(aobStatus)"
        _ = try await post(endpoint: "order_status", body: body,
                           username: creds.username, password: creds.password)
    }

    // MARK: - Sales Stats

    struct SalesStat: Sendable, Identifiable {
        let id = UUID()
        let date: Date
        let venue: String
        let totalPrice: Double
        let totalQty: Int
        let totalCommission: Double
    }

    struct ListingStat: Sendable, Identifiable {
        let id = UUID()
        let lister: String
        let qtyListed: Int
    }

    /// GET /listing_stats[/year[/month[/day]]]
    func fetchListingStats(year: Int? = nil, month: Int? = nil, day: Int? = nil, week: Int? = nil) async throws -> [ListingStat] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        var path = "listing_stats"
        if let y = year {
            path += "/\(y)"
            if let m = month {
                path += "/\(String(format: "%02d", m))"
                if let d = day {
                    path += "/\(String(format: "%02d", d))"
                }
            }
        }

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent(path.components(separatedBy: "/")[0])
                .appendingPathComponent(path.components(separatedBy: "/").dropFirst().joined(separator: "/")),
            resolvingAgainstBaseURL: false
        )!

        if let w = week, year != nil, month == nil, day == nil {
            // Backend deployments differ on the expected week query key.
            components.queryItems = [
                URLQueryItem(name: "week", value: "\(w)"),
                URLQueryItem(name: "week_of_year", value: "\(w)"),
                URLQueryItem(name: "iso_week", value: "\(w)")
            ]
        }
        guard let url = components.url else { throw AoBError.networkError(URLError(.badURL)) }

        var request = URLRequest(url: url)
        request.setValue(creds.username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(creds.password, forHTTPHeaderField: "AOB-AUTH-PW")
        print("[AoB] GET \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AoBError.httpError(http.statusCode, "listing_stats")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AoBError.parseError("listing_stats: expected JSON object") }

        let rows: [[String: Any]]
        if let arr = json["results"] as? [[String: Any]] {
            rows = arr
        } else if let arr = json["results"] as? [Any] {
            rows = arr.compactMap { $0 as? [String: Any] }
        } else {
            return []
        }

        return rows.compactMap { row in
            guard let lister = row["lister"] as? String else { return nil }
            let qty: Int = {
                if let i = row["qty_listed"] as? Int { return i }
                if let s = row["qty_listed"] as? String { return Int(s) ?? 0 }
                return 0
            }()
            return ListingStat(lister: lister, qtyListed: qty)
        }
    }

    /// GET /sales_stats[/year[/month[/day]]]
    /// Pass nil for year to fetch all-time stats. Month/day are optional.
    func fetchSalesStats(year: Int? = nil, month: Int? = nil, day: Int? = nil) async throws -> [SalesStat] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        var path = "sales_stats"
        if let y = year {
            path += "/\(y)"
            if let m = month {
                path += "/\(String(format: "%02d", m))"
                if let d = day {
                    path += "/\(String(format: "%02d", d))"
                }
            }
        }

        let json = try await fetch(endpoint: path, username: creds.username, password: creds.password)

        let rows: [[String: Any]]
        if let arr = json["results"] as? [[String: Any]] {
            rows = arr
        } else if let arr = json["results"] as? [Any] {
            rows = arr.compactMap { $0 as? [String: Any] }
        } else {
            return []
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return rows.compactMap { row in
            guard let dateStr = row["st_date"] as? String,
                  let date = formatter.date(from: dateStr) else { return nil }
            let price = parseDouble(row["total_price"]) ?? 0
            let qty: Int = {
                if let i = row["total_qty"] as? Int { return i }
                if let s = row["total_qty"] as? String { return Int(s) ?? 0 }
                return 0
            }()
            let commission = parseDouble(row["total_commission"]) ?? 0
            let venue = (row["venue"] as? String) ?? "?"
            return SalesStat(date: date, venue: venue,
                             totalPrice: price, totalQty: qty, totalCommission: commission)
        }
    }

    // MARK: - Private fetch helpers

    private func post(endpoint: String, body: String, username: String, password: String) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(password, forHTTPHeaderField: "AOB-AUTH-PW")
        request.httpBody = Data(body.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AoBError.networkError(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(statusCode) {
            throw AoBError.httpError(statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AoBError.parseError("POST \(endpoint) (HTTP \(statusCode)): expected JSON object: \(raw.prefix(300))")
        }

        // AoB returns errors as either a dict {"error_code":N,...} or an array [{...}]
        // nested under the top-level "errors" key.
        if let errorsVal = json["errors"] {
            let detail: [String: Any]?
            if let dict = errorsVal as? [String: Any] {
                detail = dict
            } else if let arr = errorsVal as? [[String: Any]] {
                detail = arr.first
            } else {
                detail = nil
            }
            if let code = detail?["error_code"] as? Int, code != 0 {
                let text = detail?["error_text"] as? String ?? "Unknown error"
                if text.localizedCaseInsensitiveContains("bad token") { throw AoBError.missingCredentials }
                throw AoBError.apiError(code, text)
            }
        }

        return json
    }

    private func fetch(endpoint: String, username: String, password: String) async throws -> [String: Any] {
        let url = baseURL
            .appendingPathComponent(endpoint.components(separatedBy: "/")[0])
            .appendingPathComponent(endpoint.components(separatedBy: "/").dropFirst().joined(separator: "/"))
        var request = URLRequest(url: url)
        request.setValue(username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(password, forHTTPHeaderField: "AOB-AUTH-PW")

        print("[AoB] GET \(url.absoluteString)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AoBError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            print("[AoB] HTTP \(http.statusCode)")
            throw AoBError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let rawStr = String(data: data, encoding: .utf8) ?? "<binary>"
        print("[AoB] raw (\(data.count) bytes): \(rawStr.prefix(500))")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AoBError.parseError("Expected JSON object: \(rawStr.prefix(200))")
        }

        print("[AoB] top-level keys: \(json.keys.sorted())")
        if let results = json["results"] as? [String: Any] {
            print("[AoB] results keys: \(results.keys.sorted())")
        }

        if let errorsVal = json["errors"] {
            let detail: [String: Any]?
            if let dict = errorsVal as? [String: Any] {
                detail = dict
            } else if let arr = errorsVal as? [[String: Any]] {
                detail = arr.first
            } else {
                detail = nil
            }
            if let code = detail?["error_code"] as? Int, code != 0 {
                let text = detail?["error_text"] as? String ?? "Unknown error"
                if text.localizedCaseInsensitiveContains("bad token") { throw AoBError.missingCredentials }
                throw AoBError.apiError(code, text)
            }
        }

        return json
    }

    private func fetchProductData(productID: String, username: String, password: String) async throws -> ProductData? {
        let json = try await fetch(endpoint: "product_data/\(productID)", username: username, password: password)
        guard let results = json["results"] as? [String: Any] else {
            print("[AoB] product_data: no results key"); return nil
        }
        guard let productMap = results["product_data"] as? [String: Any] else {
            print("[AoB] product_data: results has no 'product_data' key, keys: \(results.keys.sorted())"); return nil
        }
        guard let firstEntry = productMap.values.first as? [String: Any] else {
            print("[AoB] product_data: productMap is empty or wrong type"); return nil
        }
        guard let pd = firstEntry["ProductData"] as? [String: Any] else {
            print("[AoB] product_data: firstEntry has no 'ProductData' key, keys: \((firstEntry as AnyObject))")
            return nil
        }

        return ProductData(
            asin: pd["asin"] as? String ?? productID,
            title: pd["title"] as? String ?? "",
            imageURL: pd["image"] as? String,
            author: pd["author"] as? String,
            publisher: pd["publisher"] as? String,
            releaseDate: pd["release_date"] as? String,
            media: pd["media"] as? String,
            weight: pd["weight"] as? String
        )
    }

    private func fetchCatData(productID: String, username: String, password: String) async throws -> CatData? {
        let json = try await fetch(endpoint: "cat_data/\(productID)", username: username, password: password)
        guard let results = json["results"] as? [String: Any] else {
            print("[AoB] cat_data: no results key"); return nil
        }
        guard let cd = results["cat_data"] as? [String: Any] else {
            print("[AoB] cat_data: results has no 'cat_data' key, keys: \(results.keys.sorted())"); return nil
        }

        let asin = results["asin"] as? String ?? productID
        let upcStr = cd["upc"] as? String
        let upc = (upcStr?.isEmpty == false) ? upcStr : nil

        let salesRank = parseDouble(cd["sales_rank"]).map { Int($0) } ?? 999_999_999
        let buyPrice = parseDouble(cd["buy_price"]) ?? 0
        let abeMargin = parseDouble(cd["abe_margin"]) ?? 0
        let amzMargin = parseDouble(cd["amz_margin"]) ?? 0
        let minMargin = parseDouble(cd["min_margin"]) ?? 0

        return CatData(
            asin: asin,
            upc: upc,
            salesRank: salesRank,
            salesRankHistory: parsePerlHistory(cd["sales_rank_history"] as? String),
            buyPrice: buyPrice,
            buyPriceHistory: parsePerlHistory(cd["buy_price_history"] as? String),
            abeMargin: abeMargin,
            amzMargin: amzMargin,
            minMargin: minMargin
        )
    }

    // Handles JSON values that may be String, Double, or Int
    private func parseDouble(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    // MARK: - eBay Categories API

    /// GET /api/2.0/ebay_categories/ — returns the full eBay category tree.
    func fetchEbyCategories() async throws -> [EbayCategory] {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        let url = baseURL.appendingPathComponent("ebay_categories/")
        var request = URLRequest(url: url)
        request.setValue(creds.username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(creds.password, forHTTPHeaderField: "AOB-AUTH-PW")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        let decoder = JSONDecoder()

        // Plain array (unlikely but handle it)
        if let arr = try? decoder.decode([EbayCategory].self, from: data) { return arr }

        // API returns a single root wrapper: {"name":"eBay Categories","children":[...]}
        // The root has no "id", so decode its children array directly.
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let childrenObj = root["children"] ?? []
            if let childrenData = try? JSONSerialization.data(withJSONObject: childrenObj),
               let arr = try? decoder.decode([EbayCategory].self, from: childrenData) {
                return arr
            }
        }

        throw AoBError.parseError("ebay_categories: unexpected format")
    }

    /// GET /api/2.0/ebay_categories/{id} — returns condition codes and item specifics for a category.
    func fetchEbyCategorySpecifics(id: String) async throws -> EbaySpecificsData {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        let url = baseURL.appendingPathComponent("ebay_categories/\(id)")
        var request = URLRequest(url: url)
        request.setValue(creds.username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(creds.password, forHTTPHeaderField: "AOB-AUTH-PW")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        return (try? JSONDecoder().decode(EbaySpecificsData.self, from: data))
            ?? EbaySpecificsData(condition_codes: nil, itemspecifics: nil)
    }

    // MARK: - eBay Business Policies

    struct BusinessPolicies: Sendable {
        struct Policy: Sendable, Identifiable {
            let id: String
            let name: String
        }
        let shipping: [Policy]
        let returnPolicies: [Policy]
    }

    /// GET /api/2.0/ebay_business_policies — returns shipping and return policy options.
    func fetchBusinessPolicies() async throws -> BusinessPolicies {
        guard let creds = try? await SharedCredentialsService.shared.getAoBCredentials()
        else { throw AoBError.missingCredentials }

        let url = baseURL.appendingPathComponent("ebay_business_policies")
        var request = URLRequest(url: url)
        request.setValue(creds.username, forHTTPHeaderField: "AOB-AUTH-USER")
        request.setValue(creds.password, forHTTPHeaderField: "AOB-AUTH-PW")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AoBError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AoBError.parseError("ebay_business_policies: unexpected format")
        }

        let shippingDict = root["shipping"] as? [String: String] ?? [:]
        let returnDict   = root["return"]   as? [String: String] ?? [:]

        let shipping = shippingDict
            .map { BusinessPolicies.Policy(id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
        let returns = returnDict
            .map { BusinessPolicies.Policy(id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }

        return BusinessPolicies(shipping: shipping, returnPolicies: returns)
    }

    // MARK: - Perl Data::Dumper parser

    // Parses Perl Data::Dumper hash strings: $VAR1 = {'timestamp' => value, ...};
    private func parsePerlHistory(_ str: String?) -> [TimeInterval: Double] {
        guard let str else { return [:] }
        guard let regex = try? NSRegularExpression(pattern: #"'(\d+)'\s*=>\s*'?([\d.]+)'?"#) else { return [:] }
        var result: [TimeInterval: Double] = [:]
        let range = NSRange(str.startIndex..., in: str)
        for match in regex.matches(in: str, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: str),
                  let valRange = Range(match.range(at: 2), in: str),
                  let key = TimeInterval(str[keyRange]),
                  let val = Double(str[valRange])
            else { continue }
            result[key] = val
        }
        return result
    }
}
