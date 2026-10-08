import Charts
import NucleusUI
import SwiftUI

/// How much you've watched, and what's left, as cards the person can reorder, hide and resize.
struct StatsView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 once the page opens; every number and bar is drawn at this share of its value.
    @State private var shown: Double = 0
    @State private var layout = StatsLayout.load()
    @State private var customizing = false

    var body: some View {
        let items = store.document.items
        let rows = layout.rows(available: StatsCardView.available(items))
        NucleusPage("Statistics") {
            GlassCircleButton("slider.horizontal.3") { customizing = true }
                .accessibilityLabel("Customize")
        } content: {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { entry in
                        StatsCardView(card: entry.card, small: entry.size == .small, items: items, shown: shown)
                    }
                }
                .padding(.bottom, 12)
            }
            if rows.isEmpty {
                NucleusEmptyState("chart.bar.xaxis", title: "Nothing shown", message: "Turn cards back on with the button at the top.")
                    .padding(.top, 60)
            }
        }
        .sheet(isPresented: $customizing) {
            StatsCustomizeView(layout: $layout).presentationDetents([.large])
        }
        .onChange(of: layout) { _, new in new.save() }
        .animation(NucleusMotion.quick, value: layout)
        .onAppear {
            guard shown == 0 else { return }
            if reduceMotion { shown = 1 } else { withAnimation(.easeOut(duration: 0.8)) { shown = 1 } }
        }
    }
}

/// Time watched by status, then what's left, the total and ratings. The tour shows it too.
struct StatsOverview: View {
    let items: [Item]
    /// 0 → 1 as the numbers count up.
    let shown: Double

    var body: some View {
        let rows = StatsLayout(entries: StatsLayout.standard.entries.filter { [.watched, .inProgress, .planned, .total, .ratings].contains($0.card) }).rows()
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { entry in
                        StatsCardView(card: entry.card, small: entry.size == .small, items: items, shown: shown)
                    }
                }
            }
        }
    }
}

/// One statistics card, as a small tile or at full width.
struct StatsCardView: View {
    let card: StatsCard
    let small: Bool
    let items: [Item]
    let shown: Double

    /// Cards with something to show; the lists stay out until there's data for them.
    static func available(_ items: [Item]) -> Set<StatsCard> {
        var cards = Set(StatsCard.allCases)
        if providers(items).isEmpty { cards.remove(.availableOn) }
        if years(items).isEmpty { cards.remove(.topYears) }
        return cards
    }

    var body: some View {
        let byStatus = Dictionary(grouping: items, by: \.status)
        switch card {
        case .watched:
            if small {
                let done = byStatus[.completed] ?? []
                tile("Watched", minutes: items.reduce(0) { $0 + $1.watchedMinutes }, count: done.count,
                     detail: { String(localized: "\($0) titles watched") }, tint: WatchStatus.completed.color)
            } else {
                hero(byStatus: byStatus)
            }
        case .inProgress:
            tile("In progress", minutes: (byStatus[.watching] ?? []).reduce(0) { $0 + $1.remainingMinutes },
                 count: (byStatus[.watching] ?? []).count, detail: { String(localized: "\($0) titles left") }, tint: WatchStatus.watching.color)
        case .planned:
            tile("Planned", minutes: (byStatus[.planned] ?? []).reduce(0) { $0 + $1.remainingMinutes },
                 count: (byStatus[.planned] ?? []).count, detail: { String(localized: "\($0) titles left") }, tint: WatchStatus.planned.color)
        case .total:
            tile("Total", minutes: items.reduce(0) { $0 + $1.totalMinutes }, count: items.count, detail: { String(localized: "\($0) titles") }, tint: Nucleus.accent)
        case .ratings:
            ratingsTile()
        case .byType:
            if small {
                let done = items.filter(\.isCompleted).count
                countTile("By type", value: done, detail: String(localized: "of \(items.count) watched"), tint: WatchStatus.completed.color)
            } else {
                byType
            }
        case .availableOn:
            let rows = Self.providers(items)
            if small, let first = rows.first {
                countTile("Available on", value: first.1, detail: String(localized: "titles on \(first.0)"), tint: NucleusTint.violet.color)
            } else {
                section("Available on") { bars(rows) }
            }
        case .topYears:
            let rows = Self.years(items)
            if small, let first = rows.first {
                countTile("Top years", value: first.1, detail: String(localized: "titles from \(first.0)"), tint: NucleusTint.rose.color)
            } else {
                section("Top years") { bars(rows) }
            }
        }
    }

    private var byType: some View {
        section("By type") {
            ForEach(ItemType.allCases, id: \.self) { type in
                let all = items.filter { $0.type == type }
                let done = all.filter(\.isCompleted).count
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(type == .movie ? "Movies" : "Shows", systemImage: type.symbol).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Counting(value: Double(done), progress: shown) { String(localized: "\(Int($0.rounded())) of \(all.count) watched") }
                            .font(.system(size: 13).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
                    }
                    Meter(fraction: all.isEmpty ? 0 : Double(done) / Double(all.count) * shown, tint: WatchStatus.completed.color)
                }
                .padding(16)
            }
        }
    }

    private static func providers(_ items: [Item]) -> [(String, Int)] {
        top(items.compactMap { $0.streamingProvider.flatMap { $0.isEmpty ? nil : $0 } })
    }

    private static func years(_ items: [Item]) -> [(String, Int)] {
        top(items.compactMap { $0.year.map(String.init) })
    }

    private static func top(_ values: [String]) -> [(String, Int)] {
        Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5).map { ($0.key, $0.value) }
    }

    /// A titled glass group that fills its width, without NucleusSection's bottom gap.
    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        NucleusSection(title) { content() }
            .padding(.bottom, -28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
    }

    private func bars(_ rows: [(String, Int)]) -> some View {
        let most = rows.map(\.1).max() ?? 1
        return VStack(spacing: 12) {
            ForEach(rows, id: \.0) { name, count in
                HStack(spacing: 10) {
                    Text(verbatim: name).font(.system(size: 14)).foregroundStyle(Nucleus.primaryText).frame(width: 110, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        Capsule().fill(Nucleus.primaryGradient)
                            .frame(width: max(geo.size.width * 0.04, geo.size.width * CGFloat(count) / CGFloat(most)) * shown)
                    }
                    .frame(height: 10)
                    Counting(value: Double(count), progress: shown) { "\(Int($0.rounded()))" }
                        .font(.system(size: 13).monospacedDigit()).foregroundStyle(Nucleus.secondaryText).frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(16)
    }

    private func hero(byStatus: [WatchStatus: [Item]]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Watched").font(.system(size: 13, weight: .semibold)).textCase(.uppercase).tracking(0.5).foregroundStyle(Nucleus.secondaryText)
            Counting(value: Double(items.reduce(0) { $0 + $1.watchedMinutes }), progress: shown) { Self.runtime($0) }
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Nucleus.primaryText)
            Chart([WatchStatus.completed, .watching, .planned], id: \.self) { status in
                BarMark(x: .value("Titles", byStatus[status]?.count ?? 0), stacking: .normalized)
                    .foregroundStyle(status.color)
            }
            .chartXAxis(.hidden)
            .frame(height: 14)
            // Grows in from the left with the numbers.
            .mask(alignment: .leading) {
                GeometryReader { geo in Capsule().frame(width: geo.size.width * shown) }
            }
            HStack(spacing: 14) {
                ForEach([WatchStatus.completed, .watching, .planned], id: \.self) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.title).foregroundStyle(Nucleus.glyph)
                        Counting(value: Double(byStatus[s]?.count ?? 0), progress: shown) { "\(Int($0.rounded()))" }
                            .monospacedDigit().foregroundStyle(Nucleus.secondaryText)
                    }
                    .font(.system(size: 13))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nucleusGlass(cornerRadius: 26)
    }

    private func tile(_ title: LocalizedStringKey, minutes: Int, count: Int, detail: @escaping (Int) -> String, tint: Color) -> some View {
        card(title, tint: tint) {
            Counting(value: Double(minutes), progress: shown) { Self.runtime($0) }
                .font(.system(size: small ? 24 : 34, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
            Counting(value: Double(count), progress: shown) { detail(Int($0.rounded())) }
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
        }
    }

    private func countTile(_ title: LocalizedStringKey, value: Int, detail: String, tint: Color) -> some View {
        card(title, tint: tint) {
            Counting(value: Double(value), progress: shown) { "\(Int($0.rounded()))" }
                .font(.system(size: small ? 24 : 34, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
            Text(verbatim: detail).font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func ratingsTile() -> some View {
        let mine = items.compactMap(\.rating)
        let tmdb = items.compactMap(\.tmdbRating)
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let yours = avg(mine), theirs = avg(tmdb)
        func text(_ v: Double, of average: Double?) -> String { average == nil ? "—" : String(format: "%.1f", v) }
        return card("Ratings", tint: Color(hex: 0xFBBF24)) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Counting(value: yours ?? 0, progress: shown) { text($0, of: yours) }
                    .font(.system(size: small ? 24 : 34, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
                Text("yours").font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
            }
            Counting(value: theirs ?? 0, progress: shown) { String(localized: "TMDb \(text($0, of: theirs))") }
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
        }
    }

    /// A number card; at full width it carries the card's icon on the right.
    private func card<C: View>(_ title: LocalizedStringKey, tint: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                content()
            }
            if !small {
                Spacer()
                Image(systemName: card.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .opacity(0.85)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nucleusGlass(cornerRadius: 22)
    }

    /// Counting time starts at 1m rather than "—", which stays for nothing at all.
    private static func runtime(_ minutes: Double) -> String {
        RuntimeText.short(minutes > 0 ? max(1, Int(minutes.rounded())) : 0)
    }
}

/// Reorder, hide and resize the statistics cards.
private struct StatsCustomizeView: View {
    @Binding var layout: StatsLayout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 0) {
                HStack {
                    Button("Reset") {
                        Haptics.tap()
                        withAnimation { layout = .standard }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Nucleus.accent)
                    .frame(width: 70, alignment: .leading)
                    Spacer()
                    Text("Customize").font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                    Spacer()
                    GlassCircleButton("checkmark", tint: Nucleus.accent) { dismiss() }
                        .accessibilityLabel("Done")
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(16)
                Text("Drag to reorder. Small cards sit two to a row.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .padding(.bottom, 8)
                List {
                    ForEach($layout.entries) { $entry in
                        HStack(spacing: 12) {
                            Button {
                                Haptics.selection()
                                entry.visible.toggle()
                            } label: {
                                Image(systemName: entry.visible ? "eye.fill" : "eye.slash")
                                    .font(.system(size: 15))
                                    .foregroundStyle(entry.visible ? Nucleus.accent : Nucleus.secondaryText)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(entry.visible ? Text("Hide card") : Text("Show card"))
                            IconTile(entry.card.icon, tint: entry.card.tint)
                                .opacity(entry.visible ? 1 : 0.4)
                            Text(entry.card.title)
                                .font(.system(size: 16))
                                .foregroundStyle(entry.visible ? Nucleus.primaryText : Nucleus.secondaryText)
                            Spacer()
                            Picker("Size", selection: $entry.size) {
                                Text("S").tag(StatsLayout.Size.small)
                                Text("L").tag(StatsLayout.Size.large)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 84)
                            .disabled(!entry.visible)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove { layout.entries.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
        }
    }
}

/// Text showing `value × progress`, so it counts up as `progress` animates to 1.
private struct Counting: View, Animatable {
    let value: Double
    var progress: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View { Text(verbatim: format(value * progress)) }
}

/// A thin progress bar whose width animates, unlike `ProgressView`'s.
private struct Meter: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Nucleus.well)
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}
