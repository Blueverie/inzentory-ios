//
//  SourcesService.swift
//  InZentory
//
//  Holds the user's sourcing records, synced from the InZentory backend.
//

import Foundation

@MainActor
@Observable
final class SourcesService {
    static let shared = SourcesService()

    private(set) var sources: [SourceRecord] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    var openSources: [SourceRecord] {
        sources.filter { $0.state == .open }
    }

    func sources(kind: SourceKind, state: SourceState) -> [SourceRecord] {
        sources.filter { $0.kind == kind && $0.state == state }
    }

    func source(id: Int) -> SourceRecord? {
        sources.first(where: { $0.id == id })
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil
        do {
            let fresh = try await APIClient.shared.fetchSources()
            sources = sortedForDisplay(fresh)
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Mutations

    @discardableResult
    func create(name: String, kind: SourceKind, date: Date, notes: String?) async throws -> SourceRecord {
        let created = try await APIClient.shared.createSource(name: name, kind: kind, date: date, notes: notes)
        sources = sortedForDisplay(sources + [created])
        return created
    }

    @discardableResult
    func update(id: Int, _ payload: APIClient.SourceUpdatePayload) async throws -> SourceRecord {
        let updated = try await APIClient.shared.updateSource(id: id, payload)
        replace(updated)
        return updated
    }

    @discardableResult
    func close(id: Int) async throws -> SourceRecord {
        try await update(id: id, .init(state: SourceState.closed.rawValue))
    }

    @discardableResult
    func reopen(id: Int) async throws -> SourceRecord {
        try await update(id: id, .init(state: SourceState.open.rawValue))
    }

    func delete(id: Int) async throws {
        try await APIClient.shared.deleteSource(id: id)
        sources.removeAll { $0.id == id }
    }

    @discardableResult
    func addCost(sourceId: Int, label: String?, price: Double) async throws -> SourceCost {
        let cost = try await APIClient.shared.addSourceCost(sourceId: sourceId, label: label, price: price)
        if let idx = sources.firstIndex(where: { $0.id == sourceId }) {
            sources[idx].costs.append(cost)
            sources[idx].updatedAt = Date()
        }
        return cost
    }

    func deleteCost(sourceId: Int, costId: Int) async throws {
        try await APIClient.shared.deleteSourceCost(sourceId: sourceId, costId: costId)
        if let idx = sources.firstIndex(where: { $0.id == sourceId }) {
            sources[idx].costs.removeAll { $0.id == costId }
            sources[idx].updatedAt = Date()
        }
    }

    // MARK: - Internals

    private func replace(_ source: SourceRecord) {
        if let idx = sources.firstIndex(where: { $0.id == source.id }) {
            sources[idx] = source
        } else {
            sources.append(source)
        }
        sources = sortedForDisplay(sources)
    }

    private func sortedForDisplay(_ list: [SourceRecord]) -> [SourceRecord] {
        list.sorted { lhs, rhs in
            // Open before closed, then most recent date first.
            if lhs.state != rhs.state { return lhs.state == .open }
            return lhs.date > rhs.date
        }
    }
}
