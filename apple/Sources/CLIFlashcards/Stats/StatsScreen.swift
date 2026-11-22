// The Stats tab, ported from `app/lib/app/stats/stats_screen.dart`. Charts use
// Swift Charts on Apple platforms and plain bars on Android.

import SwiftUI
import FlashcardsCore
#if canImport(Charts) && !os(Android)
import Charts
#endif

struct StatsScreen: View {
    let model: AppModel

    var body: some View {
        if let stats = computed, model.repository?.reviewCount() ?? 0 > 0 {
            StatsList(stats: stats, names: names)
        } else {
            EmptyState(
                title: "No Reviews Yet",
                message: "Your streak, retention and forecast appear here after your first review.",
                systemImage: "chart.bar"
            )
            // The same background as the grouped lists on the other tabs.
            .background(groupedBackground.ignoresSafeArea())
        }
    }

    var computed: Stats? {
        _ = model.revision
        guard let repository = model.repository else { return nil }
        return computeStats(
            decks: model.decks.filter { !$0.paused }, states: repository.allCardStates(), log: repository.allReviews(),
            now: model.now, rolloverHour: model.settings.dayRolloverHour, flagPairs: model.settings.flagPairs
        )
    }

    var names: [String: String] {
        Dictionary(uniqueKeysWithValues: model.decks.map { ($0.id, $0.deck.tool) })
    }
}

struct StatsList: View {
    let stats: Stats
    let names: [String: String]

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: Space.s3) {
                    StatTile(value: "\(stats.reviewsToday)", label: "Reviews Today")
                    StatTile(value: "\(stats.streak)", label: "Day Streak")
                    StatTile(value: retentionText, label: "Retention")
                }
                .padding(.vertical, Space.s1)
            } footer: {
                Text(stats.retention.total > 0
                    ? "Retention is the share of mature cards (21+ day intervals) you remembered in the last 30 days: \(stats.retention.passed) of \(stats.retention.total)."
                    : "Retention appears once you review mature cards, ones with intervals of 21 days or more.")
            }

            Section {
                if forecastTotal == 0 {
                    Text("Nothing is due in the next 30 days.").foregroundStyle(.secondary)
                } else {
                    ForecastChart(days: stats.forecast)
                        .frame(height: 160)
                        .padding(.vertical, Space.s2)
                }
            } header: {
                Text("Due Forecast")
            } footer: {
                if forecastTotal > 0 {
                    Text("\(forecastTotal) reviews over the next 30 days, \(stats.forecast.first?.count ?? 0) of them today.")
                }
            }

            Section {
                Heatmap(days: stats.history)
                    .padding(.vertical, Space.s2)
            } header: {
                Text("Past Year")
            } footer: {
                Text("\(historyTotal) review\(historyTotal == 1 ? "" : "s") on \(activeDays) day\(activeDays == 1 ? "" : "s").")
            }

            if !stats.cards.isEmpty {
                Section {
                    ForEach(stats.cards, id: \.deckId) { counts in
                        DeckCountsRow(name: names[counts.deckId] ?? counts.deckId, counts: counts)
                    }
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Every card in the decks you’re studying, including flag-pair and rarely used cards.")
                }
            }
        }
    }

    var retentionText: String {
        guard let rate = stats.retention.rate else { return "–" }
        return "\(Int((rate * 100).rounded()))%"
    }

    var forecastTotal: Int { stats.forecast.reduce(0) { $0 + $1.count } }
    var historyTotal: Int { stats.history.reduce(0) { $0 + $1.count } }
    var activeDays: Int { stats.history.filter { $0.count > 0 }.count }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .tabularDigits()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(Android)
        .accessibilityElement(children: .combine)
        #endif
    }
}

struct DeckCountsRow: View {
    let name: String
    let counts: DeckCardCounts

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.mono(.body).weight(.semibold))
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    var summary: String {
        var parts = ["\(counts.total) cards", "\(counts.new) new", "\(counts.learning) learning", "\(counts.review) learned"]
        if counts.suspended > 0 { parts.append("\(counts.suspended) suspended") }
        return parts.joined(separator: " · ")
    }
}

/// "Mon, Nov 24" for a study day.
func shortDate(_ day: Millis) -> String {
    let date = Date(timeIntervalSince1970: Double(day) / 1000)
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
    return formatter.string(from: date)
}

/// Cards due on each of the next 30 days.
struct ForecastChart: View {
    let days: [DayCount]
    @Environment(\.frost) var frost

    var body: some View {
        chart
            .accessibilityLabel(Text(summary))
    }

    var summary: String {
        let total = days.reduce(0) { $0 + $1.count }
        let busiest = days.max { $0.count < $1.count }
        var text = "Due forecast: \(total) reviews over 30 days, \(days.first?.count ?? 0) today"
        if let busiest, busiest.count > 0 { text += ", busiest on \(shortDate(busiest.day)) with \(busiest.count)" }
        return text + "."
    }

    #if canImport(Charts) && !os(Android)
    var chart: some View {
        Chart(Array(days.enumerated()), id: \.offset) { index, day in
            BarMark(
                x: .value("Day", Date(timeIntervalSince1970: Double(day.day) / 1000), unit: .day),
                y: .value("Due", day.count)
            )
            .foregroundStyle(index == 0 ? frost.tint : frost.tint.opacity(0.55))
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }
    #else
    var chart: some View {
        let top = max(days.map(\.count).max() ?? 0, 1)
        return VStack(spacing: Space.s1) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.count == 0 ? Color.secondary.opacity(0.15) : index == 0 ? frost.tint : frost.tint.opacity(0.55))
                            .frame(height: max(geo.size.height * CGFloat(day.count) / CGFloat(top), day.count > 0 ? 3 : 1))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            HStack {
                Text("Today")
                Spacer()
                Text("In 30 days")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
    #endif
}

/// A year of reviews, one square per day, a column per week.
struct Heatmap: View {
    let days: [DayCount]
    @Environment(\.frost) var frost

    let cell: CGFloat = 11
    let gap: CGFloat = 3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(day.map { color(heatLevel($0.count, max: top)) } ?? Color.clear)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        #if !os(Android)
        .defaultScrollAnchor(.trailing)
        #endif
        .accessibilityLabel(Text("Past year: \(days.reduce(0) { $0 + $1.count }) reviews, busiest day \(top)."))
    }

    var top: Int { days.map(\.count).max() ?? 0 }

    /// Days in columns of seven, Sunday first, padded so weekdays line up.
    var weeks: [[DayCount?]] {
        guard let first = days.first else { return [] }
        let weekday = Calendar.current.component(.weekday, from: Date(timeIntervalSince1970: Double(first.day) / 1000))
        var cells: [DayCount?] = Array(repeating: nil, count: weekday - 1) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    func color(_ level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.15)
        case 1: frost.tint.opacity(0.3)
        case 2: frost.tint.opacity(0.5)
        case 3: frost.tint.opacity(0.75)
        default: frost.tint
        }
    }
}
