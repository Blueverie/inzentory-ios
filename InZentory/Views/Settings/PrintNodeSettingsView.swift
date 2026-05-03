//
//  PrintNodeSettingsView.swift
//  InZentory
//

import SwiftUI
import QuickLook

struct PrintNodeSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var printers: [PrintNodeClient.Printer] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var previewURL: URL? = nil

    private struct ComputerGroup: Identifiable {
        let id: Int
        let name: String
        var printers: [PrintNodeClient.Printer]
    }

    private var favoritePrinters: [PrintNodeClient.Printer] {
        printers.filter {
            settings.favoritePrinterIds.contains($0.id) &&
            !settings.hiddenPrinterIds.contains($0.id)
        }
    }

    private var visibleGroups: [ComputerGroup] {
        groupPrinters(printers.filter {
            !settings.hiddenPrinterIds.contains($0.id) &&
            !settings.favoritePrinterIds.contains($0.id)
        })
    }

    private var hiddenPrinters: [PrintNodeClient.Printer] {
        printers.filter { settings.hiddenPrinterIds.contains($0.id) }
    }

    private func groupPrinters(_ list: [PrintNodeClient.Printer]) -> [ComputerGroup] {
        var order: [Int] = []
        var groups: [Int: ComputerGroup] = [:]
        for p in list {
            if groups[p.computerId] == nil {
                order.append(p.computerId)
                groups[p.computerId] = ComputerGroup(id: p.computerId, name: p.computerName, printers: [])
            }
            groups[p.computerId]?.printers.append(p)
        }
        return order.compactMap { groups[$0] }
    }

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading printers…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let err = loadError {
                Section {
                    Text(err).foregroundStyle(.red)
                    Button("Retry") { Task { await loadPrinters() } }
                } footer: {
                    Text("Requires a PrintNode API key in Settings → Credentials.")
                }
            } else if printers.isEmpty {
                Section {
                    Text("No printers found")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Requires a PrintNode API key in Settings → Credentials.")
                }
            } else {
                if !favoritePrinters.isEmpty {
                    Section("Favorites") {
                        ForEach(favoritePrinters) { printer in
                            printerRow(printer)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        settings.favoritePrinterIds.remove(printer.id)
                                    } label: {
                                        Label("Unfavorite", systemImage: "star.slash")
                                    }
                                    .tint(.orange)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Hide", role: .destructive) {
                                        hide(printer)
                                    }
                                }
                        }
                    }
                }

                ForEach(visibleGroups) { group in
                    Section(group.name) {
                        ForEach(group.printers) { printer in
                            printerRow(printer)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        settings.favoritePrinterIds.insert(printer.id)
                                    } label: {
                                        Label("Favorite", systemImage: "star")
                                    }
                                    .tint(.yellow)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Hide", role: .destructive) {
                                        hide(printer)
                                    }
                                }
                        }
                    }
                }

                if !hiddenPrinters.isEmpty {
                    Section("Hidden") {
                        ForEach(hiddenPrinters) { printer in
                            hiddenPrinterRow(printer)
                                .swipeActions(edge: .trailing) {
                                    Button("Show") {
                                        settings.hiddenPrinterIds.remove(printer.id)
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }

            Section {
                Picker("Format", selection: Bindable(settings).labelFormat) {
                    ForEach(LabelFormat.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                if settings.labelFormat == .pdf {
                    Picker("Orientation", selection: Bindable(settings).labelOrientation) {
                        ForEach(LabelOrientation.allCases, id: \.self) { o in
                            Text(o.displayName).tag(o)
                        }
                    }
                }
                if settings.labelFormat == .zpl {
                    Picker("Printer DPI", selection: Bindable(settings).zplDpi) {
                        ForEach(ZplDpi.allCases, id: \.self) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                }
            } header: {
                Text("Label")
            } footer: {
                if settings.labelFormat == .pdf {
                    Text("Use Portrait for Mac-connected DYMO printers. Switch to Landscape if labels print sideways on a Windows-connected printer.")
                } else {
                    Text("Match the DPI setting to your Zebra printer's resolution. Most desktop Zebra printers (GK/GX/ZD series) use 203 DPI.")
                }
            }

            if settings.labelFormat == .pdf {
                Section("Debug") {
                    Button("Preview Test Label") {
                        let pdf = PrintNodeClient.makeLabelPDFData(
                            sku: "W12345", title: "The Great Gatsby", author: "Fitzgerald F",
                            asin: "", isbn: "9780743273565", upc: "", conditionRaw: 2,
                            orientation: settings.labelOrientation)
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("test_label.pdf")
                        try? pdf.write(to: url)
                        previewURL = url
                    }
                }
            }
        }
        .navigationTitle("Printing")
        .task { await loadPrinters() }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private func printerRow(_ printer: PrintNodeClient.Printer) -> some View {
        Button {
            settings.selectedPrinterId = printer.id
            settings.selectedPrinterName = printer.name
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(printer.name)
                        .foregroundStyle(.primary)
                    if !printer.description.isEmpty {
                        Text(printer.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !printer.online {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if settings.selectedPrinterId == printer.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    @ViewBuilder
    private func hiddenPrinterRow(_ printer: PrintNodeClient.Printer) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.name)
                    .foregroundStyle(.secondary)
                Text(printer.computerName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("Swipe to show")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func hide(_ printer: PrintNodeClient.Printer) {
        settings.hiddenPrinterIds.insert(printer.id)
        if settings.selectedPrinterId == printer.id {
            settings.selectedPrinterId = 0
            settings.selectedPrinterName = ""
        }
    }

    private func loadPrinters() async {
        isLoading = true
        loadError = nil
        do {
            printers = try await PrintNodeClient.shared.fetchPrinters()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        PrintNodeSettingsView()
    }
    .environment(AppSettings.shared)
}
