//
//  SettingsView.swift
//  InZentory
//
//  Created by Blueverie on 3/12/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        List {
            Section("Account") {
                NavigationLink(destination: SettingsPlaceholder("Marketplaces")) {
                    Label("Marketplaces", systemImage: "storefront")
                }
                NavigationLink(destination: CredentialsView()) {
                    Label("Credentials", systemImage: "key")
                }
            }

            Section("Listing") {
                NavigationLink(destination: ListingDefaultsView()) {
                    Label("Listing Defaults", systemImage: "list.bullet.clipboard")
                }
            }

            Section("Scanning") {
                NavigationLink(destination: SettingsPlaceholder("Barcode Settings")) {
                    Label("Barcode Settings", systemImage: "barcode")
                }
                NavigationLink(destination: ScoutSettingsView()) {
                    Label("Scout Defaults", systemImage: "magnifyingglass")
                }
            }

            Section("Printing") {
                NavigationLink(destination: PrintNodeSettingsView()) {
                    Label("Label Printer", systemImage: "printer.dotmatrix")
                }
            }

            Section("Shipping") {
                NavigationLink(destination: SettingsPlaceholder("Postage Accounts")) {
                    Label("Postage Accounts", systemImage: "printer")
                }
                NavigationLink(destination: SettingsPlaceholder("Box Presets")) {
                    Label("Box Presets", systemImage: "shippingbox")
                }
            }

            Section("App") {
                NavigationLink(destination: TabOrderView()) {
                    Label("Tab Order", systemImage: "rectangle.3.group")
                }
                NavigationLink(destination: SettingsPlaceholder("About")) {
                    Label("About", systemImage: "info.circle")
                }
            }

            Section {
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Label("Log Out (\(auth.username ?? ""))", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPlaceholder: View {
    let name: String
    init(_ name: String) { self.name = name }

    var body: some View {
        ContentUnavailableView(
            name,
            systemImage: "square.dashed",
            description: Text("Coming soon.")
        )
        .navigationTitle(name)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
