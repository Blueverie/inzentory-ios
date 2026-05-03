//
//  AppSettings.swift
//  InZentory
//

import Foundation

// MARK: - Scout mode

enum ScoutMode: String, CaseIterable {
    case sort, perItem, bagSale

    var displayName: String {
        switch self {
        case .sort:    return "Sort"
        case .perItem: return "Per Item"
        case .bagSale: return "Bag Sale"
        }
    }
}

struct ScoutCostEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var label: String
    var cost: Double

    init(id: UUID = UUID(), label: String, cost: Double) {
        self.id = id
        self.label = label
        self.cost = cost
    }
}

// MARK: - Label orientation

enum LabelOrientation: String, CaseIterable {
    /// Portrait PDF (90×162pt) with content rotated 90° inside the page.
    /// Default — prints correctly on Mac DYMO drivers.
    case portrait
    /// Landscape PDF (162×90pt) with content drawn normally (standard y-flip only).
    /// Use when the Mac-style portrait PDF prints sideways on Windows DYMO drivers.
    case landscape

    var displayName: String {
        switch self {
        case .portrait:  return "Portrait (Mac)"
        case .landscape: return "Landscape (Windows)"
        }
    }
}

// MARK: - Label format

enum LabelFormat: String, CaseIterable {
    case pdf
    case zpl

    var displayName: String {
        switch self {
        case .pdf: return "PDF (DYMO)"
        case .zpl: return "ZPL (Zebra)"
        }
    }
}

// MARK: - ZPL DPI

enum ZplDpi: Int, CaseIterable {
    case dpi203 = 203
    case dpi300 = 300

    var displayName: String { "\(rawValue) DPI" }
}

// MARK: -

@Observable final class AppSettings {
    static let shared = AppSettings()

    var minMargin: Double = 0 {
        didSet { UserDefaults.standard.set(minMargin, forKey: "minMargin") }
    }
    var lastSource: String = "" {
        didSet { UserDefaults.standard.set(lastSource, forKey: "lastSource") }
    }
    var lastLocation: String = "" {
        didSet { UserDefaults.standard.set(lastLocation, forKey: "lastLocation") }
    }
    var lastStoriesSource: String = "" {
        didSet { UserDefaults.standard.set(lastStoriesSource, forKey: "lastStoriesSource") }
    }
    var lastStoriesLocation: String = "" {
        didSet { UserDefaults.standard.set(lastStoriesLocation, forKey: "lastStoriesLocation") }
    }
    var lastSurplusSource: String = "" {
        didSet { UserDefaults.standard.set(lastSurplusSource, forKey: "lastSurplusSource") }
    }
    var lastSurplusLocation: String = "" {
        didSet { UserDefaults.standard.set(lastSurplusLocation, forKey: "lastSurplusLocation") }
    }

    func source(for type: ItemType) -> String {
        type == .media ? lastStoriesSource : lastSurplusSource
    }
    func location(for type: ItemType) -> String {
        type == .media ? lastStoriesLocation : lastSurplusLocation
    }
    func setSource(_ v: String, for type: ItemType) {
        if type == .media { lastStoriesSource = v } else { lastSurplusSource = v }
    }
    func setLocation(_ v: String, for type: ItemType) {
        if type == .media { lastStoriesLocation = v } else { lastSurplusLocation = v }
    }
    /// Notes phrases for the Stories (media) lister.
    var stockPhrases: [String] = [] {
        didSet { UserDefaults.standard.set(stockPhrases, forKey: "stockPhrases") }
    }
    /// Notes phrases for the Surplus lister (separate from Stories).
    var surplusNotesPhrases: [String] = [] {
        didSet { UserDefaults.standard.set(surplusNotesPhrases, forKey: "surplusNotesPhrases") }
    }
    /// Description phrases for the Surplus lister.
    var surplusDescriptionPhrases: [String] = [] {
        didSet { UserDefaults.standard.set(surplusDescriptionPhrases, forKey: "surplusDescriptionPhrases") }
    }

    // MARK: - Local draft-type cache
    // The InZentory backend may not store/return p9 on drafts, so we cache
    // the form type locally keyed by draft ID so re-opens land in the right form.

    private var localDraftTypes: [String: String] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(localDraftTypes) {
                UserDefaults.standard.set(data, forKey: "localDraftTypes")
            }
        }
    }

    func draftItemType(for id: Int) -> ItemType {
        // Prefer explicit "surplus"; anything else (including nil/missing) → media
        localDraftTypes[String(id)] == "surplus" ? .surplus : .media
    }

    func setDraftItemType(_ id: Int, _ type: ItemType) {
        localDraftTypes[String(id)] = type == .surplus ? "surplus" : "stories"
    }

    func clearDraftItemType(for id: Int) {
        localDraftTypes.removeValue(forKey: String(id))
    }

    // PrintNode
    var selectedPrinterId: Int = 0 {
        didSet { UserDefaults.standard.set(selectedPrinterId, forKey: "printNodePrinterId") }
    }
    var selectedPrinterName: String = "" {
        didSet { UserDefaults.standard.set(selectedPrinterName, forKey: "printNodePrinterName") }
    }
    var hiddenPrinterIds: Set<Int> = [] {
        didSet { UserDefaults.standard.set(Array(hiddenPrinterIds), forKey: "printNodeHiddenPrinterIds") }
    }
    var favoritePrinterIds: Set<Int> = [] {
        didSet { UserDefaults.standard.set(Array(favoritePrinterIds), forKey: "printNodeFavoritePrinterIds") }
    }
    var labelFormat: LabelFormat = .pdf {
        didSet { UserDefaults.standard.set(labelFormat.rawValue, forKey: "labelFormat") }
    }
    var labelOrientation: LabelOrientation = .portrait {
        didSet { UserDefaults.standard.set(labelOrientation.rawValue, forKey: "labelOrientation") }
    }
    var zplDpi: ZplDpi = .dpi203 {
        didSet { UserDefaults.standard.set(zplDpi.rawValue, forKey: "zplDpi") }
    }

    // Tab order
    static let defaultTabOrder: [AppTab] = [.home, .list, .activity, .inventory, .ship, .source, .audit, .stats, .settings]

    var tabOrder: [AppTab] = AppSettings.defaultTabOrder {
        didSet {
            UserDefaults.standard.set(tabOrder.map(\.rawValue), forKey: "tabOrder")
        }
    }

    // Scout
    var scoutMode: ScoutMode = .sort {
        didSet { UserDefaults.standard.set(scoutMode.rawValue, forKey: "scoutMode") }
    }
    var scoutCostEntries: [ScoutCostEntry] = [ScoutCostEntry(label: "Item", cost: 1.00)] {
        didSet {
            if let data = try? JSONEncoder().encode(scoutCostEntries) {
                UserDefaults.standard.set(data, forKey: "scoutCostEntries")
            }
        }
    }
    var scoutBagPrice: Double = 10.0 {
        didSet { UserDefaults.standard.set(scoutBagPrice, forKey: "scoutBagPrice") }
    }

    private init() {
        minMargin    = UserDefaults.standard.double(forKey: "minMargin")
        lastSource   = UserDefaults.standard.string(forKey: "lastSource") ?? ""
        lastLocation = UserDefaults.standard.string(forKey: "lastLocation") ?? ""
        // Migrate legacy combined keys → per-form keys on first run
        let legacySrc = UserDefaults.standard.string(forKey: "lastSource") ?? ""
        let legacyLoc = UserDefaults.standard.string(forKey: "lastLocation") ?? ""
        lastStoriesSource   = UserDefaults.standard.string(forKey: "lastStoriesSource")
            ?? (legacySrc.isEmpty ? "" : legacySrc)
        lastStoriesLocation = UserDefaults.standard.string(forKey: "lastStoriesLocation")
            ?? (legacyLoc.isEmpty ? "" : legacyLoc)
        lastSurplusSource   = UserDefaults.standard.string(forKey: "lastSurplusSource") ?? ""
        lastSurplusLocation = UserDefaults.standard.string(forKey: "lastSurplusLocation") ?? ""
        stockPhrases = UserDefaults.standard.stringArray(forKey: "stockPhrases")
            ?? ["Ex-Library", "Signed", "Book Club Edition", "Reading Copy", "First Edition",
                "Water Damage", "Remainder Mark", "Advance Reader Copy"]
        surplusNotesPhrases = UserDefaults.standard.stringArray(forKey: "surplusNotesPhrases") ?? []
        surplusDescriptionPhrases = UserDefaults.standard.stringArray(forKey: "surplusDescriptionPhrases") ?? []
        if let data = UserDefaults.standard.data(forKey: "localDraftTypes"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            localDraftTypes = dict
        }
        selectedPrinterId   = UserDefaults.standard.integer(forKey: "printNodePrinterId")
        selectedPrinterName = UserDefaults.standard.string(forKey: "printNodePrinterName") ?? ""
        let hidden = UserDefaults.standard.array(forKey: "printNodeHiddenPrinterIds") as? [Int] ?? []
        hiddenPrinterIds    = Set(hidden)
        let favorites = UserDefaults.standard.array(forKey: "printNodeFavoritePrinterIds") as? [Int] ?? []
        favoritePrinterIds  = Set(favorites)
        labelFormat         = LabelFormat(
            rawValue: UserDefaults.standard.string(forKey: "labelFormat") ?? ""
        ) ?? .pdf
        labelOrientation    = LabelOrientation(
            rawValue: UserDefaults.standard.string(forKey: "labelOrientation") ?? ""
        ) ?? .portrait
        zplDpi              = ZplDpi(
            rawValue: UserDefaults.standard.integer(forKey: "zplDpi")
        ) ?? .dpi203

        if let saved = UserDefaults.standard.stringArray(forKey: "tabOrder") {
            let decoded = saved.compactMap { AppTab(rawValue: $0) }
            // Merge: keep saved order, append any new tabs not yet in saved list
            let missing = AppSettings.defaultTabOrder.filter { !decoded.contains($0) }
            tabOrder = decoded + missing
        }

        scoutMode = ScoutMode(rawValue: UserDefaults.standard.string(forKey: "scoutMode") ?? "") ?? .sort
        if let data = UserDefaults.standard.data(forKey: "scoutCostEntries"),
           let entries = try? JSONDecoder().decode([ScoutCostEntry].self, from: data), !entries.isEmpty {
            scoutCostEntries = entries
        } else {
            scoutCostEntries = [ScoutCostEntry(label: "Item", cost: 1.00)]
        }
        let savedBagPrice = UserDefaults.standard.double(forKey: "scoutBagPrice")
        scoutBagPrice = savedBagPrice > 0 ? savedBagPrice : 10.0
    }
}
