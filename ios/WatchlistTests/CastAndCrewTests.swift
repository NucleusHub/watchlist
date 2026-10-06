import WatchlistPluginKit
import XCTest
@testable import CastAndCrewPlugin
@testable import Watchlist

final class CastAndCrewTests: XCTestCase {
    private func credit(_ id: Int, _ title: String, _ date: String?, _ role: String, _ department: String,
                        votes: Int = 0, kind: MediaKind = .movie) -> PluginPersonCredit {
        PluginPersonCredit(titleID: id, kind: kind, title: title, date: date, posterURL: nil, role: role, department: department, voteCount: votes)
    }

    private func person(knownFor: String?, _ credits: [PluginPersonCredit]) -> PluginPerson {
        PluginPerson(id: 1, name: "P", biography: "", knownFor: knownFor, birthday: nil, deathday: nil, birthplace: nil,
                     photoURL: nil, wikidataID: nil, imdbID: nil, credits: credits)
    }

    func testOccupationsPutTheMainOneFirstAndSkipOneOffs() {
        let p = person(knownFor: "Acting", [
            credit(1, "A", "2001-01-01", "Dom", "Acting"), credit(2, "B", "2003-01-01", "Dom", "Acting"),
            credit(3, "C", "2009-01-01", "Producer", "Production"), credit(4, "D", "2011-01-01", "Producer", "Production"),
            credit(5, "E", "2012-01-01", "Director", "Directing"),
            credit(6, "Talk", "2020-01-01", "Self", "Acting"), credit(7, "Talk 2", "2021-01-01", "Himself", "Acting"),
        ])
        XCTAssertEqual(Filmography(p).occupations, ["Actor", "Producer"], "one directing job isn't an occupation")
    }

    func testGroupsMergeJobsAndPutAppearancesLast() throws {
        let p = person(knownFor: "Directing", [
            credit(1, "Dune", "2021-09-15", "Director", "Directing", votes: 10),
            credit(2, "Arrival", "2016-11-10", "Director", "Directing", votes: 20),
            credit(3, "Announced", nil, "Director", "Directing"),
            credit(1, "Dune", "2021-09-15", "Screenplay", "Writing", votes: 10),
            credit(1, "Dune", "2021-09-15", "Producer", "Production", votes: 10),
            credit(9, "Oscars", "2022-03-27", "Self - Nominee", "Acting", kind: .show),
        ])
        let film = Filmography(p)
        XCTAssertEqual(film.groups.map(\.id), ["Directing", "Production", "Writing", Filmography.appearances])
        let directing = try XCTUnwrap(film.groups.first)
        XCTAssertEqual(directing.entries.map(\.title), ["Announced", "Dune", "Arrival"], "undated first, then newest")
        XCTAssertEqual(film.knownFor.first?.title, "Arrival", "most voted first")
        XCTAssertFalse(film.knownFor.contains { $0.title == "Oscars" })
    }

    func testMergeJoinsRolesOnTheSameTitle() {
        let merged = Filmography.merge([credit(1, "X", "2000-01-01", "Writer", "Writing"), credit(1, "X", "2000-01-01", "Story", "Writing"),
                                        credit(1, "X", "2000-01-01", "Writer", "Writing")])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.roles, ["Writer", "Story"])
    }

    func testStripPutsKeyCrewFirstWithJobsJoined() {
        let credits = PluginCredits(
            cast: [PluginCredit(personID: 1, name: "Star", role: "Lead", department: "Acting", photoURL: nil)],
            crew: [PluginCredit(personID: 2, name: "Boss", role: "Director", department: "Directing", photoURL: nil),
                   PluginCredit(personID: 3, name: "Grip", role: "Key Grip", department: "Crew", photoURL: nil),
                   PluginCredit(personID: 2, name: "Boss", role: "Screenplay", department: "Writing", photoURL: nil)]
        )
        let strip = CastAndCrewView.strip(credits)
        XCTAssertEqual(strip.map(\.name), ["Boss", "Star"])
        XCTAssertEqual(strip.first?.role, "Director, Screenplay")
    }

    func testWikipediaPrefersThePhonesLanguage() throws {
        let data = Data("""
        {"entities": {"Q22096": {"sitelinks": {
            "enwiki": {"title": "Denis Villeneuve", "url": "https://en.wikipedia.org/wiki/Denis_Villeneuve"},
            "cswiki": {"title": "Denis Villeneuve"}}}}}
        """.utf8)
        XCTAssertEqual(Wikipedia.article(in: data, id: "Q22096", languages: ["cs", "en"])?.absoluteString, "https://cs.wikipedia.org/wiki/Denis_Villeneuve")
        XCTAssertEqual(Wikipedia.article(in: data, id: "Q22096", languages: ["de", "en"])?.absoluteString, "https://en.wikipedia.org/wiki/Denis_Villeneuve")
        XCTAssertNil(Wikipedia.article(in: data, id: "Q22096", languages: ["de"]))
    }

    func testPersonParsesCombinedCreditsAndExternalIDs() throws {
        let raw = try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: Data("""
        {"id": 287, "name": "Brad Pitt", "biography": "", "known_for_department": "Acting", "birthday": "1963-12-18",
         "profile_path": "/p.jpg", "external_ids": {"wikidata_id": "Q35332", "imdb_id": "nm0000093"},
         "combined_credits": {
           "cast": [{"id": 550, "media_type": "movie", "title": "Fight Club", "release_date": "1999-10-15", "character": "Tyler Durden", "vote_count": 30000},
                    {"id": 1, "media_type": "person", "name": "skip"}],
           "crew": [{"id": 9, "media_type": "tv", "name": "Show", "first_air_date": "", "job": "Executive Producer", "department": "Production"}]}}
        """.utf8)).object)
        let p = TMDb.person(raw)
        XCTAssertEqual(p.name, "Brad Pitt")
        XCTAssertEqual(p.wikidataID, "Q35332")
        XCTAssertNil(p.biography.isEmpty ? nil : p.biography)
        XCTAssertEqual(p.credits.count, 2)
        XCTAssertEqual(p.credits.first?.role, "Tyler Durden")
        XCTAssertEqual(p.credits.first?.year, "1999")
        XCTAssertEqual(p.credits.last?.kind, .show)
        XCTAssertNil(p.credits.last?.date, "an empty date is unknown")
    }

    @MainActor
    func testFollowingFeedsMovieDNAAndUnfollowingClearsIt() {
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        store.setFollowing(true, personID: 287, name: "Brad Pitt", photo: "https://image.tmdb.org/t/p/h632/p.jpg")
        let trait = store.movieDNA.trait(DNAKey.person(287))
        XCTAssertEqual(trait?.followed, true)
        XCTAssertGreaterThan(trait?.strength ?? 0, 50)
        XCTAssertEqual(trait?.poster, "https://image.tmdb.org/t/p/h632/p.jpg")
        store.setFollowing(false, personID: 287, name: "Brad Pitt", photo: nil)
        XCTAssertNil(store.movieDNA.trait(DNAKey.person(287)))
        XCTAssertTrue(store.movieDNASettings.entries.isEmpty)
    }

    func testHandEnteredCreditsRoundTripAndMapToPlugins() {
        var item = Item(title: "Home video", type: .movie)
        item.customCredits = [
            CustomCredit(name: "Mum", role: "Herself", isCast: true),
            CustomCredit(name: "Brad Pitt", role: "Cameo", isCast: true, personID: 287, photo: "https://image.tmdb.org/t/p/w185/p.jpg"),
            CustomCredit(name: "Dad", role: CustomCredit.Job.director.rawValue, isCast: false),
            CustomCredit(name: "Dad", role: CustomCredit.Job.editor.rawValue, isCast: false),
        ]
        let back = Item(raw: item.raw)
        XCTAssertEqual(back.customCredits, item.customCredits)
        let credits = PluginCredits(custom: back.customCredits)
        XCTAssertEqual(credits.cast.map(\.personID), [0, 287])
        XCTAssertEqual(credits.crew.map(\.department), ["Directing", "Editing"])
        let strip = CastAndCrewView.strip(credits, allCrew: true)
        XCTAssertEqual(strip.map(\.name), ["Dad", "Mum", "Brad Pitt"], "all hand-entered crew, one bubble per typed-in name")
        XCTAssertEqual(strip.first?.role, "Director, Editor")
        item.customCredits = []
        XCTAssertEqual(item.raw["customCredits"], .null)
    }
}
