//
//  EbayCategoryCache.swift
//  InZentory
//

import Foundation

/// Singleton that caches the eBay category tree on disk.
/// Fresh data is fetched at most once every 30 days; callers can force a refresh at any time.
@MainActor
@Observable final class EbayCategoryCache {
    static let shared = EbayCategoryCache()

    private(set) var categories: [EbayCategory] = []
    private(set) var isFetching = false
    private(set) var fetchError: String?
    private(set) var lastFetchedAt: Date?

    /// Maximum age before the cache is considered stale and a refresh is triggered.
    static let maxAge: TimeInterval = 30 * 24 * 3600   // 30 days

    private static let cacheURL: URL = {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ebay_categories.json")
    }()
    private static let lastFetchKey = "ebayCat.lastFetchedAt"

    private init() {
        lastFetchedAt = UserDefaults.standard.object(forKey: Self.lastFetchKey) as? Date
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cats = try? JSONDecoder().decode([EbayCategory].self, from: data) {
            categories = cats
        }
    }

    var isStale: Bool {
        guard let last = lastFetchedAt else { return true }
        return Date().timeIntervalSince(last) > Self.maxAge
    }

    /// Returns cached data immediately if it's within 30 days. Otherwise fetches from the API.
    /// Safe to call on every surplus form load — it's a no-op when the cache is fresh.
    func cachedOrFetch() async {
        guard categories.isEmpty || isStale else { return }
        await refresh()
    }

    /// Always fetches fresh data from the API and updates the on-disk cache.
    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        do {
            let cats = try await AoBClient.shared.fetchEbyCategories()
            categories = cats
            let now = Date()
            lastFetchedAt = now
            UserDefaults.standard.set(now, forKey: Self.lastFetchKey)
            if let data = try? JSONEncoder().encode(cats) {
                try? data.write(to: Self.cacheURL, options: .atomic)
            }
        } catch {
            fetchError = error.localizedDescription
        }
        isFetching = false
    }
}
