//
//  CredentialsView.swift
//  InZentory
//

import SwiftUI

struct CredentialsView: View {
    @State private var aobLoaded      = false
    @State private var spacesLoaded   = false
    @State private var printLoaded    = false
    @State private var easyPostLoaded = false
    @State private var lastError: String?
    @State private var isRefreshing   = false

    var body: some View {
        List {
            Section {
                statusRow("Art of Books", loaded: aobLoaded)
                statusRow("DigitalOcean Spaces", loaded: spacesLoaded)
                statusRow("PrintNode", loaded: printLoaded)
                statusRow("EasyPost", loaded: easyPostLoaded)
            } header: {
                Text("Services")
            } footer: {
                if let err = lastError {
                    Text(err).foregroundStyle(.red)
                } else {
                    Text("Credentials are managed server-side and loaded automatically at sign-in.")
                }
            }

            Section {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Refreshing…")
                        }
                    } else {
                        Label("Refresh Credentials", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .navigationTitle("Credentials")
        .task { await loadStatus() }
    }

    @ViewBuilder
    private func statusRow(_ name: String, loaded: Bool) -> some View {
        Label {
            Text(name)
        } icon: {
            Image(systemName: loaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(loaded ? .green : .red)
        }
    }

    private func loadStatus() async {
        let status = await SharedCredentialsService.shared.loadStatus()
        let error  = await SharedCredentialsService.shared.lastError
        aobLoaded      = status.aob
        spacesLoaded   = status.spaces
        printLoaded    = status.printNode
        easyPostLoaded = status.easyPost
        lastError      = error
    }

    private func refresh() async {
        isRefreshing = true
        guard let token = Keychain.load(forKey: AuthService.tokenKeychainKey) else {
            lastError = "No auth token found — try signing out and back in."
            isRefreshing = false
            return
        }
        await SharedCredentialsService.shared.configure(token: token)
        await loadStatus()
        isRefreshing = false
    }
}

#Preview {
    NavigationStack { CredentialsView() }
}
