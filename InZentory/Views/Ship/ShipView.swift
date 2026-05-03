//
//  ShipView.swift
//  InZentory
//

import SwiftUI

struct ShipView: View {
    var body: some View {
        List {
            NavigationLink(destination: PullListView()) {
                Label("Pull List", systemImage: "list.clipboard")
            }
            NavigationLink(destination: OrdersView()) {
                Label("Orders", systemImage: "shippingbox")
            }
            NavigationLink(destination: PostageView()) {
                Label("Print Postage", systemImage: "printer")
            }
        }
        .navigationTitle("Ship")
    }
}

struct PostageView: View {
    var body: some View {
        ContentUnavailableView(
            "Print Postage",
            systemImage: "printer",
            description: Text("Postage printing will appear here.")
        )
        .navigationTitle("Print Postage")
    }
}

#Preview {
    NavigationStack {
        ShipView()
    }
}
