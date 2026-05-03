//
//  SourceView.swift
//  InZentory
//

import SwiftUI

struct SourceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SourcesService.self) private var sourcesService

    @State private var showScout = false
    @State private var newSourceKind: SourceKind? = nil
    @State private var pendingNavigationId: Int? = nil

    var body: some View {
        List {
            // MARK: Scout section
            Section {
                Button {
                    showScout = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "binoculars.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scout")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Mode: \(settings.scoutMode.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Scout")
            }

            // MARK: Manage Sources
            Section {
                ForEach(SourceKind.allCases) { kind in
                    NavigationLink(destination: SourceKindActionsView(kind: kind, onOpenNew: { newSourceKind = kind })) {
                        Label(kind.displayName, systemImage: kind.icon)
                    }
                }
            } header: {
                Text("Manage Sources")
            }

            // MARK: Currently open sources (quick access)
            let openSources = sourcesService.openSources
            if !openSources.isEmpty {
                Section {
                    ForEach(openSources) { source in
                        NavigationLink(value: source.id) {
                            HStack {
                                Image(systemName: source.kind.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                    Text("\(source.kind.displayName) · \(source.date.formatted(.dateTime.month(.abbreviated).day()))")
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
                    }
                } header: {
                    Text("Currently Open")
                }
            }
        }
        .navigationTitle("Source")
        .refreshable { await sourcesService.refresh() }
        .task { if sourcesService.sources.isEmpty { await sourcesService.refresh() } }
        .navigationDestination(for: Int.self) { id in
            SourceDetailView(sourceId: id)
        }
        .navigationDestination(item: $pendingNavigationId) { id in
            SourceDetailView(sourceId: id)
        }
        .sheet(item: $newSourceKind) { kind in
            NewSourceSheet(kind: kind) { record in
                pendingNavigationId = record.id
            }
        }
        .fullScreenCover(isPresented: $showScout) {
            ScoutView()
        }
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }
}

/// Shown after tapping a kind ("Itemized", "Bulk", "Auction") in the Manage Sources section.
/// Offers New / Resume / Close actions for that kind.
private struct SourceKindActionsView: View {
    let kind: SourceKind
    var onOpenNew: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onOpenNew()
                } label: {
                    Label("Open New \(kind.displayName)", systemImage: "plus.circle.fill")
                }
                NavigationLink {
                    SourceListView(kind: kind, state: .open)
                } label: {
                    Label("Resume Existing", systemImage: "arrow.uturn.forward.circle")
                }
                NavigationLink {
                    SourceListView(kind: kind, state: .open)
                } label: {
                    Label("Close a Source", systemImage: "lock.circle")
                }
            }

            Section {
                NavigationLink {
                    SourceListView(kind: kind, state: .closed)
                } label: {
                    Label("Closed \(kind.displayName) Sources", systemImage: "archivebox")
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
