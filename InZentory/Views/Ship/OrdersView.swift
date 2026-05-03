//
//  OrdersView.swift
//  InZentory
//
//  Displays the five AoB ship lists (New, Hold, Aux Hold, Pulled, Pickup)
//  in a scrollable tab bar. Data is sourced from OrdersService, which
//  polls in the background and handles notifications.
//

import SwiftUI

struct OrdersView: View {
    @Environment(OrdersService.self) private var service
    @State private var selectedList = "N"

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            listContent
        }
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { refreshButton }
        .task { await service.refresh() }
        .refreshable { await service.refresh() }
    }

    // MARK: - Scrollable tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(service.sublists) { sub in
                    let count = service.orders(for: sub.id).count
                    TabPill(
                        title: sub.title,
                        count: count,
                        isSelected: selectedList == sub.id,
                        includesInBadge: sub.includesInBadge
                    )
                    .onTapGesture { selectedList = sub.id }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        let orders = service.orders(for: selectedList)

        if service.isRefreshing && orders.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if orders.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(orders) { order in
                        OrderCard(order: order)
                        Divider()
                    }
                }
            }
            .overlay(alignment: .top) {
                if service.isRefreshing {
                    ProgressView().scaleEffect(0.7).padding(.top, 6)
                }
            }
        }
    }

    private var emptyState: some View {
        let sub = service.sublists.first { $0.id == selectedList }
        return ContentUnavailableView(
            "No Orders",
            systemImage: "tray",
            description: Text("The \(sub?.title ?? selectedList) list is empty.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await service.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(service.isRefreshing)
        }
    }
}

// MARK: - Tab Pill

private struct TabPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let includesInBadge: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))

            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? .white : (includesInBadge ? .red : .secondary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isSelected
                            ? Color.white.opacity(0.3)
                            : (includesInBadge ? Color.red.opacity(0.12) : Color(.systemGray5)),
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor : Color(.systemBackground),
            in: Capsule()
        )
        .foregroundStyle(isSelected ? .white : .primary)
        .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : .clear, radius: 4, y: 2)
    }
}

// MARK: - Order Card

private struct OrderCard: View {
    let order: AoBClient.AoBOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let buyer = order.buyerName, !buyer.isEmpty {
                    Text(buyer)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text(order.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let date = order.orderDate, !date.isEmpty {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Items
            ForEach(order.items) { item in
                OrderItemRow(item: item)
            }

            // Footer: order ID + item count
            HStack {
                Text("Order \(order.id)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                let n = order.items.count
                Text("\(n) item\(n == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Order Item Row

private struct OrderItemRow: View {
    let item: AoBClient.AoBOrderItem

    private let coverW: CGFloat = 44
    private let coverH: CGFloat = 58

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover
            AsyncImage(url: item.imageURL.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: coverW, height: coverH)
                        .clipped()
                default:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: coverW, height: coverH)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Details
            VStack(alignment: .leading, spacing: 4) {
                if let qty = item.qty, qty > 1 {
                    Text("×\(qty)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }

                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if let location = item.location, !location.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(location)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let source = item.source, !source.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Price
            if let price = item.price, !price.isEmpty {
                Text("$\(price)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        OrdersView()
    }
    .environment(OrdersService.shared)
}
