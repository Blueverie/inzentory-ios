//
//  AuditEngine.swift
//  InZentory
//

import Foundation

// MARK: - Result model

struct AuditItemResult: Identifiable, Sendable {
    let id: UUID
    let item: AoBClient.AoBItem
    let catData: AoBClient.CatData?
    let verdict: Verdict
    var isDeleted: Bool
    /// Non-nil when the item's location was overridden during the audit upload
    /// (i.e. user chose "Move to [location]" on a mismatch). Used for display
    /// and for any subsequent delete upload.
    var effectiveLocation: String?
    /// Tracks the qty as updated by the user after initial processing.
    /// Falls back to `item.qty` when nil (i.e. no update yet).
    var currentQty: Int?

    enum Verdict: Sendable {
        /// At least one margin >= 0 — list_flags reset to 0, item stays in inventory.
        case retain
        /// Both margins < 0 — qty automatically set to 0 during processing.
        case autoDeleted
    }

    init(item: AoBClient.AoBItem, catData: AoBClient.CatData?,
         verdict: Verdict, isDeleted: Bool = false, effectiveLocation: String? = nil) {
        self.id                = UUID()
        self.item              = item
        self.catData           = catData
        self.verdict           = verdict
        self.isDeleted         = isDeleted
        self.effectiveLocation = effectiveLocation
        self.currentQty        = item.qty
    }
}

// MARK: - Engine

@Observable final class AuditEngine {

    // MARK: State

    enum State {
        case idle
        case loading
        case notFound
        /// Multiple items found and none match the entered location (or no location given).
        /// The associated value is the full result set so the user can pick a location.
        case locationPicker(items: [AoBClient.AoBItem])
        /// The scanned item exists in one location that differs from the entered location,
        /// AND at least one result is retained (deleted items don't need a location decision).
        /// Items have already been processed/uploaded with their original location.
        /// User must choose whether to keep that location or re-upload to the entered one.
        case locationMismatch(results: [AuditItemResult], itemLocation: String, enteredLocation: String)
        case singleResult(AuditItemResult)
        case multiResult([AuditItemResult])
        /// A move-location operation completed successfully.
        case moved(item: AoBClient.AoBItem, toLocation: String)
        case error(String)
    }

    var state: State = .idle

    /// Incremented each time a new audit result is produced (singleResult or multiResult).
    /// Use this with `.onChange` instead of observing `State` directly, since `State`
    /// has associated values that don't conform to `Equatable`.
    private(set) var resultChangeCount: Int = 0

    // MARK: - Session tracking

    /// SKUs that have been individually scanned and processed this session.
    /// Persists for the lifetime of this engine instance (i.e. the current AuditView session).
    private(set) var scannedSKUs: Set<String> = []

    /// How many items were skipped on the most recent "Load Entire Location" because
    /// they were already in `scannedSKUs`. Reset to 0 before each load.
    private(set) var lastLoadSkippedCount: Int = 0

    // MARK: - Input Classification

    /// Maps raw barcode / manual input → the correct AoB item query key + value.
    ///
    /// Rules (digit-count based):
    /// - 13 digits starting with "978" → convert to ISBN-10, query by `isbn`
    /// - Exactly 10 digits           → query by `isbn`
    /// - 12+ digits (not 978-ISBN13) → query by `upc`
    /// - Anything else               → query by `sku`
    static func classifyInput(_ raw: String) -> (key: String, value: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits  = trimmed.filter(\.isNumber)

        if digits.count == 13, digits.hasPrefix("978") {
            return ("isbn", isbn13ToIsbn10(digits))
        } else if digits.count == 10 {
            return ("isbn", trimmed)
        } else if digits.count >= 12 {
            // Scanners often emit UPC-A (12 digits) as EAN-13 with a leading "0".
            // Strip that zero so the query matches what AoB stored.
            let upc = (digits.count == 13 && digits.hasPrefix("0")) ? String(digits.dropFirst()) : digits
            return ("upc", upc)
        } else {
            return ("sku", trimmed)
        }
    }

    /// Converts a 13-digit ISBN-13 (978-prefix) to a 10-digit ISBN-10 with computed check digit.
    static func isbn13ToIsbn10(_ digits: String) -> String {
        guard digits.count == 13 else { return digits }
        let body = String(digits.dropFirst(3).prefix(9))
        var sum  = 0
        for (i, ch) in body.enumerated() {
            sum += (Int(String(ch)) ?? 0) * (10 - i)
        }
        let check = (11 - (sum % 11)) % 11
        return body + (check == 10 ? "X" : String(check))
    }

    // MARK: - Public API

    /// Look up a single SKU / ISBN / UPC / barcode, filtered by the entered location.
    func lookupSku(input: String, location: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        state = .loading
        do {
            let (key, value) = Self.classifyInput(trimmed)
            let items = try await AoBClient.shared.fetchItems(params: [key: value])
            guard !items.isEmpty else { state = .notFound; return }
            await resolveItems(items, enteredLocation: location)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Load all items for a given location and process each one.
    /// Only items with qty ≥ 1 are included — qty-0 items are skipped when
    /// loading an entire location (they are only audited on an explicit scan).
    /// Items already individually scanned this session are also skipped.
    func loadLocation(_ location: String) async {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        lastLoadSkippedCount = 0
        state = .loading
        do {
            let items   = try await AoBClient.shared.fetchItems(params: ["location": trimmed])
            let exact   = items.filter { ($0.location ?? "").caseInsensitiveCompare(trimmed) == .orderedSame }
            let inStock = exact.filter { ($0.qty ?? 0) > 0 }
            guard !inStock.isEmpty else { state = .notFound; return }

            // Skip items already processed individually this session.
            let unscanned = inStock.filter { !scannedSKUs.contains($0.sku) }
            lastLoadSkippedCount = inStock.count - unscanned.count

            guard !unscanned.isEmpty else { state = .notFound; return }

            let results = await processItems(unscanned)
            // loadLocation results are NOT added to scannedSKUs — they weren't
            // individually scanned, so they shouldn't block future individual lookups.
            setResultState(results.count == 1 ? .singleResult(results[0]) : .multiResult(results))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Called when the user picks a specific location from the picker.
    /// Originates from a scan, so qty-0 items are included.
    func selectLocation(_ location: String, from items: [AoBClient.AoBItem]) async {
        let matching = items.filter {
            ($0.location ?? "").caseInsensitiveCompare(location) == .orderedSame
        }
        guard !matching.isEmpty else { state = .notFound; return }

        state = .loading
        let results = await processItems(matching)
        markScanned(results)
        setResultState(results.count == 1 ? .singleResult(results[0]) : .multiResult(results))
    }

    /// Sends a qty=0 upload for a previously-retained result (user taps the Delete button).
    func deleteRetained(id: UUID) async {
        switch state {
        case .singleResult(var result) where result.id == id:
            do {
                try await AoBClient.shared.auditInventoryUpload(
                    item: result.item, qty: 0,
                    locationOverride: result.effectiveLocation)
                result.isDeleted = true
                state = .singleResult(result)
            } catch {
                state = .error(error.localizedDescription)
            }

        case .multiResult(var results):
            guard let idx = results.firstIndex(where: { $0.id == id }) else { return }
            do {
                try await AoBClient.shared.auditInventoryUpload(
                    item: results[idx].item, qty: 0,
                    locationOverride: results[idx].effectiveLocation)
                results[idx].isDeleted = true
                state = .multiResult(results)
            } catch {
                state = .error(error.localizedDescription)
            }

        default:
            break
        }
    }

    /// Re-uploads a retained result with a user-specified quantity, then updates the displayed qty.
    func updateQty(id: UUID, qty: Int) async {
        switch state {
        case .singleResult(var result) where result.id == id:
            do {
                try await AoBClient.shared.auditInventoryUpload(
                    item: result.item, qty: qty,
                    locationOverride: result.effectiveLocation)
                result.currentQty = qty
                state = .singleResult(result)
            } catch {
                state = .error(error.localizedDescription)
            }

        case .multiResult(var results):
            guard let idx = results.firstIndex(where: { $0.id == id }) else { return }
            do {
                try await AoBClient.shared.auditInventoryUpload(
                    item: results[idx].item, qty: qty,
                    locationOverride: results[idx].effectiveLocation)
                results[idx].currentQty = qty
                state = .multiResult(results)
            } catch {
                state = .error(error.localizedDescription)
            }

        default:
            break
        }
    }

    /// Called after the user resolves a location mismatch.
    /// Items were already processed/uploaded with their original location before this dialog appeared.
    /// - Parameters:
    ///   - keepOriginal: `true` → keep as-is (no re-upload needed).
    ///                   `false` → re-upload only retained items with `enteredLocation`.
    ///   - results: The pre-processed results from the `.locationMismatch` state.
    ///   - enteredLocation: The location the user had typed in.
    func resolveLocationMismatch(keepOriginal: Bool,
                                 results: [AuditItemResult],
                                 enteredLocation: String) async {
        if keepOriginal {
            // Already uploaded with the original location — just display.
            setResultState(results.count == 1 ? .singleResult(results[0]) : .multiResult(results))
            return
        }

        // Re-upload only retained items with the location override.
        state = .loading
        var updated = results
        for i in updated.indices {
            guard updated[i].verdict == .retain && !updated[i].isDeleted else { continue }
            let item = updated[i].item
            let retainQty = (item.qty ?? 0) > 0 ? item.qty! : 1
            try? await AoBClient.shared.auditInventoryUpload(item: item, qty: retainQty,
                                                              locationOverride: enteredLocation)
            updated[i].effectiveLocation = enteredLocation
        }
        setResultState(updated.count == 1 ? .singleResult(updated[0]) : .multiResult(updated))
    }

    /// Move item(s) matching `sku` to `toLocation` without performing an audit.
    /// If the barcode resolves to items in multiple distinct locations, transitions
    /// to `.locationPicker` so the user can select which copy to move.
    func moveItem(sku: String, toLocation: String) async {
        let skuTrimmed = sku.trimmingCharacters(in: .whitespaces)
        let locTrimmed = toLocation.trimmingCharacters(in: .whitespaces)
        guard !skuTrimmed.isEmpty, !locTrimmed.isEmpty else { return }

        state = .loading
        do {
            let (key, value) = Self.classifyInput(skuTrimmed)
            let items = try await AoBClient.shared.fetchItems(params: [key: value])
            guard !items.isEmpty else { state = .notFound; return }

            let distinctLocs = Set(items.compactMap { $0.location })
            if distinctLocs.count > 1 {
                // Ambiguous — let user choose which location to move from.
                state = .locationPicker(items: items)
                return
            }

            // Single location (or no location) — move all matching records.
            for item in items {
                let qty = item.qty ?? 0
                try await AoBClient.shared.auditInventoryUpload(item: item, qty: qty,
                                                                locationOverride: locTrimmed)
            }
            state = .moved(item: items[0], toLocation: locTrimmed)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Called after the user picks a source location in move mode.
    func confirmMoveFromLocation(_ location: String,
                                 items: [AoBClient.AoBItem],
                                 toLocation: String) async {
        let matching = items.filter {
            ($0.location ?? "").caseInsensitiveCompare(location) == .orderedSame
        }
        guard !matching.isEmpty else { state = .notFound; return }

        state = .loading
        do {
            for item in matching {
                let qty = item.qty ?? 0
                try await AoBClient.shared.auditInventoryUpload(item: item, qty: qty,
                                                                locationOverride: toLocation)
            }
            state = .moved(item: matching[0], toLocation: toLocation)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
    }

    // MARK: - Private

    /// Sets `state` to a singleResult/multiResult and bumps `resultChangeCount`
    /// so AuditView's `onChange(of: engine.resultChangeCount)` can fire the qty alert.
    private func setResultState(_ newState: State) {
        resultChangeCount += 1
        state = newState
    }

    private func resolveItems(_ items: [AoBClient.AoBItem], enteredLocation: String) async {
        let loc = enteredLocation.trimmingCharacters(in: .whitespaces)

        if !loc.isEmpty {
            let matching = items.filter {
                ($0.location ?? "").caseInsensitiveCompare(loc) == .orderedSame
            }
            if !matching.isEmpty {
                // Came from a scan — preserve qty-0 items.
                let results = await processItems(matching)
                markScanned(results)
                setResultState(results.count == 1 ? .singleResult(results[0]) : .multiResult(results))
                return
            }

            // No items in the entered location. If all items share a single distinct
            // (different) location, process them first, then only show the mismatch dialog
            // if at least one result is retained — deleted items don't need a location decision.
            let distinctLocs = Set(items.compactMap { $0.location })
            if distinctLocs.count == 1, let itemLoc = distinctLocs.first {
                let results = await processItems(items)
                markScanned(results)
                if results.allSatisfy({ $0.verdict == .autoDeleted || $0.isDeleted }) {
                    // All deleted — location is irrelevant, go straight to result display.
                    setResultState(results.count == 1 ? .singleResult(results[0]) : .multiResult(results))
                } else {
                    state = .locationMismatch(results: results,
                                              itemLocation: itemLoc,
                                              enteredLocation: loc)
                }
                return
            }
        }

        // No location set, or multiple distinct locations with no match — show picker
        // if ambiguous, otherwise auto-process.
        let distinctLocs = Set(items.compactMap { $0.location })
        if distinctLocs.count > 1 {
            state = .locationPicker(items: items)
        } else {
            let results = await processItems(items)
            markScanned(results)
            setResultState(results.count == 1 ? .singleResult(results[0]) : .multiResult(results))
        }
    }

    /// Concurrently processes each item: fetches cat_data and sends the appropriate upload.
    /// Pass `locationOverride` to move all items to a specific location in the upload.
    private func processItems(_ items: [AoBClient.AoBItem],
                              locationOverride: String? = nil) async -> [AuditItemResult] {
        typealias WorkResult = (item: AoBClient.AoBItem, catData: AoBClient.CatData?, verdict: AuditItemResult.Verdict)
        return await withTaskGroup(of: WorkResult.self) { group in
            for item in items {
                group.addTask { await AuditEngine.processItemStatic(item, locationOverride: locationOverride) }
            }
            var out: [AuditItemResult] = []
            for await r in group {
                out.append(AuditItemResult(item: r.item, catData: r.catData,
                                           verdict: r.verdict, effectiveLocation: locationOverride))
            }
            return out.sorted { $0.item.sku < $1.item.sku }
        }
    }

    /// Non-isolated static worker: fetches cat_data and sends the inventory_upload.
    /// Returns a plain tuple so the caller (on the main actor) constructs AuditItemResult.
    private nonisolated static func processItemStatic(
        _ item: AoBClient.AoBItem,
        locationOverride: String? = nil
    ) async -> (item: AoBClient.AoBItem, catData: AoBClient.CatData?, verdict: AuditItemResult.Verdict) {
        // Prefer ASIN for cat_data lookup (most reliable); fall back to isbn13, upc, sku
        let lookupId = item.asin ?? item.isbn ?? item.upc ?? item.sku
        let catData  = try? await AoBClient.shared.catData(for: lookupId)

        let verdict: AuditItemResult.Verdict
        if !isRecentlyListed(item) && (catData.map { $0.amzMargin < 0 && $0.abeMargin < 0 } ?? false) {
            verdict = .autoDeleted
            try? await AoBClient.shared.auditInventoryUpload(item: item, qty: 0,
                                                              locationOverride: locationOverride)
        } else {
            verdict = .retain
            // Always restore to at least qty 1 when retained — covers qty-0 items found via scan.
            let retainQty = (item.qty ?? 0) > 0 ? item.qty! : 1
            try? await AoBClient.shared.auditInventoryUpload(item: item, qty: retainQty,
                                                              locationOverride: locationOverride)
        }

        return (item, catData, verdict)
    }

    /// Records the SKU of each result in the session scan log.
    private func markScanned(_ results: [AuditItemResult]) {
        for result in results {
            scannedSKUs.insert(result.item.sku)
        }
    }

    /// Returns true if `item.dateListed` falls within the past 365 days.
    private nonisolated static func isRecentlyListed(_ item: AoBClient.AoBItem) -> Bool {
        guard let dateStr = item.dateListed, !dateStr.isEmpty else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 3600)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateStr) {
                return date > oneYearAgo
            }
        }
        return false
    }
}
