//
//  SourcePickerField.swift
//  InZentory
//

import SwiftUI

/// Dropdown field that lets the lister pick from currently-open SourceRecords.
/// Sources come from `SourcesService` (server-synced).
struct SourcePickerField: View {
    @Binding var source: String
    var placeholder: String = "Source"

    @Environment(SourcesService.self) private var sources

    var body: some View {
        let openSources = sources.openSources

        Menu {
            if openSources.isEmpty {
                Text("No open sources. Open one in the Source tab.")
            } else {
                ForEach(openSources) { record in
                    Button {
                        source = record.name
                    } label: {
                        HStack {
                            Text(record.name)
                            Spacer()
                            Text(record.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !source.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        source = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            HStack {
                Text(source.isEmpty ? placeholder : source)
                    .foregroundStyle(source.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}
