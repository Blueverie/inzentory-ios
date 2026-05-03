//
//  ScoutSettingsView.swift
//  InZentory
//

import SwiftUI

struct ScoutSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var s = settings
        List {
            // MARK: Mode picker
            Section {
                Picker("Scouting Mode", selection: $s.scoutMode) {
                    ForEach(ScoutMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Mode")
            }

            // MARK: Mode-specific settings
            switch settings.scoutMode {

            case .sort:
                Section {
                    Label {
                        Text("Uses the same Buy Price vs. margin algorithm as the List tab. Buy = List, Borderline = Borderline, Reject = Reject.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

            case .perItem:
                Section {
                    ForEach(settings.scoutCostEntries.indices, id: \.self) { idx in
                        CostEntryRow(
                            label: Binding(
                                get: { settings.scoutCostEntries[idx].label },
                                set: { settings.scoutCostEntries[idx].label = $0 }
                            ),
                            cost: Binding(
                                get: { settings.scoutCostEntries[idx].cost },
                                set: { settings.scoutCostEntries[idx].cost = $0 }
                            )
                        )
                    }
                    .onDelete { settings.scoutCostEntries.remove(atOffsets: $0) }
                    .onMove  { settings.scoutCostEntries.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        settings.scoutCostEntries.append(ScoutCostEntry(label: "", cost: 1.00))
                    } label: {
                        Label("Add Cost Entry", systemImage: "plus")
                    }
                } header: {
                    Text("Cost Entries")
                } footer: {
                    Text("Each entry shows its own Buy/Reject verdict. Buy if Buy Price ≥ cost.")
                }

            case .bagSale:
                Section {
                    HStack {
                        Text("Bag Price")
                        Spacer()
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Price", value: $s.scoutBagPrice,
                                  format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }

                    let threshold = settings.scoutBagPrice / 25.0
                    HStack {
                        Image(systemName: "divide")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(String(format: "Cost per book: $%.2f (bag ÷ 25)", threshold))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Bag Price")
                } footer: {
                    Text("Buy if the book's Buy Price ≥ bag price ÷ 25.")
                }
            }
        }
        .navigationTitle("Scout Defaults")
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarLeading) {
                if settings.scoutMode == .perItem {
                    EditButton()
                }
            }
        }
    }
}

// MARK: - Cost entry row

private struct CostEntryRow: View {
    @Binding var label: String
    @Binding var cost: Double

    var body: some View {
        HStack(spacing: 8) {
            TextField("Label (e.g. Hardcover)", text: $label)
                .frame(maxWidth: .infinity)
            Divider()
            HStack(spacing: 2) {
                Text("$").foregroundStyle(.secondary)
                TextField("0.00", value: $cost,
                          format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScoutSettingsView()
    }
    .environment(AppSettings.shared)
}
