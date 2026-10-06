import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// A short swipeable tour of what the app can do. Opens after Welcome and from Settings → Help.
struct TourView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    /// The scenes' cards can't open anything real.
    @State private var demoNavigator = Navigator()

    private let steps = TourStep.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: finish)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Nucleus.secondaryText)
                    .opacity(page < steps.count - 1 ? 1 : 0)
                    .accessibilityIdentifier("tourSkip")
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    TourPage(step: steps[index], active: page == index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(demoNavigator)
            .onChange(of: page) { _, _ in Haptics.selection() }

            VStack(spacing: 22) {
                dots
                Button(page < steps.count - 1 ? "Next" : "Done", action: next)
                    .buttonStyle(NucleusPrimaryButtonStyle())
                    .accessibilityIdentifier("tourNext")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background {
            ZStack {
                NucleusBackground()
                RadialGradient(colors: [steps[page].tint.color.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 460)
                    .ignoresSafeArea()
                    .animation(NucleusMotion.ease, value: page)
            }
        }
        .onDisappear { preferences.hasSeenTour = true }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Nucleus.accent : Nucleus.separator)
                    .frame(width: index == page ? 20 : 7, height: 7)
            }
        }
        .animation(NucleusMotion.quick, value: page)
        .accessibilityHidden(true)
    }

    private func next() {
        guard page < steps.count - 1 else { return finish() }
        withAnimation(NucleusMotion.ease) { page += 1 }
    }

    private func finish() {
        Haptics.tap()
        preferences.hasSeenTour = true
        dismiss()
    }
}

struct TourStep {
    enum Scene { case add, swipe, mark, progress, collections, discover, stats, sync }

    let scene: Scene
    let tint: NucleusTint
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    static let all: [TourStep] = [
        TourStep(scene: .add, tint: .indigo, title: "Add anything",
                 message: "Tap + to add a movie or show. With a TMDb key, search fills in the poster, cast and where to watch."),
        TourStep(scene: .swipe, tint: .violet, title: "Swipe between pages",
                 message: "Home slides between your Watchlist, Collections and the pages plugins add, like Discover."),
        TourStep(scene: .mark, tint: .emerald, title: "Mark it, love it",
                 message: "Tap the check when you've seen something and the heart for favorites. Press and hold a title for everything else."),
        TourStep(scene: .progress, tint: .sky, title: "Pick up where you left off",
                 message: "Tick off episodes season by season. Links open in the app and remember where you stopped, so Jump back in takes you straight there."),
        TourStep(scene: .collections, tint: .amber, title: "Make collections",
                 message: "Group titles for date night, a marathon or a friend's recommendations, each with its own cover and order."),
        TourStep(scene: .discover, tint: .rose, title: "Find what's next",
                 message: "Discover suggests titles, MovieDNA learns what you like, Cast & Crew shows who made them and News follows your titles."),
        TourStep(scene: .stats, tint: .orange, title: "See your numbers",
                 message: "The chart button on Home shows how much you've watched, what's left and how you rate things."),
        TourStep(scene: .sync, tint: .teal, title: "Yours on every device",
                 message: "Sign in with Nucleus ID to sync, or export a backup any time. You can replay this tour from Settings."),
    ]
}

private struct TourPage: View {
    let step: TourStep
    let active: Bool

    var body: some View {
        VStack(spacing: 0) {
            FitHeight { scene }
                .frame(maxHeight: .infinity)
                .padding(.top, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(step.title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Nucleus.primaryText)
                Text(step.message)
                    .font(.system(size: 16))
                    .foregroundStyle(Nucleus.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch step.scene {
        case .add: AddScene(active: active)
        case .swipe: SwipeScene(active: active)
        case .mark: MarkScene(active: active)
        case .progress: ProgressScene(active: active)
        case .collections: CollectionsScene(active: active)
        case .discover: DiscoverScene(active: active)
        case .stats: StatsScene(active: active)
        case .sync: SyncScene(active: active)
        }
    }
}

// MARK: Scenes
// Each scene is the app's own views over a throwaway store of sample titles, acting out the step.

/// Shows a scene at the app's real size, shrunk only when the screen is too short for it.
private struct FitHeight<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var natural: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let scale = natural > geo.size.height && natural > 0 ? geo.size.height / natural : 1
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
                .frame(width: geo.size.width)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// A fingertip touching the screen; it taps each time `count` goes up.
private struct TapMark: View {
    let count: Int
    @State private var down = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.3))
            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
            .frame(width: 46, height: 46)
            .scaleEffect(down ? 1 : 0.5)
            .opacity(down ? 1 : 0)
            .task(id: count) {
                guard count > 0 else { return down = false }
                withAnimation(.easeOut(duration: 0.15)) { down = true }
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(.easeIn(duration: 0.3)) { down = false }
            }
    }
}

/// Runs `run` while the page is showing, on a loop unless `repeats` is off; Reduce Motion gets the end state only.
private struct SceneLoop: ViewModifier {
    let active: Bool
    let reset: () -> Void
    let still: () -> Void
    var repeats = true
    let run: () async throws -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task(id: active) {
            guard active, !reduceMotion else { return reduceMotion ? still() : reset() }
            do {
                repeat {
                    reset()
                    try await run()
                } while repeats
            } catch {}
        }
    }
}

private extension View {
    func sceneLoop(_ active: Bool, repeats: Bool = true, reset: @escaping () -> Void, still: @escaping () -> Void, _ run: @escaping () async throws -> Void) -> some View {
        modifier(SceneLoop(active: active, reset: reset, still: still, repeats: repeats, run: run))
    }
}

private func wait(_ seconds: Double) async throws {
    try await Task.sleep(for: .seconds(seconds))
}


// MARK: Demo titles

/// The titles the scenes play with; each scene gets its own, so the tour doesn't repeat itself.
private enum Demo {
    struct Title {
        let n: Int
        let title: String
        let type: ItemType
        let year: Int
        let poster: String
        let genres: [String]
        var runtime: Int? = nil
        var seasons: Int? = nil
        var episodes: Int? = nil
        var tmdb: Double
        let tmdbID: Int

        var id: String { String(format: "d%023d", n) }
        var posterURL: String { "https://image.tmdb.org/t/p/w500\(poster)" }
    }

    static let dune2 = Title(n: 1, title: "Dune: Part Two", type: .movie, year: 2024, poster: "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", genres: ["Science Fiction", "Adventure"], runtime: 166, tmdb: 8.2, tmdbID: 693134)
    static let dune = Title(n: 2, title: "Dune", type: .movie, year: 2021, poster: "/v1tRXZ4JtD2Iv6fjkPvT4GiwslV.jpg", genres: ["Science Fiction", "Adventure"], runtime: 155, tmdb: 7.8, tmdbID: 438631)
    static let duneProphecy = Title(n: 3, title: "Dune: Prophecy", type: .show, year: 2024, poster: "/oWVohNsxkxA3u92EzRo8fTuXIS0.jpg", genres: ["Sci-Fi & Fantasy", "Drama"], seasons: 1, episodes: 6, tmdb: 7.6, tmdbID: 90228)
    static let shogun = Title(n: 4, title: "Shōgun", type: .show, year: 2024, poster: "/7O4iVfOMQmdCSxhOg1WnzG1AgYT.jpg", genres: ["Drama", "War & Politics"], seasons: 1, episodes: 10, tmdb: 8.6, tmdbID: 126308)
    static let pastLives = Title(n: 5, title: "Past Lives", type: .movie, year: 2023, poster: "/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg", genres: ["Drama", "Romance"], runtime: 106, tmdb: 7.6, tmdbID: 666277)
    static let arrival = Title(n: 6, title: "Arrival", type: .movie, year: 2016, poster: "/pEzNVQfdzYDzVK0XqxERIw2x2se.jpg", genres: ["Drama", "Science Fiction"], runtime: 116, tmdb: 7.6, tmdbID: 329865)
    static let poorThings = Title(n: 7, title: "Poor Things", type: .movie, year: 2023, poster: "/kCGlIMHnOm8JPXq3rXM6c5wMxcT.jpg", genres: ["Science Fiction", "Romance", "Comedy"], runtime: 141, tmdb: 7.7, tmdbID: 792307)
    static let eeaao = Title(n: 8, title: "Everything Everywhere All at Once", type: .movie, year: 2022, poster: "/u68AjlvlutfEIcpmbYpKcdi09ut.jpg", genres: ["Action", "Adventure", "Science Fiction"], runtime: 140, tmdb: 7.8, tmdbID: 545611)
    static let spiderVerse = Title(n: 9, title: "Spider-Man: Across the Spider-Verse", type: .movie, year: 2023, poster: "/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg", genres: ["Animation", "Action"], runtime: 140, tmdb: 8.3, tmdbID: 569094)
    static let laLaLand = Title(n: 10, title: "La La Land", type: .movie, year: 2016, poster: "/uDO8zWDhfWwoFdKS4fzkUJt0Rf0.jpg", genres: ["Comedy", "Drama", "Romance"], runtime: 129, tmdb: 7.9, tmdbID: 313369)
    static let beforeSunrise = Title(n: 11, title: "Before Sunrise", type: .movie, year: 1995, poster: "/kf1Jb1c2JAOqjuzA3H4oDM263uB.jpg", genres: ["Drama", "Romance"], runtime: 101, tmdb: 8.0, tmdbID: 76)
    static let holdovers = Title(n: 12, title: "The Holdovers", type: .movie, year: 2023, poster: "/VHSzNBTwxV8vh7wylo7O9CLdac.jpg", genres: ["Comedy", "Drama"], runtime: 133, tmdb: 7.7, tmdbID: 840430)
    static let bladeRunner = Title(n: 13, title: "Blade Runner 2049", type: .movie, year: 2017, poster: "/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg", genres: ["Science Fiction", "Drama"], runtime: 164, tmdb: 7.6, tmdbID: 335984)
    static let sicario = Title(n: 14, title: "Sicario", type: .movie, year: 2015, poster: "/lz8vNyXeidqqOdJW9ZjnDAMb5Vr.jpg", genres: ["Action", "Crime", "Thriller"], runtime: 122, tmdb: 7.4, tmdbID: 273481)
    static let prisoners = Title(n: 15, title: "Prisoners", type: .movie, year: 2013, poster: "/uhviyknTT5cEQXbn6vWIqfM4vGm.jpg", genres: ["Drama", "Thriller", "Crime"], runtime: 153, tmdb: 8.1, tmdbID: 146233)
    static let oppenheimer = Title(n: 16, title: "Oppenheimer", type: .movie, year: 2023, poster: "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", genres: ["Drama", "History"], runtime: 180, tmdb: 8.1, tmdbID: 872585)
    static let severance = Title(n: 17, title: "Severance", type: .show, year: 2022, poster: "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg", genres: ["Drama", "Mystery"], seasons: 2, episodes: 19, tmdb: 8.4, tmdbID: 95396)
    static let fellowship = Title(n: 19, title: "The Lord of the Rings: The Fellowship of the Ring", type: .movie, year: 2001, poster: "/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg", genres: ["Adventure", "Fantasy"], runtime: 179, tmdb: 8.4, tmdbID: 120)
    static let twoTowers = Title(n: 20, title: "The Lord of the Rings: The Two Towers", type: .movie, year: 2002, poster: "/5VTN0pR8gcqV3EPUHHfMGnJYN9L.jpg", genres: ["Adventure", "Fantasy"], runtime: 179, tmdb: 8.4, tmdbID: 121)
    static let returnOfTheKing = Title(n: 21, title: "The Lord of the Rings: The Return of the King", type: .movie, year: 2003, poster: "/rCzpDGLbOoPwLjy3OAm5NUPOTrC.jpg", genres: ["Adventure", "Fantasy"], runtime: 201, tmdb: 8.5, tmdbID: 122)
    static let lastOfUs = Title(n: 18, title: "The Last of Us", type: .show, year: 2023, poster: "/dmo6TYuuJgaYinXBPjrgG9mB5od.jpg", genres: ["Drama", "Action & Adventure"], seasons: 2, episodes: 16, tmdb: 8.6, tmdbID: 100088)

    /// `order` puts titles in the grid: lower comes first.
    static func item(_ t: Title, status: WatchStatus = .planned, rating: Double? = nil, collections: [String] = [], order: Int = 0) -> Item {
        var i = Item(title: t.title, type: t.type)
        let at = Timestamp.string(Date().addingTimeInterval(-Double(order + 1) * 3600))
        i.set("_id", .string(t.id))
        i.set("createdAt", .string(at))
        i.set("dateAdded", .string(at))
        i.updatedAt = at
        i.status = status
        i.posterUrl = t.posterURL
        i.genres = t.genres
        i.year = t.year
        i.runtime = t.runtime
        i.seasons = t.seasons
        i.episodes = t.episodes
        i.rating = rating
        i.tmdbRating = t.tmdb
        i.tmdbId = t.tmdbID
        i.collectionIds = collections
        if status == .completed { i.set("completedAt", .string(at)) }
        return i
    }

    static func collection(_ n: Int, _ name: String) -> WatchCollection {
        var c = WatchCollection(name: name)
        c.set("_id", .string(String(format: "c%023d", n)))
        c.set("createdAt", .string(Timestamp.now()))
        c.updatedAt = Timestamp.now()
        return c
    }

    @MainActor
    static func store(_ items: [Item], collections: [WatchCollection] = []) -> WatchlistStore {
        WatchlistStore(fileURL: nil, document: WatchlistDocument(items: items, collections: collections))
    }
}

// MARK: Scenes

/// The small grid, as on Home.
private struct SmallGrid: View {
    let items: [Item]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 16) {
            ForEach(items) { item in
                ItemCard(item: item, compact: true)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Typing in the Add title sheet's search, picking a result, and the title landing in the list.
private struct AddScene: View {
    let active: Bool
    @State private var store = Demo.store([])
    @State private var typed = ""
    @State private var results: [Demo.Title] = []
    @State private var taps = 0

    private static let rounds: [(query: String, results: [Demo.Title])] = [
        ("Dune", [Demo.dune2, Demo.dune, Demo.duneProphecy]),
        ("Shōgun", [Demo.shogun]),
    ]

    var body: some View {
        VStack(spacing: 22) {
            NucleusSection {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
                    HStack(spacing: 1) {
                        if typed.isEmpty {
                            Capsule().fill(Nucleus.accent).frame(width: 2, height: 22)
                            Text("Title, or search TMDb").foregroundStyle(Nucleus.secondaryText.opacity(0.7))
                        } else {
                            Text(verbatim: typed).foregroundStyle(Nucleus.primaryText)
                            Capsule().fill(Nucleus.accent).frame(width: 2, height: 22)
                        }
                    }
                    .font(.system(size: 17, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16).frame(minHeight: 54)
                ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                    SearchHitRow(thumbnail: URL(string: hit.posterURL), title: hit.title, type: hit.type, detail: String(hit.year))
                        .overlay(alignment: .trailing) { if index == 0 { TapMark(count: taps).padding(.trailing, 3) } }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            SmallGrid(items: store.items)
        }
        .environment(store)
        .sceneLoop(active, reset: reset, still: { reset(); add(Demo.dune2) }) {
            for round in Self.rounds {
                try await wait(0.8)
                for letter in round.query {
                    typed.append(letter)
                    try await wait(0.16)
                }
                try await wait(0.3)
                withAnimation(NucleusMotion.ease) { results = round.results }
                try await wait(1.1)
                taps += 1
                try await wait(0.25)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    typed = ""
                    results = []
                    add(round.results[0])
                }
            }
            try await wait(2.4)
        }
    }

    private func reset() {
        typed = ""
        results = []
        store.replace(with: WatchlistDocument(items: [Demo.item(Demo.pastLives, order: 1), Demo.item(Demo.arrival, order: 2)]), silent: true)
    }

    private func add(_ title: Demo.Title) {
        store.replace(with: WatchlistDocument(items: store.document.items + [Demo.item(title, order: -store.document.items.count)]), silent: true)
    }
}

private struct SwipeScene: View {
    let active: Bool
    @State private var store = Demo.store(
        [Demo.item(Demo.poorThings), Demo.item(Demo.lastOfUs, order: 1), Demo.item(Demo.holdovers, order: 2),
         Demo.item(Demo.fellowship, collections: [Self.collection.id], order: 3),
         Demo.item(Demo.twoTowers, collections: [Self.collection.id], order: 4),
         Demo.item(Demo.returnOfTheKing, collections: [Self.collection.id], order: 5)],
        collections: [Self.collection])
    @State private var tab = "watchlist"
    @State private var progress = CarouselProgress()
    private static let collection = Demo.collection(1, String(localized: "Lord of the Rings marathon"))
    private let tabs: [(value: String, title: LocalizedStringKey)] = [("discover", "Discover"), ("watchlist", "Watchlist"), ("collections", "Collections")]

    var body: some View {
        VStack(spacing: 16) {
            SlidingSegmented(selection: $tab, items: tabs, progress: progress).fixedSize()
            PagedCarousel(tabs.map(\.value), selection: $tab, progress: progress) { page($0).frame(maxHeight: .infinity, alignment: .top) }
                .frame(height: 340)
        }
        .environment(store)
        .sceneLoop(active, reset: { tab = "watchlist" }, still: { tab = "watchlist" }) {
            for next in ["collections", "watchlist", "discover", "watchlist"] {
                try await wait(1.6)
                withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { tab = next }
            }
            try await wait(0.6)
        }
    }

    @ViewBuilder
    private func page(_ id: String) -> some View {
        switch id {
        case "discover":
            DiscoverPicks(picks: [
                .init(title: Demo.oppenheimer, why: Text("Because you liked \(Demo.poorThings.title)")),
                .init(title: Demo.eeaao, why: Text("Because you liked \(Demo.poorThings.title)")),
                .init(title: Demo.spiderVerse, why: Text(verbatim: "Animation · Action")),
            ])
        case "collections":
            if let collection = store.collection(Self.collection.id) { CollectionCard(collection: collection).padding(.horizontal, 16) }
        default: SmallGrid(items: Array(store.items.prefix(3)))
        }
    }
}

private struct MarkScene: View {
    let active: Bool
    @State private var store = Demo.store([Demo.item(Demo.eeaao), Demo.item(Demo.spiderVerse, order: 1)])
    @State private var checkTaps = 0
    @State private var heartTaps = 0

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let first = store.item(Demo.eeaao.id) {
                ItemCard(item: first)
                    .overlay(alignment: .topLeading) { TapMark(count: checkTaps).offset(x: -8, y: -8) }
            }
            if let second = store.item(Demo.spiderVerse.id) {
                ItemCard(item: second)
                    .overlay(alignment: .topTrailing) { TapMark(count: heartTaps).offset(x: 8, y: -8) }
            }
        }
        .padding(.horizontal, 16)
        .overlay { Confetti(trigger: store.celebrations) }
        .environment(store)
        .sceneLoop(active, reset: reset, still: { store.markWatched(Demo.eeaao.id); store.toggleFavorite(Demo.spiderVerse.id) }) {
            try await wait(1)
            checkTaps += 1
            try await wait(0.2)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { store.markWatched(Demo.eeaao.id) }
            try await wait(1.4)
            heartTaps += 1
            try await wait(0.2)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { store.toggleFavorite(Demo.spiderVerse.id) }
            try await wait(2.6)
        }
    }

    private func reset() {
        withAnimation(NucleusMotion.quick) {
            store.replace(with: WatchlistDocument(items: [Demo.item(Demo.eeaao), Demo.item(Demo.spiderVerse, order: 1)]), silent: true)
        }
    }
}

/// Severance half way through: Jump back in resumes the episode, the season rows tick on.
private struct ProgressScene: View {
    let active: Bool
    @State private var store = Demo.store([])
    private let id = Demo.severance.id

    var body: some View {
        let seasons = store.item(id)?.seasonProgress ?? []
        VStack(spacing: 0) {
            HomeSections()
            VStack(spacing: 12) {
                SeasonProgressSummary(item: store.item(id), watched: seasons.reduce(0) { $0 + $1.watched },
                                      total: seasons.reduce(0) { $0 + $1.episodeCount })
                NucleusSection {
                    ForEach(seasons.indices, id: \.self) { i in
                        SeasonProgressRow(season: Binding(get: { seasons[i] }, set: { _ in }), haptics: false)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .environment(store)
        .sceneLoop(active, reset: reset, still: reset) {
            for _ in 0..<12 {
                try await wait(0.25)
                store.updateItem(id) { $0.playback?.position += 7 }
            }
            for _ in 0..<5 {
                try await wait(0.7)
                withAnimation(NucleusMotion.quick) {
                    store.updateItem(id) {
                        $0.watchNextEpisode()
                        $0.playback?.position = 0
                    }
                }
            }
            try await wait(2.2)
        }
    }

    private func reset() {
        var show = Demo.item(Demo.severance, status: .watching)
        show.seasonProgress = [SeasonProgress(seasonNumber: 1, name: String(localized: "Season \(1)"), episodeCount: 9, watched: 6),
                               SeasonProgress(seasonNumber: 2, name: String(localized: "Season \(2)"), episodeCount: 10, watched: 0)]
        show.playback = Playback(url: "https://example.com/watch", position: 900, duration: 3180)
        show.set("lastWatchedAt", .string(Timestamp.now()))
        store.replace(with: WatchlistDocument(items: [show]), silent: true)
    }
}

private struct CollectionsScene: View {
    let active: Bool
    @State private var store = Demo.store(Self.adding.enumerated().map { Demo.item($0.element, order: $0.offset) }, collections: [Self.collection])
    private static let collection = Demo.collection(2, String(localized: "Date night"))
    private static let adding = [Demo.pastLives, Demo.laLaLand, Demo.beforeSunrise, Demo.holdovers]
    private var adding: [Demo.Title] { Self.adding }

    var body: some View {
        // Not a Group: an empty one would drop the modifiers, and the loop that fills it with them.
        VStack {
            if let collection = store.collection(Self.collection.id) {
                CollectionCard(collection: collection)
            }
        }
        .padding(.horizontal, 16)
        .environment(store)
        .sceneLoop(active, reset: reset, still: { reset(); store.addItems(adding.map(\.id), to: Self.collection.id) }) {
            for title in adding {
                try await wait(0.9)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { store.addItems([title.id], to: Self.collection.id) }
            }
            try await wait(2.4)
        }
    }

    private func reset() {
        let items = adding.enumerated().map { Demo.item($0.element, order: $0.offset) }
        store.replace(with: WatchlistDocument(items: items, collections: [Self.collection]), silent: true)
    }
}

/// Discover's "Picked for you" row, as the plugin draws it.
private struct DiscoverPicks: View {
    struct Pick: Identifiable {
        let title: Demo.Title
        let why: Text
        var id: String { title.id }
    }

    let picks: [Pick]
    var added: Set<String> = []
    var dismissed: Set<String> = []
    /// Where the fingertip taps: + on one card, × on another.
    var addTarget: String? = nil
    var addTaps = 0
    var dismissTarget: String? = nil
    var dismissTaps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Picked for you").font(.system(size: 20, weight: .bold)).foregroundStyle(Nucleus.primaryText)
                Text("From your MovieDNA").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(picks.filter { !dismissed.contains($0.id) }) { pick in
                        card(pick).transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func card(_ pick: Pick) -> some View {
        let isAdded = added.contains(pick.id)
        return VStack(alignment: .leading, spacing: 6) {
            TitlePoster(url: URL(string: pick.title.posterURL))
                .frame(width: 128, height: 192)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(isAdded ? AnyShapeStyle(Color.inLibrary) : AnyShapeStyle(Nucleus.primaryGradient)))
                        .overlay { if pick.id == addTarget { TapMark(count: addTaps) } }
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if !isAdded {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.black.opacity(0.45)))
                            .overlay { if pick.id == dismissTarget { TapMark(count: dismissTaps) } }
                            .padding(6)
                    }
                }
            Text(verbatim: pick.title.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(2)
            pick.why.font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText).lineLimit(2)
        }
        .frame(width: 128, alignment: .leading)
    }
}

/// Picks for someone who loved Dune: one gets added, one waved off.
private struct DiscoverScene: View {
    let active: Bool
    @State private var added: Set<String> = []
    @State private var dismissed: Set<String> = []
    @State private var addTaps = 0
    @State private var dismissTaps = 0

    private let picks: [DiscoverPicks.Pick] = [
        .init(title: Demo.bladeRunner, why: Text("Because you liked \(Demo.dune2.title)")),
        .init(title: Demo.sicario, why: Text(verbatim: "Crime · Thriller")),
        .init(title: Demo.prisoners, why: Text("Because you liked \(Demo.dune2.title)")),
        .init(title: Demo.arrival, why: Text("Because you liked \(Demo.dune2.title)")),
    ]

    var body: some View {
        DiscoverPicks(picks: picks, added: added, dismissed: dismissed,
                      addTarget: Demo.bladeRunner.id, addTaps: addTaps, dismissTarget: Demo.sicario.id, dismissTaps: dismissTaps)
            .sceneLoop(active, reset: { added = []; dismissed = [] }, still: { added = [Demo.bladeRunner.id] }) {
                try await wait(1.2)
                addTaps += 1
                try await wait(0.2)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { _ = added.insert(Demo.bladeRunner.id) }
                try await wait(1.4)
                dismissTaps += 1
                try await wait(0.25)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { _ = dismissed.insert(Demo.sicario.id) }
                try await wait(2.6)
                withAnimation(NucleusMotion.quick) { added = []; dismissed = [] }
                try await wait(0.5)
            }
    }
}

private struct StatsScene: View {
    let active: Bool
    @State private var shown = 0.0

    private static let items: [Item] = {
        var severance = Demo.item(Demo.severance, status: .watching)
        severance.seasonProgress = [SeasonProgress(seasonNumber: 1, name: "", episodeCount: 9, watched: 9),
                                    SeasonProgress(seasonNumber: 2, name: "", episodeCount: 10, watched: 3)]
        return [
            Demo.item(Demo.dune, status: .completed, rating: 9), Demo.item(Demo.arrival, status: .completed, rating: 8),
            Demo.item(Demo.pastLives, status: .completed, rating: 10), Demo.item(Demo.eeaao, status: .completed, rating: 9),
            Demo.item(Demo.spiderVerse, status: .completed, rating: 8), Demo.item(Demo.oppenheimer, status: .completed, rating: 9),
            severance, Demo.item(Demo.lastOfUs, status: .watching),
            Demo.item(Demo.dune2), Demo.item(Demo.poorThings), Demo.item(Demo.shogun), Demo.item(Demo.holdovers), Demo.item(Demo.bladeRunner),
        ]
    }()

    var body: some View {
        StatsOverview(items: Self.items, shown: shown)
            .padding(.horizontal, 16)
            .sceneLoop(active, repeats: false, reset: { shown = 0 }, still: { shown = 1 }) {
                try await wait(0.3)
                withAnimation(.easeOut(duration: 0.8)) { shown = 1 }
            }
    }
}

private struct SyncScene: View {
    let active: Bool
    @State private var syncing = false
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 0) {
            NucleusSection("Account") {
                HStack(spacing: 12) {
                    Text(verbatim: "E")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Nucleus.primaryGradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Ema").font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                        Text(verbatim: "@ema · Nucleus ID").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                NucleusRow("Sync now", subtitle: syncing ? Text("Syncing…") : Text("Synced \(Date(), format: .relative(presentation: .named))"),
                           icon: IconTile("arrow.triangle.2.circlepath", tint: .emerald)) {
                    if syncing { ProgressView().controlSize(.small) }
                }
                .overlay(alignment: .leading) { TapMark(count: taps).padding(.leading, 8) }
            }
            NucleusSection("Data") {
                NucleusRow("Export backup", icon: IconTile("square.and.arrow.up", tint: .sky)) { Chevron() }
                NucleusRow("Import backup", icon: IconTile("square.and.arrow.down", tint: .teal)) { Chevron() }
            }
        }
        .padding(.horizontal, 16)
        .sceneLoop(active, reset: { syncing = false }, still: { syncing = false }) {
            try await wait(1)
            taps += 1
            try await wait(0.2)
            syncing = true
            try await wait(1.6)
            syncing = false
            try await wait(2.6)
        }
    }
}
