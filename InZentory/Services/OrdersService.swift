//
//  OrdersService.swift
//  InZentory
//
//  Background-polling service for AoB order lists.
//
//  • Fetches New (N), Hold (H), Aux Hold (A), Pulled (1), and Pending Pickup (2)
//    concurrently every 90 seconds while the app is running.
//  • Sends a local notification when new orders appear in the N list.
//  • Exposes badgeCount = |N| + |1| for the Ship tab badge and app icon badge.
//

import Foundation
import UserNotifications

// MARK: - Per-sublist metadata

struct OrderSublist: Identifiable, Equatable {
    let id: String        // AoB sublist code (N, H, A, 1, 2)
    let title: String     // Human-readable name
    let includesInBadge: Bool
}

// MARK: - Service

@MainActor
@Observable final class OrdersService {

    static let shared = OrdersService()

    // MARK: Public state

    /// All known sublists (in display order).
    let sublists: [OrderSublist] = [
        OrderSublist(id: "N", title: "New",           includesInBadge: true),
        OrderSublist(id: "H", title: "Hold",          includesInBadge: false),
        OrderSublist(id: "A", title: "Aux Hold",      includesInBadge: false),
        OrderSublist(id: "1", title: "Pulled",        includesInBadge: true),
        OrderSublist(id: "2", title: "Pickup",        includesInBadge: false),
    ]

    /// Orders keyed by sublist code.
    private(set) var ordersByList: [String: [AoBClient.AoBOrder]] = [:]

    /// True during a refresh cycle.
    private(set) var isRefreshing = false

    /// Last error from any fetch (cleared on next successful refresh).
    private(set) var lastError: String? = nil

    /// Total order count across badge-eligible sublists (N + 1).
    var badgeCount: Int {
        sublists
            .filter(\.includesInBadge)
            .reduce(0) { $0 + (ordersByList[$1.id]?.count ?? 0) }
    }

    // MARK: Private

    private var pollingTask: Task<Void, Never>?
    /// Order IDs seen on the FIRST fetch — used to suppress "new order" noise
    /// when the app cold-starts with existing orders.
    private var bootstrappedIds: Set<String> = []
    private var isBootstrapped = false

    static let pollInterval: Duration = .seconds(90)

    // MARK: - Polling control

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: OrdersService.pollInterval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isBootstrapped = false
        bootstrappedIds = []
        ordersByList = [:]
    }

    // MARK: - Manual refresh

    /// Fetches all sublists concurrently. Safe to call directly (e.g. pull-to-refresh).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError    = nil

        let codes = sublists.map(\.id)
        var fresh: [String: [AoBClient.AoBOrder]] = [:]

        await withTaskGroup(of: (String, [AoBClient.AoBOrder], Error?).self) { group in
            for code in codes {
                group.addTask {
                    do {
                        let orders = try await AoBClient.shared.fetchOrders(sublist: code)
                        return (code, orders, nil)
                    } catch {
                        return (code, [], error)
                    }
                }
            }
            for await (code, orders, error) in group {
                fresh[code] = orders
                if let error { lastError = error.localizedDescription }
            }
        }

        // Detect new "N" orders and notify (skip on first fetch)
        let newNOrders = fresh["N"] ?? []
        let newNIds    = Set(newNOrders.map(\.id))

        if isBootstrapped {
            let arrivedIds = newNIds.subtracting(bootstrappedIds)
            if !arrivedIds.isEmpty {
                let arrivedOrders = newNOrders.filter { arrivedIds.contains($0.id) }
                await sendNotification(for: arrivedOrders)
            }
        }

        // Merge arrived IDs into the bootstrap set for subsequent polls
        bootstrappedIds = bootstrappedIds.union(newNIds)
        isBootstrapped  = true

        ordersByList = fresh
        isRefreshing = false

        // Sync app-icon badge
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeCount)
    }

    // MARK: - Notifications

    private func sendNotification(for newOrders: [AoBClient.AoBOrder]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let count = newOrders.reduce(0) { $0 + $1.items.count }
        let firstTitle = newOrders.first?.items.first?.title

        let content          = UNMutableNotificationContent()
        content.sound        = .default
        content.badge        = badgeCount as NSNumber

        if newOrders.count == 1 {
            content.title = "New Order"
            if let title = firstTitle, !title.isEmpty {
                content.body = title
            } else {
                content.body = "\(count) item\(count == 1 ? "" : "s")"
            }
        } else {
            content.title = "\(newOrders.count) New Orders"
            content.body  = "\(count) item\(count == 1 ? "" : "s") to pull"
        }

        let request = UNNotificationRequest(
            identifier: "orders-new-\(UUID().uuidString)",
            content: content,
            trigger: nil   // deliver immediately
        )
        try? await center.add(request)
    }

    // MARK: - Helpers

    /// Returns the orders for a given sublist code (empty if not yet loaded).
    func orders(for code: String) -> [AoBClient.AoBOrder] {
        ordersByList[code] ?? []
    }
}
