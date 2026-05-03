//
//  ListingsView.swift
//  InZentory
//
//  Created by Blueverie on 3/11/26.
//

import SwiftUI
import SwiftData

struct ListingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ListingItem.createdAt, order: .reverse) private var items: [ListingItem]
    @State private var filter: ListingStatus? = nil

    var filteredItems: [ListingItem] {
        guard let filter else { return items }
        return items.filter { $0.status == filter }
    }

    var emptyDescription: String {
        if let filter {
            return "No \(filter.displayName.lowercased()) items."
        }
        return "Items you scan will appear here."
    }

    var body: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No listings",
                    systemImage: "tray",
                    description: Text(emptyDescription)
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems) { item in
                    NavigationLink(destination: ListingDetailView(item: item)) {
                        ListingRowView(item: item)
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .navigationTitle("Listings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { filter = nil } label: {
                        Label("All", systemImage: filter == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(ListingStatus.allCases, id: \.self) { status in
                        Button { filter = status } label: {
                            Label(status.displayName, systemImage: filter == status ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(filter?.displayName ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            #endif
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredItems[index])
        }
    }
}

struct ListingRowView: View {
    let item: ListingItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(
                        item.type.displayName,
                        systemImage: item.type == .media ? "play.square.stack" : "shippingbox"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.location.isEmpty {
                    Text(item.location)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(status: item.status)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: ListingStatus

    var color: Color {
        switch status {
        case .draft: return .orange
        case .listed: return .green
        case .rejected: return .red
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        ListingsView()
    }
    .modelContainer(for: ListingItem.self, inMemory: true)
}
