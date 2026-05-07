//
//  StatsView.swift
//  InZentory
//

import SwiftUI
import Charts

struct StatsView: View {
    @Environment(OrdersService.self) private var ordersService
    @Environment(SourcesService.self) private var sourcesService

    private var sourceRecords: [SourceRecord] { sourcesService.sources }

    enum Scope: String, CaseIterable, Identifiable {
        case month, year, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .month: return "Month"
            case .year:  return "Year"
            case .all:   return "All"
            }
        }
    }

    @State private var scope: Scope = .month
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var month: Int = Calendar.current.component(.month, from: Date())

    @State private var stats: [AoBClient.SalesStat] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedDate: Date?

    private let monthSymbols = DateFormatter().standaloneMonthSymbols ?? []
    private let currentYear = Calendar.current.component(.year, from: Date())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                scopePicker
                scopeDetail

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let err = errorMessage {
                    errorCard(err)
                } else if stats.isEmpty {
                    emptyCard
                } else {
                    summaryCards
                    chartSection
                    venueBreakdown
                }

                sourceBreakdown
                listerBreakdown
            }
            .padding(16)
        }
        .navigationTitle("Sales Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scopeKey) { await load() }
        .refreshable { await load() }
    }

    private var scopeKey: String {
        switch scope {
        case .all:   return "all"
        case .year:  return "year-\(year)"
        case .month: return "month-\(year)-\(month)"
        }
    }

    // MARK: - Scope controls

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            ForEach(Scope.allCases) { s in Text(s.label).tag(s) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var scopeDetail: some View {
        switch scope {
        case .all:
            EmptyView()
        case .year:
            HStack {
                Text("Year").foregroundStyle(.secondary)
                Spacer()
                Picker("Year", selection: $year) {
                    ForEach(yearRange, id: \.self) { y in Text(String(y)).tag(y) }
                }
                .pickerStyle(.menu)
            }
        case .month:
            HStack(spacing: 12) {
                Picker("Year", selection: $year) {
                    ForEach(yearRange, id: \.self) { y in Text(String(y)).tag(y) }
                }
                .pickerStyle(.menu)
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthSymbols.indices.contains(m - 1) ? monthSymbols[m - 1] : "\(m)").tag(m)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
        }
    }

    private var yearRange: [Int] { Array((currentYear - 5)...currentYear).reversed() }

    // MARK: - Summary

    private var totalRevenue: Double { stats.reduce(0) { $0 + $1.totalPrice } }
    private var totalCommission: Double { stats.reduce(0) { $0 + $1.totalCommission } }
    private var totalQty: Int { stats.reduce(0) { $0 + $1.totalQty } }
    private var totalNet: Double { totalRevenue - totalCommission }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryCard(label: "Revenue", value: money(totalRevenue), tint: .blue)
            SummaryCard(label: "Net", value: money(totalNet), tint: .green)
            SummaryCard(label: "Commission", value: money(totalCommission), tint: .orange)
            SummaryCard(label: "Items Sold", value: "\(totalQty)", tint: .purple)
        }
    }

    // MARK: - Chart

    /// Buckets stats by date/month/year depending on scope.
    private var bucketedStats: [(bucket: Date, venue: String, revenue: Double)] {
        let cal = Calendar(identifier: .gregorian)
        let component: Calendar.Component
        switch scope {
        case .month: component = .day
        case .year:  component = .month
        case .all:   component = .year
        }
        var dict: [AnyHashable: (Date, String, Double)] = [:]
        for s in stats {
            let bucket = cal.dateInterval(of: component, for: s.date)?.start ?? s.date
            let key = "\(bucket.timeIntervalSince1970)-\(s.venue)" as AnyHashable
            let existing = dict[key]?.2 ?? 0
            dict[key] = (bucket, s.venue, existing + s.totalPrice)
        }
        return dict.values
            .map { (bucket: $0.0, venue: $0.1, revenue: $0.2) }
            .sorted { lhs, rhs in
                if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }
                return lhs.venue < rhs.venue
            }
    }

    private var chartDateFormat: Date.FormatStyle {
        switch scope {
        case .month: return .dateTime.day()
        case .year:  return .dateTime.month(.abbreviated)
        case .all:   return .dateTime.year()
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REVENUE BY \(scope == .month ? "DAY" : scope == .year ? "MONTH" : "YEAR")")
                .font(.custom("Inconsolata-Bold", size: 11))
                .tracking(2)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(Array(bucketedStats.enumerated()), id: \.offset) { _, row in
                    BarMark(
                        x: .value("Date", row.bucket, unit: scopeUnit),
                        y: .value("Revenue", row.revenue)
                    )
                    .foregroundStyle(by: .value("Venue", row.venue))
                    .cornerRadius(3)
                }

                if let sel = selectedDate,
                   let totals = bucketTotals(for: sel) {
                    RuleMark(x: .value("Selected", totals.bucket, unit: scopeUnit))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, alignment: .center, spacing: 4) {
                            selectionPopover(totals)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisTick()
                    if let d = value.as(Date.self) {
                        AxisValueLabel { Text(d, format: chartDateFormat) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    if let n = value.as(Double.self) {
                        AxisValueLabel { Text(money(n, compact: true)) }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 240)
        }
        .padding(12)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scopeUnit: Calendar.Component {
        switch scope {
        case .month: return .day
        case .year:  return .month
        case .all:   return .year
        }
    }

    private struct BucketTotals {
        let bucket: Date
        let revenue: Double
        let qty: Int
        let commission: Double
        let byVenue: [(venue: String, revenue: Double)]
    }

    private func bucketTotals(for date: Date) -> BucketTotals? {
        let cal = Calendar(identifier: .gregorian)
        guard let interval = cal.dateInterval(of: scopeUnit, for: date) else { return nil }
        let matches = stats.filter { $0.date >= interval.start && $0.date < interval.end }
        guard !matches.isEmpty else { return nil }
        let venueDict = Dictionary(grouping: matches, by: \.venue)
            .mapValues { $0.reduce(0) { $0 + $1.totalPrice } }
        let byVenue = venueDict
            .map { (venue: $0.key, revenue: $0.value) }
            .sorted { $0.revenue > $1.revenue }
        return BucketTotals(
            bucket: interval.start,
            revenue: matches.reduce(0) { $0 + $1.totalPrice },
            qty: matches.reduce(0) { $0 + $1.totalQty },
            commission: matches.reduce(0) { $0 + $1.totalCommission },
            byVenue: byVenue
        )
    }

    @ViewBuilder
    private func selectionPopover(_ totals: BucketTotals) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(totals.bucket, format: popoverDateFormat)
                .font(.caption.bold())
            Text("\(money(totals.revenue)) · \(totals.qty) qty")
                .font(.caption)
            ForEach(totals.byVenue, id: \.venue) { v in
                Text("\(v.venue): \(money(v.revenue))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
    }

    private var popoverDateFormat: Date.FormatStyle {
        switch scope {
        case .month: return .dateTime.month(.abbreviated).day()
        case .year:  return .dateTime.month(.wide).year()
        case .all:   return .dateTime.year()
        }
    }

    // MARK: - Venue breakdown

    private var venueBreakdown: some View {
        let groups: [String: [AoBClient.SalesStat]] = Dictionary(grouping: stats, by: { $0.venue })
        var rows: [VenueRow] = []
        for (venue, items) in groups {
            let revenue = items.reduce(0.0) { $0 + $1.totalPrice }
            let qty = items.reduce(0) { $0 + $1.totalQty }
            let commission = items.reduce(0.0) { $0 + $1.totalCommission }
            rows.append(VenueRow(venue: venue, revenue: revenue, qty: qty, commission: commission))
        }
        rows.sort { $0.revenue > $1.revenue }
        let grouped = rows
        let maxRevenue = grouped.map { $0.revenue }.max() ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("BY VENUE")
                .font(.custom("Inconsolata-Bold", size: 11))
                .tracking(2)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(grouped, id: \.venue) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.venue.uppercased())
                                .font(.custom("Inconsolata-Bold", size: 13))
                                .tracking(1)
                            Spacer()
                            Text(money(row.revenue))
                                .font(.custom("Inconsolata-Bold", size: 13))
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.blue.opacity(0.5))
                                .frame(width: geo.size.width * CGFloat(row.revenue / maxRevenue),
                                       height: 6)
                        }
                        .frame(height: 6)
                        HStack {
                            Text("\(row.qty) items · \(money(row.commission)) commission")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Net \(money(row.revenue - row.commission))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func money(_ v: Double, compact: Bool = false) -> String {
        if compact {
            if abs(v) >= 1000 { return String(format: "$%.1fk", v / 1000) }
            return String(format: "$%.0f", v)
        }
        return String(format: "$%.2f", v)
    }

    @ViewBuilder
    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Couldn't load stats", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(msg).font(.caption).foregroundStyle(.secondary)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No sales data for this period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Source breakdown

    private struct SourceStatRow {
        let source: SourceRecord
        let revenue: Double
        let qty: Int
    }

    private var sourceStatRows: [SourceStatRow] {
        // Aggregate revenue from currently cached orders (across all sublists) by item.source.
        var revenueByName: [String: (revenue: Double, qty: Int)] = [:]
        for (_, orders) in ordersService.ordersByList {
            for order in orders {
                for item in order.items {
                    guard let s = item.source, !s.isEmpty else { continue }
                    let price = Double(item.price ?? "") ?? 0
                    let qty = item.qty ?? 0
                    let lineTotal = price * Double(qty)
                    var entry = revenueByName[s] ?? (0, 0)
                    entry.revenue += lineTotal
                    entry.qty += qty
                    revenueByName[s] = entry
                }
            }
        }
        return sourceRecords
            .filter { $0.name != "Backlog" }
            .map { rec in
                let r = revenueByName[rec.name] ?? (0, 0)
                return SourceStatRow(source: rec, revenue: r.revenue, qty: r.qty)
            }
            .sorted { ($0.revenue - $0.source.totalCost) > ($1.revenue - $1.source.totalCost) }
    }

    @ViewBuilder
    private var sourceBreakdown: some View {
        if sourceStatRows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("BY SOURCE")
                    .font(.custom("Inconsolata-Bold", size: 11))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Text("Net = revenue from currently active orders − recorded cost.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(sourceStatRows, id: \.source.id) { row in
                        sourceRow(row)
                    }
                }
            }
            .padding(12)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Lister breakdown

    private struct ListerStatRow {
        let name: String
        let revenue: Double
        let qty: Int
    }

    private var listerStatRows: [ListerStatRow] {
        var totals: [String: (revenue: Double, qty: Int)] = [:]
        for (_, orders) in ordersService.ordersByList {
            for order in orders {
                for item in order.items {
                    guard let lister = item.lister, !lister.isEmpty else { continue }
                    let price = Double(item.price ?? "") ?? 0
                    let qty = item.qty ?? 0
                    var entry = totals[lister] ?? (0, 0)
                    entry.revenue += price * Double(qty)
                    entry.qty += qty
                    totals[lister] = entry
                }
            }
        }
        return totals
            .map { ListerStatRow(name: $0.key, revenue: $0.value.revenue, qty: $0.value.qty) }
            .sorted { $0.revenue > $1.revenue }
    }

    @ViewBuilder
    private var listerBreakdown: some View {
        let rows = listerStatRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("BY LISTER")
                    .font(.custom("Inconsolata-Bold", size: 11))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Text("Revenue from currently active orders, attributed by p2.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                let maxRevenue = rows.map(\.revenue).max() ?? 1
                VStack(spacing: 10) {
                    ForEach(rows, id: \.name) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.name.uppercased())
                                    .font(.custom("Inconsolata-Bold", size: 13))
                                    .tracking(1)
                                Spacer()
                                Text(money(row.revenue))
                                    .font(.custom("Inconsolata-Bold", size: 13))
                                    .monospacedDigit()
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.purple.opacity(0.5))
                                    .frame(width: geo.size.width * CGFloat(row.revenue / maxRevenue),
                                           height: 6)
                            }
                            .frame(height: 6)
                            HStack {
                                Text("\(row.qty) sold")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func sourceRow(_ row: SourceStatRow) -> some View {
        let net = row.revenue - row.source.totalCost
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: row.source.kind.icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(row.source.name.uppercased())
                    .font(.custom("Inconsolata-Bold", size: 13))
                    .tracking(1)
                if row.source.state == .closed {
                    Text("CLOSED")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(money(net))
                    .font(.custom("Inconsolata-Bold", size: 13))
                    .monospacedDigit()
                    .foregroundStyle(net >= 0 ? .green : .red)
            }
            HStack {
                Text("Cost \(money(row.source.totalCost)) · Rev \(money(row.revenue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(row.qty) sold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        selectedDate = nil
        do {
            let results: [AoBClient.SalesStat]
            switch scope {
            case .all:   results = try await AoBClient.shared.fetchSalesStats()
            case .year:  results = try await AoBClient.shared.fetchSalesStats(year: year)
            case .month: results = try await AoBClient.shared.fetchSalesStats(year: year, month: month)
            }
            stats = results
        } catch {
            stats = []
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

private struct VenueRow: Identifiable {
    var id: String { venue }
    let venue: String
    let revenue: Double
    let qty: Int
    let commission: Double
}

private struct SummaryCard: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.custom("Inconsolata-Bold", size: 24))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.custom("Inconsolata-Regular", size: 11))
                .tracking(1.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NavigationStack { StatsView() }
}
