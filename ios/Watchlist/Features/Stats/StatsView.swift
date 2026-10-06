import Charts
import NucleusUI
import SwiftUI

/// How much you've watched, and what's left.
struct StatsView: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 once the page opens; every number and bar is drawn at this share of its value.
    @State private var shown: Double = 0

    var body: some View {
        let items = store.document.items
        let byStatus = Dictionary(grouping: items, by: \.status)
        NucleusPage("Statistics") {
            hero(items, byStatus: byStatus)

            HStack(spacing: 12) {
                tile("In progress", minutes: (byStatus[.watching] ?? []).reduce(0) { $0 + $1.remainingMinutes },
                     count: (byStatus[.watching] ?? []).count, detail: { String(localized: "\($0) titles left") }, tint: WatchStatus.watching.color)
                tile("Planned", minutes: (byStatus[.planned] ?? []).reduce(0) { $0 + $1.remainingMinutes },
                     count: (byStatus[.planned] ?? []).count, detail: { String(localized: "\($0) titles left") }, tint: WatchStatus.planned.color)
            }
            .padding(.bottom, 12)
            HStack(spacing: 12) {
                tile("Total", minutes: items.reduce(0) { $0 + $1.totalMinutes }, count: items.count, detail: { String(localized: "\($0) titles") }, tint: Nucleus.accent)
                ratingsTile(items)
            }
            .padding(.bottom, 28)

            NucleusSection("By type") {
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

            let providers = top(items.compactMap { $0.streamingProvider.flatMap { $0.isEmpty ? nil : $0 } })
            if !providers.isEmpty {
                NucleusSection("Available on") { bars(providers) }
            }
            let years = top(items.compactMap { $0.year.map(String.init) })
            if !years.isEmpty {
                NucleusSection("Top years") { bars(years) }
            }
        }
        .onAppear {
            guard shown == 0 else { return }
            if reduceMotion { shown = 1 } else { withAnimation(.easeOut(duration: 0.8)) { shown = 1 } }
        }
    }

    private func hero(_ items: [Item], byStatus: [WatchStatus: [Item]]) -> some View {
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
        .padding(.bottom, 12)
    }

    private func tile(_ title: LocalizedStringKey, minutes: Int, count: Int, detail: @escaping (Int) -> String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Counting(value: Double(minutes), progress: shown) { Self.runtime($0) }
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
            Counting(value: Double(count), progress: shown) { detail(Int($0.rounded())) }
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nucleusGlass(cornerRadius: 22)
    }

    private func ratingsTile(_ items: [Item]) -> some View {
        let mine = items.compactMap(\.rating)
        let tmdb = items.compactMap(\.tmdbRating)
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let yours = avg(mine), theirs = avg(tmdb)
        func text(_ v: Double, of average: Double?) -> String { average == nil ? "—" : String(format: "%.1f", v) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Ratings").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xFBBF24))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Counting(value: yours ?? 0, progress: shown) { text($0, of: yours) }
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Nucleus.primaryText)
                Text("yours").font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
            }
            Counting(value: theirs ?? 0, progress: shown) { String(localized: "TMDb \(text($0, of: theirs))") }
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Nucleus.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nucleusGlass(cornerRadius: 22)
    }

    /// Counting time starts at 1m rather than "—", which stays for nothing at all.
    private static func runtime(_ minutes: Double) -> String {
        RuntimeText.short(minutes > 0 ? max(1, Int(minutes.rounded())) : 0)
    }

    private func top(_ values: [String]) -> [(String, Int)] {
        Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5).map { ($0.key, $0.value) }
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
