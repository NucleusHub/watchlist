import Charts
import NucleusUI
import SwiftUI

/// How much you've watched, and what's left.
struct StatsView: View {
    @Environment(WatchlistStore.self) private var store

    var body: some View {
        let items = store.document.items
        let byStatus = Dictionary(grouping: items, by: \.status)
        NucleusPage("Statistics") {
            hero(items, byStatus: byStatus)

            HStack(spacing: 12) {
                tile("In progress", minutes: (byStatus[.watching] ?? []).reduce(0) { $0 + $1.remainingMinutes },
                     detail: Text("\((byStatus[.watching] ?? []).count) titles left"), tint: WatchStatus.watching.color)
                tile("Planned", minutes: (byStatus[.planned] ?? []).reduce(0) { $0 + $1.remainingMinutes },
                     detail: Text("\((byStatus[.planned] ?? []).count) titles left"), tint: WatchStatus.planned.color)
            }
            .padding(.bottom, 12)
            HStack(spacing: 12) {
                tile("Total", minutes: items.reduce(0) { $0 + $1.totalMinutes }, detail: Text("\(items.count) titles"), tint: Nucleus.accent)
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
                            Text("\(done) of \(all.count) watched").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                        }
                        ProgressView(value: all.isEmpty ? 0 : Double(done) / Double(all.count)).tint(WatchStatus.completed.color)
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
    }

    private func hero(_ items: [Item], byStatus: [WatchStatus: [Item]]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Watched").font(.system(size: 13, weight: .semibold)).textCase(.uppercase).tracking(0.5).foregroundStyle(Nucleus.secondaryText)
            Text(verbatim: RuntimeText.short(items.reduce(0) { $0 + $1.watchedMinutes }))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Nucleus.primaryText)
            Chart([WatchStatus.completed, .watching, .planned], id: \.self) { status in
                BarMark(x: .value("Titles", byStatus[status]?.count ?? 0), stacking: .normalized)
                    .foregroundStyle(status.color)
            }
            .chartXAxis(.hidden)
            .frame(height: 14)
            .clipShape(Capsule())
            HStack(spacing: 14) {
                ForEach([WatchStatus.completed, .watching, .planned], id: \.self) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.title).foregroundStyle(Nucleus.glyph)
                        Text("\(byStatus[s]?.count ?? 0)").foregroundStyle(Nucleus.secondaryText)
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

    private func tile(_ title: LocalizedStringKey, minutes: Int, detail: Text, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(verbatim: RuntimeText.short(minutes)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Nucleus.primaryText)
            detail.font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nucleusGlass(cornerRadius: 22)
    }

    private func ratingsTile(_ items: [Item]) -> some View {
        let mine = items.compactMap(\.rating)
        let tmdb = items.compactMap(\.tmdbRating)
        func avg(_ v: [Double]) -> String { v.isEmpty ? "—" : String(format: "%.1f", v.reduce(0, +) / Double(v.count)) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Ratings").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xFBBF24))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: avg(mine)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Nucleus.primaryText)
                Text("yours").font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
            }
            Text("TMDb \(avg(tmdb))").font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nucleusGlass(cornerRadius: 22)
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
                        Capsule().fill(Nucleus.primaryGradient).frame(width: max(geo.size.width * 0.04, geo.size.width * CGFloat(count) / CGFloat(most)))
                    }
                    .frame(height: 10)
                    Text("\(count)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Nucleus.secondaryText).frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(16)
    }
}
