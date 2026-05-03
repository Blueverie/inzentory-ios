//
//  SourceDetailView.swift
//  InZentory
//

import SwiftUI

struct SourceDetailView: View {
    @Environment(SourcesService.self) private var sourcesService
    @Environment(\.dismiss) private var dismiss

    /// Identifier of the SourceRecord we're displaying. The latest copy is read
    /// from `SourcesService` so any mutation re-renders the view.
    let sourceId: Int

    @State private var newCostLabel = ""
    @State private var newCostPrice = ""
    @State private var showCloseConfirm = false
    @State private var isMutating = false
    @State private var errorMessage: String?

    /// Local edit buffer for name/date so we only PUT on commit.
    @State private var editedName: String = ""
    @State private var editedDate: Date = Date()
    @State private var editedNotes: String = ""
    @State private var hasLoadedEdits = false

    private var source: SourceRecord? {
        sourcesService.source(id: sourceId)
    }

    private var sortedCosts: [SourceCost] {
        guard let source else { return [] }
        return source.costs.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        Group {
            if let source {
                form(for: source)
            } else {
                ContentUnavailableView("Source not found", systemImage: "questionmark.folder")
            }
        }
        .keyboardDoneButton()
        .navigationTitle(source?.name ?? "Source")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMutating {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            } else if let source, source.state == .open, hasEdits(source) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await saveEdits() } }
                }
            }
        }
        .onAppear { loadEditsIfNeeded() }
        .confirmationDialog(
            "Close this source? It won't appear in the lister picker anymore.",
            isPresented: $showCloseConfirm,
            titleVisibility: .visible
        ) {
            Button("Close Source", role: .destructive) {
                Task { await closeSource() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func form(for source: SourceRecord) -> some View {
        Form {
            detailsSection(for: source)
            kindSpecificSection(for: source)
            totalSection(for: source)

            if source.state == .open {
                Section {
                    Button(role: .destructive) {
                        showCloseConfirm = true
                    } label: {
                        Label("Close Source", systemImage: "lock.fill")
                    }
                    .disabled(isMutating)
                }
            } else {
                Section {
                    Button {
                        Task { await reopenSource() }
                    } label: {
                        Label("Reopen Source", systemImage: "lock.open.fill")
                    }
                    .disabled(isMutating)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private func detailsSection(for source: SourceRecord) -> some View {
        Section("Details") {
            if source.state == .open {
                TextField("Name", text: $editedName)
                DatePicker("Date", selection: $editedDate, displayedComponents: .date)
                TextField("Notes", text: $editedNotes, axis: .vertical)
                    .lineLimit(1...4)
            } else {
                LabeledContent("Name", value: source.name)
                LabeledContent("Date", value: source.date.formatted(date: .abbreviated, time: .omitted))
                if let closedAt = source.closedAt {
                    LabeledContent("Closed", value: closedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let notes = source.notes, !notes.isEmpty {
                    LabeledContent("Notes", value: notes)
                }
            }
            LabeledContent("Type", value: source.kind.displayName)
            HStack {
                Text("Status")
                Spacer()
                Text(source.state == .open ? "Open" : "Closed")
                    .foregroundStyle(source.state == .open ? .green : .secondary)
            }
        }
    }

    @ViewBuilder
    private func kindSpecificSection(for source: SourceRecord) -> some View {
        switch source.kind {
        case .bulk:
            bulkCostsSection(for: source)
        case .itemized:
            Section("Itemized") {
                Text("Itemized cost tracking is coming soon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .auction:
            Section("Auction") {
                Text("Auction tracking is coming soon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func totalSection(for source: SourceRecord) -> some View {
        Section("Total Cost") {
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text(money(source.totalCost))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func bulkCostsSection(for source: SourceRecord) -> some View {
        Section("Costs") {
            if source.costs.isEmpty {
                Text("No costs added yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if source.state == .open {
                ForEach(sortedCosts) { cost in costRow(cost) }
                    .onDelete { offsets in
                        Task { await deleteCosts(at: offsets, source: source) }
                    }
            } else {
                ForEach(sortedCosts) { cost in costRow(cost) }
            }

            if source.state == .open {
                addCostRow(source: source)
            }
        }
    }

    @ViewBuilder
    private func costRow(_ cost: SourceCost) -> some View {
        HStack {
            Text((cost.label?.isEmpty == false ? cost.label : "Untitled") ?? "Untitled")
            Spacer()
            Text(money(cost.price))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func addCostRow(source: SourceRecord) -> some View {
        HStack(spacing: 8) {
            TextField("Type (e.g. Box, Lot)", text: $newCostLabel)
            TextField("0.00", text: $newCostPrice)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Button {
                Task { await addCost(to: source) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .disabled(!canAddCost || isMutating)
        }
    }

    private var canAddCost: Bool {
        Double(newCostPrice.replacingOccurrences(of: ",", with: ".")) != nil
    }

    // MARK: - Actions

    private func loadEditsIfNeeded() {
        guard !hasLoadedEdits, let source else { return }
        editedName = source.name
        editedDate = source.date
        editedNotes = source.notes ?? ""
        hasLoadedEdits = true
    }

    private func hasEdits(_ source: SourceRecord) -> Bool {
        guard hasLoadedEdits else { return false }
        let trimmedName = editedName.trimmingCharacters(in: .whitespaces)
        if trimmedName != source.name && !trimmedName.isEmpty { return true }
        if !Calendar.current.isDate(editedDate, inSameDayAs: source.date) { return true }
        if (editedNotes.trimmingCharacters(in: .whitespaces)) != (source.notes ?? "") { return true }
        return false
    }

    private func saveEdits() async {
        guard let source else { return }
        let trimmedName = editedName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isMutating = true
        errorMessage = nil
        do {
            var payload = APIClient.SourceUpdatePayload()
            if trimmedName != source.name { payload.name = trimmedName }
            if !Calendar.current.isDate(editedDate, inSameDayAs: source.date) { payload.date = editedDate }
            let trimmedNotes = editedNotes.trimmingCharacters(in: .whitespaces)
            if trimmedNotes != (source.notes ?? "") { payload.notes = trimmedNotes }
            _ = try await sourcesService.update(id: source.id, payload)
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    private func addCost(to source: SourceRecord) async {
        let price = Double(newCostPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
        let label = newCostLabel.trimmingCharacters(in: .whitespaces)
        isMutating = true
        errorMessage = nil
        do {
            _ = try await sourcesService.addCost(
                sourceId: source.id,
                label: label.isEmpty ? nil : label,
                price: price
            )
            newCostLabel = ""
            newCostPrice = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    private func deleteCosts(at offsets: IndexSet, source: SourceRecord) async {
        let sorted = sortedCosts
        isMutating = true
        errorMessage = nil
        for idx in offsets {
            let cost = sorted[idx]
            do {
                try await sourcesService.deleteCost(sourceId: source.id, costId: cost.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isMutating = false
    }

    private func closeSource() async {
        guard let source else { return }
        isMutating = true
        errorMessage = nil
        do {
            _ = try await sourcesService.close(id: source.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    private func reopenSource() async {
        guard let source else { return }
        isMutating = true
        errorMessage = nil
        do {
            _ = try await sourcesService.reopen(id: source.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }
}
