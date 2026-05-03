//
//  SourceListView.swift
//  InZentory
//

import SwiftUI

/// Lists sources of a given kind, filtered by state. Used for resume (open) and history (closed).
struct SourceListView: View {
    let kind: SourceKind
    let state: SourceState

    @Environment(SourcesService.self) private var sourcesService

    private var sources: [SourceRecord] {
        sourcesService.sources(kind: kind, state: state)
    }

    var body: some View {
        Group {
            if sources.isEmpty {
                ContentUnavailableView(
                    state == .open ? "No open \(kind.displayName.lowercased()) sources" : "No closed \(kind.displayName.lowercased()) sources",
                    systemImage: "tray",
                    description: Text(state == .open ? "Open one from the Source tab." : "Sources you've closed will show up here.")
                )
            } else {
                List {
                    ForEach(sources) { source in
                        NavigationLink(value: source.id) {
                            row(source)
                        }
                    }
                }
            }
        }
        .navigationTitle(state == .open ? "Resume \(kind.displayName)" : "Closed \(kind.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sourcesService.refresh() }
    }

    @ViewBuilder
    private func row(_ source: SourceRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.body)
                Text(source.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(source.totalCost))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }
}
