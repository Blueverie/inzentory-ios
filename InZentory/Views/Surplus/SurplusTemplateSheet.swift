//
//  SurplusTemplateSheet.swift
//  InZentory
//

import SwiftUI

struct SurplusTemplateSheet: View {
    let data: SurplusTemplateData

    @State private var selectedTemplate: SurplusListingTemplate = .facebookGroups
    @State private var copiedRowIndex: Int? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Template", selection: $selectedTemplate) {
                    ForEach(SurplusListingTemplate.allCases) { template in
                        Text(template.displayName).tag(template)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                let rows = selectedTemplate.rows(from: data)
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        rowView(row, index: index, totalRows: rows)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Listing Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: selectedTemplate) { _, _ in
            copiedRowIndex = nil
        }
    }

    @ViewBuilder
    private func rowView(_ row: TemplateRow, index: Int, totalRows: [TemplateRow]) -> some View {
        switch row {
        case .copyField(let label, let value):
            CopyFieldRow(label: label, value: value, isCopied: copiedRowIndex == index) {
                copy(value, index: index)
            }
        case .copyBlock(let label, let text):
            CopyBlockRow(label: label, text: text, isCopied: copiedRowIndex == index) {
                copy(text, index: index)
            }
        case .infoField(let label, let value):
            InfoFieldRow(label: label, value: value)
        }
    }

    private func copy(_ string: String, index: Int) {
        UIPasteboard.general.string = string
        withAnimation(.easeInOut(duration: 0.15)) { copiedRowIndex = index }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) {
                if copiedRowIndex == index { copiedRowIndex = nil }
            }
        }
    }
}

// MARK: - Row Views

private struct CopyFieldRow: View {
    let label: String
    let value: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
            }
            Spacer(minLength: 8)
            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .accentColor)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

private struct CopyBlockRow: View {
    let label: String
    let text: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCopy) {
                    Label(isCopied ? "Copied" : "Copy All",
                          systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct InfoFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Preview

#Preview {
    SurplusTemplateSheet(data: SurplusTemplateData(
        title: "Stanley 40oz Quencher Tumbler",
        description: "Stainless steel vacuum-insulated tumbler. Keeps drinks cold 24 hrs.",
        condition: "New",
        ebayCondition: "New with tags",
        notes: "Original packaging, unopened",
        rspPrice: 29.95,
        msrp: 49.99,
        price: 34.95,
        cost: 12.00,
        sku: "SUR-98765",
        brand: "Stanley",
        ebayCatName: "Kitchen & Dining",
        weightOz: 22.0,
        lengthIn: 9.5,
        widthIn: 4.5,
        depthIn: 4.5,
        shippingRate: EasyPostClient.Rate(carrier: "USPS", service: "Priority", rate: 8.75, deliveryDays: 3)
    ))
}
