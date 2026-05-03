//
//  InZentoryApp.swift
//  InZentory
//

import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home      = "home"
    case list      = "list"
    case activity  = "activity"
    case inventory = "inventory"
    case ship      = "ship"
    case source    = "source"
    case audit     = "audit"
    case stats     = "stats"
    case settings  = "settings"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:      return "Home"
        case .list:      return "List"
        case .activity:  return "Activity"
        case .inventory: return "Inventory"
        case .ship:      return "Ship"
        case .source:    return "Source"
        case .audit:     return "Audit"
        case .stats:     return "Stats"
        case .settings:  return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house"
        case .list:      return "square.and.pencil"
        case .activity:  return "clock.arrow.circlepath"
        case .inventory: return "archivebox"
        case .ship:      return "shippingbox"
        case .source:    return "cart"
        case .audit:     return "checklist"
        case .stats:     return "chart.bar"
        case .settings:  return "gear"
        }
    }
}

@Observable final class AppNavigator {
    var selectedTab: AppTab = .home
    var pendingBarcode: String? = nil
    var pendingTitle: String? = nil
    var pendingProductData: AoBClient.ProductData? = nil
    var pendingCatData: AoBClient.CatData? = nil
    /// Incremented each time new scan data is pushed. ListFormView observes
    /// this so it reloads even when the tab is already visible.
    var pendingVersion: Int = 0
    /// Set by ActivityView when the user taps Re-open; ListFormView consumes and clears it.
    var pendingReopenPayload: ReopenPayload? = nil
}

@main
struct InZentoryApp: App {

    static let bgTaskIdentifier = "com.inzentory.orders-refresh"

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: InZentoryApp.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            InZentoryApp.handleBackgroundRefresh(refreshTask)
        }
    }

    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // Reschedule before doing any work so we always have a next run queued
        scheduleBackgroundRefresh()

        let work = Task {
            await OrdersService.shared.refresh()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        // iOS enforces a system-wide minimum (~15 min); asking for 15 min is reasonable
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ListingItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var authService        = AuthService()
    @State private var navigator          = AppNavigator()
    @State private var ordersService      = OrdersService.shared
    @State private var ebayCategoryCache  = EbayCategoryCache.shared
    @State private var sourcesService     = SourcesService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environment(authService)
            .environment(navigator)
            .environment(AppSettings.shared)
            .environment(ordersService)
            .environment(ebayCategoryCache)
            .environment(sourcesService)
            .task { await authService.bootstrap() }
            .onChange(of: authService.isAuthenticated) { _, authenticated in
                if authenticated {
                    Task {
                        await requestNotificationPermission()
                        ordersService.startPolling()
                        // Prefetch eBay categories in the background after login.
                        // cachedOrFetch() is a no-op when the cache is fresh (< 30 days old).
                        await ebayCategoryCache.cachedOrFetch()
                        await sourcesService.refresh()
                    }
                    InZentoryApp.scheduleBackgroundRefresh()
                } else {
                    ordersService.stopPolling()
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: InZentoryApp.bgTaskIdentifier)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        }
        .modelContainer(sharedModelContainer)
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}
