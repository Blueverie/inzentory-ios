//
//  TabOrderView.swift
//  InZentory
//

import SwiftUI

struct TabOrderView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                ForEach(settings.tabOrder) { tab in
                    HStack(spacing: 14) {
                        Image(systemName: tab.icon)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        Text(tab.label)
                    }
                }
                .onMove { from, to in
                    settings.tabOrder.move(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text("Drag to reorder tabs. Changes take effect immediately.")
            }

            Section {
                Button("Reset to Default") {
                    settings.tabOrder = AppSettings.defaultTabOrder
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Tab Order")
        .environment(\.editMode, .constant(.active))
    }
}

#Preview {
    NavigationStack {
        TabOrderView()
            .environment(AppSettings.shared)
    }
}
