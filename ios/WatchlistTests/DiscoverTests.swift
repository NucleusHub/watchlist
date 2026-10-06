import NucleusPlugins
import WatchlistPluginKit
import XCTest
@testable import DiscoverPlugin
@testable import Watchlist

final class DiscoverTests: XCTestCase {
    private func dna(enabled: Bool = true, genres: [(String, Double)] = [], titles: [PluginTitleTrait] = [],
                     people: [PluginPersonTrait] = [], notInterested: Set<String> = []) -> PluginMovieDNA {
        PluginMovieDNA(enabled: enabled, genres: genres.map { PluginTrait(name: $0.0, strength: $0.1) },
                       titles: titles, people: people, notInterested: notInterested)
    }

    private func suggestion(_ id: Int, genres: [String], vote: Double = 7) -> Suggestion {
        Suggestion(kind: .movie, tmdbID: id, title: "T\(id)", date: "2024-01-01", posterURL: nil, genres: genres,
                   voteAverage: vote, voteCount: 500, reason: .trending)
    }

    func testDNATasteSeedsFromStrongTitlesAndExcludesTheLibraryAndRefusals() {
        let library = [PluginLibraryTitle(kind: .movie, tmdbID: 1, title: "Owned", genres: [], rating: nil, favorite: false, isCompleted: false, finishedAt: nil)]
        let taste = Taste.from(dna: dna(genres: [("Drama", 80), ("Horror", -60)],
                                        titles: [PluginTitleTrait(kind: .movie, tmdbID: 603, name: "The Matrix", strength: 90),
                                                 PluginTitleTrait(kind: .movie, tmdbID: 9, name: "Meh", strength: 10)],
                                        people: [PluginPersonTrait(personID: 1, name: "A", strength: 76, followed: true),
                                                 PluginPersonTrait(personID: 2, name: "B", strength: 40, followed: false)],
                                        notInterested: ["movie:5"]), library: library)
        XCTAssertEqual(taste.seeds.map(\.title), ["The Matrix"], "weak titles don't seed")
        XCTAssertEqual(taste.followed.map(\.personID), [1])
        XCTAssertEqual(taste.excluded, ["movie:1", "movie:5"])
        XCTAssertGreaterThan(taste.fit(["Drama"]), 0)
        XCTAssertLessThan(taste.fit(["Horror"]), 0)
        XCTAssertGreaterThan(taste.score(suggestion(2, genres: ["Drama"])), taste.score(suggestion(3, genres: ["Horror"])))
    }

    func testLibraryTasteFavoursRecentWellRatedFinishedTitles() {
        let now = Date()
        func title(_ id: Int, _ genres: [String], rating: Double?, daysAgo: Double, done: Bool = true) -> PluginLibraryTitle {
            PluginLibraryTitle(kind: .movie, tmdbID: id, title: "T\(id)", genres: genres, rating: rating, favorite: false,
                               isCompleted: done, finishedAt: now.addingTimeInterval(-daysAgo * 86400))
        }
        let taste = Taste.from(library: [title(1, ["Comedy"], rating: 9, daysAgo: 2), title(2, ["Horror"], rating: 2, daysAgo: 1),
                                         title(3, ["Western"], rating: 10, daysAgo: 2, done: false)],
                               notInterested: [], now: now)
        XCTAssertGreaterThan(taste.genres["comedy"] ?? 0, 0.9, "scaled against the strongest feeling, liked or not")
        XCTAssertLessThan(taste.genres["horror"] ?? 0, 0)
        XCTAssertNil(taste.genres["western"], "unfinished titles don't count")
        XCTAssertEqual(taste.seeds.map(\.tmdbID), [1], "only liked titles seed")
        XCTAssertFalse(taste.fromDNA)
    }

    func testUnexploredSkipsKnownAndDislikedGenres() {
        var taste = Taste()
        taste.genres = ["drama": 0.9, "horror": -0.6, "romance": 0.05]
        let picks = taste.unexplored(from: ["Drama", "Horror", "Romance", "Western", "War"], limit: 2, day: 3)
        XCTAssertFalse(picks.contains("Drama"))
        XCTAssertFalse(picks.contains("Horror"), "disliked isn't unexplored")
        XCTAssertTrue(Set(picks).isSubset(of: ["Romance", "Western", "War"]))
        XCTAssertEqual(picks.count, 2)
        XCTAssertEqual(picks, taste.unexplored(from: ["War", "Western", "Romance", "Horror", "Drama"], limit: 2, day: 3), "stable within a day")
    }

    func testListParsingKeepsPostersAndReadsMixedTypes() {
        let data = Data("""
        {"results": [
          {"id": 1, "media_type": "movie", "title": "A", "release_date": "2024-02-01", "poster_path": "/a.jpg", "genre_ids": [18, 999], "vote_average": 7.5, "vote_count": 300},
          {"id": 2, "media_type": "tv", "name": "B", "first_air_date": "", "poster_path": "/b.jpg", "genre_ids": [10765]},
          {"id": 3, "media_type": "movie", "title": "No poster"},
          {"id": 4, "media_type": "person", "name": "Someone", "poster_path": "/p.jpg"}]}
        """.utf8)
        let genres = GenreMap(names: [.movie: [18: "Drama"], .show: [10765: "Sci-Fi & Fantasy"]])
        let list = TMDbList.parse(data, kind: nil, genres: genres, reason: .trending)
        XCTAssertEqual(list.map(\.id), ["movie:1", "show:2"])
        XCTAssertEqual(list.first?.genres, ["Drama"])
        XCTAssertEqual(list.first?.year, "2024")
        XCTAssertNil(list.last?.date)
        XCTAssertEqual(genres.id("drama", .movie), 18)
    }

    func testTrailerPicksAnOfficialYouTubeTrailer() {
        let data = Data("""
        {"results": [{"site": "YouTube", "key": "teaser1", "type": "Teaser"}, {"site": "Vimeo", "key": "v", "type": "Trailer"},
                     {"site": "YouTube", "key": "fan", "type": "Trailer", "official": false},
                     {"site": "YouTube", "key": "real", "type": "Trailer", "official": true}]}
        """.utf8)
        XCTAssertEqual(TMDbList.trailer(data), "real")
        XCTAssertEqual(TMDbList.trailer(Data(#"{"results": [{"site": "YouTube", "key": "t", "type": "Teaser"}]}"#.utf8)), "t")
        XCTAssertNil(TMDbList.trailer(Data(#"{"results": []}"#.utf8)))
    }

    func testFingerprintIgnoresSmallChangesButNotNewFollows() {
        let a = DiscoverModel.fingerprint(dna(genres: [("Drama", 81)]))
        XCTAssertEqual(a, DiscoverModel.fingerprint(dna(genres: [("Drama", 84)])))
        XCTAssertNotEqual(a, DiscoverModel.fingerprint(dna(genres: [("Drama", 81)], people: [PluginPersonTrait(personID: 1, name: "A", strength: 76, followed: true)])))
        XCTAssertEqual(DiscoverModel.fingerprint(dna(enabled: false)), "off")
    }

    @MainActor
    func testNotInterestedLandsInMovieDNAAndCanBeUndone() {
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let host = AppHost(store: store, navigator: Navigator(), registry: .init(app: "watchlist", state: InMemoryPluginStateStore()))
        host.markNotInterested(.show, tmdbID: 1399, title: "Got", genres: ["Drama"])
        XCTAssertEqual(host.movieDNA.notInterested, ["show:1399"])
        XCTAssertLessThan(store.movieDNA.trait(DNAKey.genre("Drama"))?.strength ?? 0, 0, "its genres count a little against them")
        store.clearNotInterested("show:1399")
        XCTAssertTrue(host.movieDNA.notInterested.isEmpty)
    }

    private func card(_ id: Int, _ genres: [String], kind: MediaKind = .movie) -> Suggestion {
        Suggestion(kind: kind, tmdbID: id, title: "T\(id)", date: nil, posterURL: nil, genres: genres, voteAverage: 7, voteCount: 500, reason: .trending)
    }

    func testBlendTakesSourcesInTurnsAndCapsAGenre() {
        let anime = (1...10).map { card($0, ["Animation", "Action"], kind: .show) }
        let drama = (11...13).map { card($0, ["Drama"]) }
        let thriller = (21...23).map { card($0, ["Thriller"]) }
        let row = Taste.blend([anime, drama, thriller], limit: 9)
        XCTAssertEqual(row.count, 9)
        XCTAssertLessThanOrEqual(row.filter { $0.genres.first == "Animation" }.count, 3, "one main genre is about a third")
        XCTAssertEqual(Set(row.filter { $0.genres.first == "Drama" }.map(\.tmdbID)), [11, 12, 13])
        XCTAssertEqual(Taste.blend([anime], limit: 5).count, 5, "with nothing else, the cap gives way")
    }

    func testMoviesAndShowsAlternate() {
        let list = [card(1, [], kind: .show), card(2, [], kind: .show), card(3, []), card(4, [], kind: .show), card(5, [])]
        XCTAssertEqual(Taste.alternateKinds(list).map(\.kind), [.show, .movie, .show, .movie, .show])
    }

    func testSeedsSpreadOverGenres() {
        let seeds = [Taste.Seed(kind: .show, tmdbID: 1, title: "Anime A", weight: 0.9), Taste.Seed(kind: .show, tmdbID: 2, title: "Anime B", weight: 0.85),
                     Taste.Seed(kind: .movie, tmdbID: 3, title: "Drama", weight: 0.6)]
        let genres: [Int: [String]] = [1: ["Animation", "Action"], 2: ["Animation", "Action"], 3: ["Drama"]]
        let picked = Taste.diverseSeeds(seeds, genresOf: { genres[$0.tmdbID] ?? [] }, limit: 2)
        XCTAssertEqual(picked.map(\.title), ["Anime A", "Drama"], "a second anime adds nothing new")
    }

    func testAnimationOnlyWhenLikedAndUntouchedGenresCountAgainst() {
        var taste = Taste()
        taste.genres = ["drama": 0.8]
        XCTAssertTrue(taste.isUnwantedAnimation(card(1, ["Animation", "Drama"])))
        XCTAssertGreaterThan(taste.fit(["Drama"]), taste.fit(["Drama", "Western"]), "an unknown genre pulls down")
        taste.genres["animation"] = 0.5
        XCTAssertFalse(taste.isUnwantedAnimation(card(1, ["Animation"])))
    }
}
