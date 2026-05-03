//
//  HomeView.swift
//  InZentory
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(AuthService.self) private var authService
    @Query private var allItems: [ListingItem]

    private var listedCount: Int { allItems.filter { $0.status == .listed }.count }
    private var draftCount: Int  { allItems.filter { $0.status == .draft  }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("INZENTORY")
                        .font(.custom("Inconsolata-Bold", size: 28))
                        .tracking(4)
                    if let username = authService.username, !username.isEmpty {
                        Text("Welcome back, \(username)")
                            .font(.custom("Inconsolata-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                // Stats row
                HStack(spacing: 12) {
                    StatCard(value: "\(listedCount)", label: "Listed")
                    StatCard(value: "\(draftCount)", label: "Drafts")
                }

                // Quick actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("QUICK ACTIONS")
                        .font(.custom("Inconsolata-Bold", size: 11))
                        .tracking(2)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        ActionRow(
                            icon: "square.and.pencil",
                            title: "List an Item",
                            subtitle: "Create a new listing",
                            color: .blue
                        ) {
                            navigator.selectedTab = .list
                        }

                        ActionRow(
                            icon: "clock.arrow.circlepath",
                            title: "Activity",
                            subtitle: "View recent listings",
                            color: .orange
                        ) {
                            navigator.selectedTab = .activity
                        }

                        ActionRow(
                            icon: "archivebox",
                            title: "Inventory",
                            subtitle: "Browse all items",
                            color: .indigo
                        ) {
                            navigator.selectedTab = .inventory
                        }

                        ActionRow(
                            icon: "shippingbox",
                            title: "Ship",
                            subtitle: "Manage orders & pull lists",
                            color: .green
                        ) {
                            navigator.selectedTab = .ship
                        }

                        ActionRow(
                            icon: "cart",
                            title: "Source",
                            subtitle: "Track purchase sources",
                            color: .purple
                        ) {
                            navigator.selectedTab = .source
                        }

                        ActionRow(
                            icon: "checklist",
                            title: "Audit",
                            subtitle: "Audit inventory by location",
                            color: .teal
                        ) {
                            navigator.selectedTab = .audit
                        }

                        ActionRow(
                            icon: "chart.bar",
                            title: "Stats",
                            subtitle: "View sales & performance",
                            color: .pink
                        ) {
                            navigator.selectedTab = .stats
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("")
        .navigationBarHidden(true)
    }
}

// MARK: - Subviews

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.custom("Inconsolata-Bold", size: 32))
                .monospacedDigit()
            Text(label.uppercased())
                .font(.custom("Inconsolata-Regular", size: 11))
                .tracking(1.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.custom("Inconsolata-Bold", size: 16))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.custom("Inconsolata-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: ListingItem.self, inMemory: true)
    .environment(AppNavigator())
    .environment(AuthService())
    .environment(AppSettings.shared)
}
