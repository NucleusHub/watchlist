import NucleusUI
import SwiftUI

enum SortKey: String, CaseIterable {
    case alphabetical, dateAdded, dateReleased, rating, runtime

    var title: LocalizedStringKey {
        switch self {
        case .alphabetical: "Title"
        case .dateAdded: "Date added"
        case .dateReleased: "Release year"
        case .rating: "Rating"
        case .runtime: "Runtime"
        }
    }

    var symbol: String {
        switch self {
        case .alphabetical: "textformat"
        case .dateAdded: "calendar.badge.plus"
        case .dateReleased: "calendar"
        case .rating: "star"
        case .runtime: "clock"
        }
    }

    /// Picking a sort starts in its natural direction; A–Z goes up, the rest come down.
    var ascendingByDefault: Bool { self == .alphabetical }
}

struct ItemFilter: Equatable {
    var status: WatchStatus?
    var type: ItemType?
    var favoritesOnly = false
    var genres: Set<String> = []

    func matches(_ item: Item) -> Bool {
        if let status, item.status != status { return false }
        if let type, item.type != type { return false }
        if favoritesOnly, !item.favorite { return false }
        if !genres.isEmpty {
            let mine = Set(item.genres.map { $0.lowercased() })
            if mine.isDisjoint(with: genres.map { $0.lowercased() }) { return false }
        }
        return true
    }

    var isActive: Bool { status != nil || type != nil || favoritesOnly || !genres.isEmpty }
}

/// The main list: filters, sort, genre chips and the titles in the chosen layout.
struct WatchlistTab: View {
    @Environment(WatchlistStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(Navigator.self) private var navigator
    @Environment(CloudSync.self) private var sync
    @State private var filter = ItemFilter(status: .planned)
    @State private var sort: SortKey = .alphabetical
    @State private var ascending = true

    private var filtered: [Item] {
        var base = filter
        base.genres = []
        let items = store.items.filter(base.matches)
        let withGenres = items.filter(filter.matches)
        return sorted(withGenres)
    }

    /// Genres among what the other filters leave, most common first.
    private var genreCounts: [(name: String, count: Int)] {
        var base = filter
        base.genres = []
        var counts: [String: (String, Int)] = [:]
        for item in store.items where base.matches(item) {
            for g in item.genres { counts[g.lowercased(), default: (g, 0)].1 += 1 }
        }
        return counts.values.map { (name: $0.0, count: $0.1) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func sorted(_ items: [Item]) -> [Item] {
        func value(_ i: Item) -> Double? {
            switch sort {
            case .alphabetical: nil
            case .dateAdded: Timestamp.millis(i.dateAdded)
            case .dateReleased: i.year.map(Double.init)
            case .rating: i.rating ?? i.tmdbRating
            case .runtime: Double(i.totalMinutes)
            }
        }
        if sort == .alphabetical {
            return items.sorted {
                let r = $0.title.localizedCaseInsensitiveCompare($1.title)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        }
        // Titles without a value go last either way.
        return items.sorted { a, b in
            switch (value(a), value(b)) {
            case let (x?, y?): return ascending ? x < y : x > y
            case (_?, nil): return true
            default: return false
            }
        }
    }

    var body: some View {
        if store.items.isEmpty {
            ScrollView {
                VStack(spacing: 20) {
                    NucleusEmptyState("popcorn", title: "Nothing to watch yet", message: "Add movies and shows you want to see. Search TMDb or type a title.")
                    Button("Add your first title") { navigator.present(.newItem(collectionID: nil)) }
                        .buttonStyle(NucleusPrimaryButtonStyle())
                        .frame(maxWidth: 280)
                }
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
                .nucleusAppear()
            }
        } else {
            ItemGrid(items: filtered, style: preferences.gridStyle) {
                filters
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        NucleusEmptyState("line.3.horizontal.decrease.circle", title: "No matches", message: "Nothing fits these filters.")
                        Button("Clear filters") { withAnimation(NucleusMotion.quick) { filter = ItemFilter() } }
                            .buttonStyle(NucleusSecondaryButtonStyle())
                    }
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
                }
            }
            .refreshable { await sync.syncNow() }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            NucleusSegmented(selection: $filter.status, items: [
                (nil, "All"), (.planned, "Planned"), (.watching, "Watching"), (.completed, "Watched"),
            ], fill: true)

            HStack(spacing: 8) {
                NucleusSegmented(selection: $filter.type, items: [(nil, "All"), (.movie, "Movies"), (.show, "Shows")])
                    .fixedSize()
                Spacer(minLength: 0)
                chipButton(filter.favoritesOnly ? "heart.fill" : "heart", active: filter.favoritesOnly) {
                    Haptics.selection()
                    withAnimation(NucleusMotion.quick) { filter.favoritesOnly.toggle() }
                }
                .accessibilityLabel("Favorites only")
                Menu {
                    Picker("Sort by", selection: Binding(get: { sort }, set: { pick($0) })) {
                        ForEach(SortKey.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Divider()
                    Button { ascending.toggle() } label: {
                        Label(ascending ? "Ascending" : "Descending", systemImage: ascending ? "arrow.up" : "arrow.down")
                    }
                } label: { chipLabel("arrow.up.arrow.down", active: sort != .alphabetical || !ascending) }
                    .accessibilityLabel("Sort")
                Menu {
                    Picker("Layout", selection: Binding(get: { preferences.gridStyle }, set: { preferences.gridStyle = $0 })) {
                        Label("List", systemImage: "list.bullet").tag(GridStyle.list)
                        Label("Large posters", systemImage: "square.grid.2x2").tag(GridStyle.big)
                        Label("Small posters", systemImage: "square.grid.3x3").tag(GridStyle.small)
                    }
                } label: { chipLabel(layoutSymbol, active: false) }
                    .accessibilityLabel("Layout")
            }

            if !genreCounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(genreCounts, id: \.name) { g in
                            let on = filter.genres.contains { $0.lowercased() == g.name.lowercased() }
                            Button {
                                Haptics.selection()
                                withAnimation(NucleusMotion.quick) {
                                    if on { filter.genres = filter.genres.filter { $0.lowercased() != g.name.lowercased() } } else { filter.genres.insert(g.name) }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: g.name)
                                    Text(verbatim: "\(g.count)").foregroundStyle(on ? .white.opacity(0.7) : Nucleus.secondaryText)
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(on ? .white : Nucleus.glyph)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(on ? AnyShapeStyle(GenrePalette.color(g.name)) : AnyShapeStyle(Nucleus.well)))
                            }
                            .buttonStyle(NucleusPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var layoutSymbol: String {
        switch preferences.gridStyle {
        case .list: "list.bullet"
        case .big: "square.grid.2x2"
        case .small: "square.grid.3x3"
        }
    }

    private func pick(_ key: SortKey) {
        Haptics.selection()
        if key == sort { ascending.toggle() } else { sort = key; ascending = key.ascendingByDefault }
    }

    private func chipButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(symbol, active: active) }.buttonStyle(NucleusPressStyle())
    }

    private func chipLabel(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Nucleus.accent : Nucleus.glyph)
            .frame(width: 40, height: 40)
            .nucleusGlass(in: Circle(), interactive: true)
    }
}

/// A steady colour per genre name.
enum GenrePalette {
    private static let hues: [UInt32] = [0x6366F1, 0x8B5CF6, 0xEC4899, 0xF43F5E, 0xF59E0B, 0x10B981, 0x0EA5E9, 0x14B8A6]

    static func color(_ name: String) -> Color {
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Color(hex: hues[Int(hash % UInt32(hues.count))])
    }
}
