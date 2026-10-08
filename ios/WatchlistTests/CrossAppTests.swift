import XCTest
@testable import Watchlist

@MainActor
final class CrossAppTests: XCTestCase {
    private func store() -> WatchlistStore { WatchlistStore(fileURL: nil, document: WatchlistDocument()) }

    private func show(_ s: WatchlistStore, watched: [Int] = [2, 0], counts: [Int] = [8, 10]) throws -> String {
        var item = Item(title: "Severance", type: .show)
        item.seasonProgress = zip(counts, watched).enumerated().map {
            SeasonProgress(seasonNumber: $0.offset + 1, name: "Season \($0.offset + 1)", episodeCount: $0.element.0, watched: $0.element.1)
        }
        item.status = .watching
        return try XCTUnwrap(s.createItem(item)).id
    }

    private func apply(_ type: String, _ payload: JSONValue, _ s: WatchlistStore) -> CrossApp.Settlement {
        CrossApp.apply(type: type, payload: payload, to: s)
    }

    private func watched(_ s: WatchlistStore, _ id: String, season: Int) -> Int? {
        s.item(id)?.seasonProgress?.first { $0.seasonNumber == season }?.watched
    }

    // MARK: markWatched

    func testRangeMarkUsesMaxAndClampsToEpisodeCount() throws {
        let s = store()
        let id = try show(s, watched: [5, 0])
        let r = apply("markWatched", ["itemId": .string(id), "season": 1, "fromEp": 1, "toEp": 3], s)
        XCTAssertEqual(r, .applied(["previousWatched": 5, "watched": 5, "previousStatus": "watching"]))
        XCTAssertEqual(watched(s, id, season: 1), 5, "never takes progress back")

        _ = apply("markWatched", ["itemId": .string(id), "season": 2, "fromEp": 1, "toEp": 99], s)
        XCTAssertEqual(watched(s, id, season: 2), 10)
        XCTAssertEqual(s.item(id)?.status, .watching)

        _ = apply("markWatched", ["itemId": .string(id), "season": 1, "fromEp": 6, "toEp": 8], s)
        XCTAssertEqual(watched(s, id, season: 1), 8)
        XCTAssertEqual(s.item(id)?.status, .completed)
        XCTAssertNotNil(s.item(id)?.completedAt)
    }

    func testMarkMovieOrWithoutSeasonMarksWholeTitle() throws {
        let s = store()
        let movie = try XCTUnwrap(s.createItem(Item(title: "Dune", type: .movie))).id
        // A season on a movie is ignored.
        XCTAssertEqual(apply("markWatched", ["itemId": .string(movie), "season": 1, "toEp": 2], s),
                       .applied(["previousStatus": "planned"]))
        XCTAssertEqual(s.item(movie)?.status, .completed)

        let id = try show(s)
        XCTAssertEqual(apply("markWatched", ["itemId": .string(id)], s), .applied([
            "previousStatus": "watching", "previousSeasons": [["number": 1, "watched": 2], ["number": 2, "watched": 0]],
        ]))
        XCTAssertEqual(s.item(id)?.seasonProgress?.map(\.watched), [8, 10])
        XCTAssertEqual(s.item(id)?.status, .completed)
    }

    func testRepeatedMarkChangesNothing() throws {
        let s = store()
        let id = try show(s)
        let payload: JSONValue = ["itemId": .string(id), "season": 1, "fromEp": 3, "toEp": 6]
        _ = apply("markWatched", payload, s)
        let after = s.document
        let revision = s.revision
        _ = apply("markWatched", payload, s)
        XCTAssertEqual(s.document, after)
        XCTAssertEqual(s.revision, revision, "no write, so no push")

        let movie = try XCTUnwrap(s.createItem(Item(title: "Dune", type: .movie))).id
        _ = apply("markWatched", ["itemId": .string(movie)], s)
        let stamped = s.item(movie)?.updatedAt
        _ = apply("markWatched", ["itemId": .string(movie)], s)
        XCTAssertEqual(s.item(movie)?.updatedAt, stamped)
    }

    // MARK: unmarkWatched

    func testUnmarkSeasonUsesMinAndRecomputesStatus() throws {
        let s = store()
        let id = try show(s, watched: [8, 10])
        s.updateItem(id) { $0.status = .completed }
        let r = apply("unmarkWatched", ["itemId": .string(id), "season": 2, "restoreTo": 4, "restoreStatus": "watching"], s)
        XCTAssertEqual(r, .applied(["previousWatched": 10, "previousStatus": "completed"]))
        XCTAssertEqual(watched(s, id, season: 2), 4)
        XCTAssertEqual(s.item(id)?.status, .watching)
        XCTAssertNil(s.item(id)?.completedAt)

        _ = apply("unmarkWatched", ["itemId": .string(id), "season": 2, "restoreTo": 7, "restoreStatus": "watching"], s)
        XCTAssertEqual(watched(s, id, season: 2), 4, "never adds progress")
    }

    func testUnmarkWithoutSeasonRestoresStatus() throws {
        let s = store()
        let movie = try XCTUnwrap(s.createItem(Item(title: "Dune", type: .movie))).id
        s.markWatched(movie)
        XCTAssertEqual(apply("unmarkWatched", ["itemId": .string(movie), "restoreStatus": "planned"], s),
                       .applied(["previousStatus": "completed"]))
        XCTAssertEqual(s.item(movie)?.status, .planned)

        // Not completed any more: left alone.
        s.updateItem(movie) { $0.status = .watching }
        _ = apply("unmarkWatched", ["itemId": .string(movie), "restoreStatus": "planned"], s)
        XCTAssertEqual(s.item(movie)?.status, .watching)
    }

    func testUnmarkRefusesOnceWatchedPastWhatTheMarkLeft() throws {
        let s = store()
        let id = try show(s, watched: [2, 0])
        XCTAssertEqual(apply("markWatched", ["itemId": .string(id), "season": 1, "fromEp": 3, "toEp": 5], s),
                       .applied(["previousWatched": 2, "watched": 5, "previousStatus": "watching"]))
        // Watched two more by hand after the task marked 3–5.
        s.markSeasonWatched(id, season: 1, through: 7)
        let unmark: JSONValue = ["itemId": .string(id), "season": 1, "restoreTo": 2, "expectWatched": 5, "restoreStatus": "watching"]
        XCTAssertEqual(apply("unmarkWatched", unmark, s), .rejected("progressMoved"))
        XCTAssertEqual(watched(s, id, season: 1), 7, "progress made since is kept")

        // Back where the task left it: the rollback goes through.
        s.unmarkSeasonWatched(id, season: 1, keeping: 5)
        XCTAssertEqual(apply("unmarkWatched", unmark, s), .applied(["previousWatched": 5, "previousStatus": "watching"]))
        XCTAssertEqual(watched(s, id, season: 1), 2)
    }

    func testUnmarkWholeShowRestoresEachSeason() throws {
        let s = store()
        let id = try show(s, watched: [2, 0])
        _ = apply("markWatched", ["itemId": .string(id)], s)
        XCTAssertEqual(s.item(id)?.seasonProgress?.map(\.watched), [8, 10])
        let unmark: JSONValue = ["itemId": .string(id), "restoreStatus": "watching",
                                 "restoreSeasons": [["number": 1, "watched": 2], ["number": 2, "watched": 0]]]
        XCTAssertEqual(apply("unmarkWatched", unmark, s), .applied(["previousStatus": "completed"]))
        XCTAssertEqual(s.item(id)?.seasonProgress?.map(\.watched), [2, 0])
        XCTAssertEqual(s.item(id)?.status, .watching)
    }

    // MARK: Rejections

    func testRejections() throws {
        let s = store()
        let id = try show(s)
        XCTAssertEqual(apply("markWatched", ["itemId": "000000000000000000000000"], s), .rejected("itemNotFound"))
        XCTAssertEqual(apply("markWatched", ["itemId": .string(id), "season": 7, "toEp": 2], s), .rejected("seasonNotFound"))
        XCTAssertEqual(apply("deleteEverything", ["itemId": .string(id)], s), .rejected("unknownType"))
        XCTAssertEqual(apply("markWatched", "nope", s), .rejected("badPayload"))
        XCTAssertEqual(apply("markWatched", ["season": 1], s), .rejected("badPayload"))
        XCTAssertEqual(apply("markWatched", ["itemId": .string(id), "season": "one"], s), .rejected("badPayload"))
        XCTAssertEqual(apply("markWatched", ["itemId": .string(id), "season": 1, "fromEp": 5, "toEp": 2], s), .rejected("badPayload"))
        XCTAssertEqual(apply("unmarkWatched", ["itemId": .string(id)], s), .rejected("badPayload"))
        XCTAssertEqual(apply("unmarkWatched", ["itemId": .string(id), "restoreStatus": "lost"], s), .rejected("badPayload"))

        var bare = Item(title: "No seasons", type: .show)
        bare.status = .planned
        let bareID = try XCTUnwrap(s.createItem(bare)).id
        XCTAssertEqual(apply("markWatched", ["itemId": .string(bareID), "season": 1, "toEp": 2], s), .rejected("seasonNotFound"))
        XCTAssertEqual(watched(s, id, season: 1), 2, "rejections change nothing")
    }

    // MARK: Library view

    func testLibraryProjection() throws {
        let s = store()
        var movie = Item(title: "Dune", type: .movie)
        movie.tmdbId = 438631
        movie.posterUrl = "https://image.tmdb.org/t/p/w500/d.jpg"
        let movieID = try XCTUnwrap(s.createItem(movie)).id
        var bare = Item(title: "Bare", type: .show)
        bare.posterUrl = "data:image/jpeg;base64,AAAA"
        _ = try XCTUnwrap(s.createItem(bare))
        let showID = try show(s)
        let gone = try XCTUnwrap(s.createItem(Item(title: "Gone", type: .movie))).id
        s.deleteItem(gone)

        let items = try XCTUnwrap(CrossApp.library(s.document).object?["items"]?.array)
        XCTAssertEqual(items.count, 3)
        let byID = Dictionary(uniqueKeysWithValues: items.compactMap { v in v.object.map { ($0["id"]?.string ?? "", $0) } })
        XCTAssertNil(byID[gone])
        XCTAssertEqual(byID[movieID].map(JSONValue.object), [
            "id": .string(movieID), "title": "Dune", "type": "movie", "tmdbId": 438631,
            "poster": "https://image.tmdb.org/t/p/w500/d.jpg", "status": "planned", "seasons": [],
        ])
        let bareEntry = try XCTUnwrap(items.compactMap(\.object).first { $0["title"] == "Bare" })
        XCTAssertEqual(bareEntry["seasons"], [])
        XCTAssertEqual(bareEntry["poster"], .null)
        XCTAssertEqual(bareEntry["tmdbId"], .null)
        XCTAssertEqual(byID[showID]?["seasons"], [
            ["number": 1, "name": "Season 1", "episodeCount": 8, "watched": 2],
            ["number": 2, "name": "Season 2", "episodeCount": 10, "watched": 0],
        ])
    }

    func testLibraryHashFollowsContent() throws {
        let s = store()
        let id = try show(s)
        let before = CrossApp.hash(CrossApp.library(s.document))
        XCTAssertEqual(before, CrossApp.hash(CrossApp.library(s.document)))
        s.markSeasonWatched(id, season: 1, through: 4)
        XCTAssertNotEqual(before, CrossApp.hash(CrossApp.library(s.document)))
    }
}
