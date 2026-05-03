//
//  MainTabView.swift
//  InZentory

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AppNavigator.self)  private var navigator
    @Environment(AppSettings.self)  private var settings
    @Environment(OrdersService.self) private var ordersService

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.selectedTab) {
            ForEach(settings.tabOrder) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.label, systemImage: tab.icon) }
                    .badge(tab == .ship ? ordersService.badgeCount : 0)
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView() }
        case .list:
            NavigationStack { ListFormView() }
        case .activity:
            NavigationStack { ActivityView() }
        case .inventory:
            NavigationStack { InventoryView() }
        case .ship:
            NavigationStack { ShipView() }
        case .source:
            NavigationStack { SourceView() }
        case .audit:
            AuditView()
        case .stats:
            NavigationStack { StatsView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: ListingItem.self, inMemory: true)
        .environment(OrdersService.shared)
        .environment(AppSettings.shared)
}
