import XCTest
@testable import Watchlist

@MainActor
final class MovieDNATests: XCTestCase {
    private func store() -> WatchlistStore { WatchlistStore(fileURL: nil, document: WatchlistDocument()) }

    private func add(_ s: WatchlistStore, _ title: String, tmdb: Int, genres: [String], rating: Double? = nil,
                     favorite: Bool = false, status: WatchStatus = .completed) -> Item {
        var item = Item(title: title, type: .movie)
        item.tmdbId = tmdb
        item.genres = genres
        item.rating = rating
        item.favorite = favorite
        item.status = status
        return s.createItem(item)!
    }

    func testRatingsAndFavoritesShapeGenres() {
        let s = store()
        _ = add(s, "Alien", tmdb: 348, genres: ["Horror", "Sci-Fi"], rating: 10, favorite: true)
        _ = add(s, "Bad Rom-Com", tmdb: 1, genres: ["Romance"], rating: 2)
        let dna = s.movieDNA
        XCTAssertGreaterThan(dna.trait(DNAKey.genre("Horror"))!.strength, 0)
        XCTAssertLessThan(dna.trait(DNAKey.genre("romance"))!.strength, 0)
        XCTAssertEqual(dna.traits(.title).first?.name, "Alien", "strongest first")
        XCTAssertEqual(dna.traits.first?.kind, .title)
    }

    func testListOnlyTitlesFeedGenresButAreNoTrait() {
        let s = store()
        let item = add(s, "Planned", tmdb: 5, genres: ["Drama"], status: .planned)
        XCTAssertNil(s.movieDNA.trait(DNAKey.title(item)))
        XCTAssertGreaterThan(s.movieDNA.trait(DNAKey.genre("Drama"))!.strength, 0)
    }

    func testNeutralGenresStayAndTitlesCarryPosters() {
        let s = store()
        var item = Item(title: "Meh", type: .movie)
        item.tmdbId = 7
        item.genres = ["Comedy"]
        item.rating = 6
        item.status = .completed
        item.posterUrl = "https://image.tmdb.org/t/p/w500/x.jpg"
        let created = s.createItem(item)!
        XCTAssertEqual(s.movieDNA.trait(DNAKey.genre("Comedy"))?.strength, 0, "a 6/10 is neutral, but the genre is still listed")
        XCTAssertEqual(s.movieDNA.trait(DNAKey.title(created))?.poster, item.posterUrl)
        s.addToDNA(kind: .title, key: "movie:99", name: "Elsewhere", poster: "data:image/png;base64,AAAA", strength: 40)
        XCTAssertNil(s.movieDNASettings.entries["movie:99"]?.poster, "inlined images don't go into synced settings")
    }

    func testInterestedStacksWithFalloffAndFades() {
        let now = Date()
        let one = MovieDNAEngine.boost([Timestamp.string(now)], now: now)
        let two = MovieDNAEngine.boost([Timestamp.string(now), Timestamp.string(now)], now: now)
        XCTAssertEqual(one, MovieDNAEngine.boostValue, accuracy: 0.0001)
        XCTAssertGreaterThan(two, one)
        XCTAssertLessThan(two, 2 * one, "later presses count less")
        let old = MovieDNAEngine.boost([Timestamp.string(now.addingTimeInterval(-MovieDNAEngine.boostHalfLife * 86400))], now: now)
        XCTAssertEqual(old, one / 2, accuracy: 0.0001)
    }

    func testInterestedPressesAreCountedAndCapped() {
        let s = store()
        let item = add(s, "Dune", tmdb: 438631, genres: ["Sci-Fi"], status: .planned)
        for _ in 0..<(MovieDNAEngine.maxBoosts + 5) { s.markInterested(item) }
        XCTAssertEqual(s.interestCount(item), MovieDNAEngine.maxBoosts)
        let trait = s.movieDNA.trait(DNAKey.title(item))
        XCTAssertEqual(trait?.boosts, MovieDNAEngine.maxBoosts)
        XCTAssertGreaterThan(trait?.strength ?? 0, 0)
    }

    func testManualStrengthOverridesAndResets() throws {
        let s = store()
        _ = add(s, "Alien", tmdb: 348, genres: ["Horror"], rating: 9)
        let horror = try XCTUnwrap(s.movieDNA.trait(DNAKey.genre("Horror")))
        s.setDNAStrength(-40, for: horror)
        XCTAssertEqual(s.movieDNA.trait(horror.key)?.strength, -40)
        XCTAssertTrue(s.movieDNA.trait(horror.key)?.isManual == true)
        s.setDNAStrength(nil, for: horror)
        XCTAssertEqual(s.movieDNA.trait(horror.key)?.strength, horror.learned)
        XCTAssertNil(s.movieDNASettings.entries[horror.key], "an entry with nothing left is dropped")
    }

    func testRemovedLearnedTraitStaysOutAndStopsFeedingGenres() throws {
        let s = store()
        let item = add(s, "Alien", tmdb: 348, genres: ["Horror"], rating: 10)
        let title = try XCTUnwrap(s.movieDNA.trait(DNAKey.title(item)))
        s.removeFromDNA(title)
        XCTAssertNil(s.movieDNA.trait(title.key))
        XCTAssertNil(s.movieDNA.trait(DNAKey.genre("Horror")))
    }

    func testAddedTraitsAndRemovingThem() throws {
        let s = store()
        s.addToDNA(kind: .genre, key: DNAKey.genre("Western"), name: "Western", strength: 73)
        let western = try XCTUnwrap(s.movieDNA.trait(DNAKey.genre("Western")))
        XCTAssertEqual(western.strength, 73)
        XCTAssertNil(western.learned)
        s.removeFromDNA(western)
        XCTAssertNil(s.movieDNA.trait(western.key))
        XCTAssertTrue(s.movieDNASettings.entries.isEmpty, "nothing learned to hide, so it's simply gone")
    }

    func testRebuildKeepsFollowsAndNotInterestedOnly() throws {
        let s = store()
        let item = add(s, "Alien", tmdb: 348, genres: ["Horror"], rating: 10)
        s.markInterested(item)
        s.addToDNA(kind: .genre, key: DNAKey.genre("Western"), name: "Western", strength: 50)
        s.updateSettings { settings in
            settings.movieDNA.edit(DNAKey.person(287), kind: .person, name: "Brad Pitt") { $0.followed = true }
            settings.movieDNA.notInterested["movie:9"] = NotInterested(name: "Nope", genres: ["Romance"], at: Timestamp.now())
        }
        s.rebuildMovieDNA()
        let dna = s.movieDNASettings
        XCTAssertEqual(Set(dna.entries.keys), [DNAKey.person(287)])
        XCTAssertNotNil(dna.notInterested["movie:9"])
        XCTAssertEqual(s.movieDNA.trait(DNAKey.person(287))?.followed, true)
        XCTAssertLessThan(s.movieDNA.trait(DNAKey.genre("Romance"))?.strength ?? 0, 0)
    }

    func testDisabledLearnsNothingAndKeepsEntries() {
        let s = store()
        let item = add(s, "Alien", tmdb: 348, genres: ["Horror"], rating: 10)
        s.addToDNA(kind: .genre, key: DNAKey.genre("Western"), name: "Western", strength: 50)
        s.setMovieDNAEnabled(false)
        XCTAssertTrue(s.movieDNA.traits.isEmpty)
        s.markInterested(item)
        XCTAssertEqual(s.interestCount(item), 0)
        s.setMovieDNAEnabled(true)
        XCTAssertEqual(s.movieDNA.trait(DNAKey.genre("Western"))?.strength, 50)
    }

    func testRoundTripKeepsUnknownFieldsAndSyncsInSettings() throws {
        let s = store()
        let item = add(s, "Alien", tmdb: 348, genres: ["Horror"], rating: 10)
        s.markInterested(item)
        var doc = s.document
        doc.settings.raw["somethingNew"] = "kept"
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(WatchlistDocument.self, from: data)
        XCTAssertEqual(back.settings.movieDNA, s.movieDNASettings)
        XCTAssertEqual(back.settings.raw["somethingNew"], "kept")
        XCTAssertNotNil(back.settings.updatedAt, "a press stamps the settings so it syncs")
    }

    func testTitleKeysMatchAcrossTypesAndTypedInTitles() {
        var typed = Item(title: "Home video", type: .movie)
        typed.set("_id", "abc")
        XCTAssertEqual(DNAKey.title(typed), "item:abc")
        var show = Item(title: "S", type: .show)
        show.tmdbId = 1399
        XCTAssertEqual(DNAKey.title(show), "show:1399")
        XCTAssertEqual(DNAKey.genre(" Sci-Fi "), "genre:sci-fi")
    }
}
