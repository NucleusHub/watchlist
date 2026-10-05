import XCTest
@testable import Watchlist

@MainActor
final class StoreTests: XCTestCase {
    private func store() -> WatchlistStore { WatchlistStore(fileURL: nil, document: WatchlistDocument()) }

    func testCreateFillsDefaultsAndStamps() throws {
        let s = store()
        var draft = Item(title: "  Dune  ", type: .movie)
        draft.genres = ["Sci-Fi", "sci-fi", " ", String(repeating: "x", count: 50)]
        let item = try XCTUnwrap(s.createItem(draft))
        XCTAssertEqual(item.title, "Dune")
        XCTAssertEqual(item.id.count, 24)
        XCTAssertEqual(item.genres, ["Sci-Fi", String(repeating: "x", count: 40)])
        XCTAssertNotNil(item.createdAt)
        XCTAssertEqual(item.raw["notes"], "")
        XCTAssertNil(s.createItem(Item(title: "   ", type: .movie)))
    }

    func testCompletedAtFollowsStatus() throws {
        let s = store()
        let id = try XCTUnwrap(s.createItem(Item(title: "A", type: .movie))).id
        s.markWatched(id)
        XCTAssertNotNil(s.item(id)?.completedAt)
        s.updateItem(id) { $0.set("completedAt", "1999-01-01T00:00:00.000Z") }
        XCTAssertNotEqual(s.item(id)?.completedAt, "1999-01-01T00:00:00.000Z", "completedAt can't be written directly")
        s.updateItem(id) { $0.status = .planned }
        XCTAssertNil(s.item(id)?.completedAt)
    }

    func testMarkWatchedFillsSeasons() throws {
        let s = store()
        var show = Item(title: "S", type: .show)
        show.seasonProgress = [SeasonProgress(seasonNumber: 1, name: "S1", episodeCount: 8, watched: 2)]
        let id = try XCTUnwrap(s.createItem(show)).id
        s.markWatched(id)
        XCTAssertEqual(s.item(id)?.seasonProgress?.first?.watched, 8)
        XCTAssertEqual(s.item(id)?.status, .completed)
    }

    func testDeleteLeavesTombstoneAndStripsCollection() throws {
        let s = store()
        let col = try XCTUnwrap(s.createCollection(name: "Picks"))
        let id = try XCTUnwrap(s.createItem(Item(title: "A", type: .movie))).id
        s.addItems([id], to: col.id)
        XCTAssertEqual(s.members(of: col.id).count, 1)
        s.deleteCollection(col.id)
        XCTAssertEqual(s.item(id)?.collectionIds, [])
        XCTAssertNotNil(s.document.deleted[col.id])
        s.deleteItem(id)
        XCTAssertNotNil(s.document.deleted[id])
        XCTAssertTrue(s.document.items.isEmpty)
    }

    func testOrderedMembersPutsUnorderedLast() throws {
        let s = store()
        let col = try XCTUnwrap(s.createCollection(name: "C"))
        let a = try XCTUnwrap(s.createItem(Item(title: "A", type: .movie))).id
        let b = try XCTUnwrap(s.createItem(Item(title: "B", type: .movie))).id
        let c = try XCTUnwrap(s.createItem(Item(title: "C", type: .movie))).id
        s.addItems([a, b, c], to: col.id)
        s.saveOrder([c, a], in: col.id)
        let ordered = s.orderedMembers(of: try XCTUnwrap(s.collection(col.id))).map(\.id)
        XCTAssertEqual(ordered, [c, a, b])
    }

    func testSettingsStampOnlyOnChange() {
        let s = store()
        var pushes = 0
        s.onLocalChange { pushes += 1 }
        s.updateSettings { $0.tmdbApiKey = "" }
        XCTAssertNil(s.settings.updatedAt)
        XCTAssertEqual(pushes, 0)
        s.updateSettings { $0.tmdbApiKey = "key" }
        XCTAssertNotNil(s.settings.updatedAt)
        XCTAssertEqual(pushes, 1)
    }

    func testPlaybackRoundTripsAndMarkingWatchedClearsIt() throws {
        let s = store()
        let id = try XCTUnwrap(s.createItem(Item(title: "A", type: .movie))).id
        s.updateItem(id) { $0.playback = Playback(url: "https://example.com/v", position: 1234.4, duration: 6000) }
        let saved = try XCTUnwrap(s.item(id)?.playback)
        XCTAssertEqual(saved.url, "https://example.com/v")
        XCTAssertEqual(saved.position, 1234)
        XCTAssertEqual(saved.fraction, 1234.0 / 6000, accuracy: 0.001)
        s.markWatched(id)
        XCTAssertNil(s.item(id)?.playback)
    }

    func testMarkEpisodeWatchedAdvancesThroughSeasons() throws {
        let s = store()
        var show = Item(title: "S", type: .show)
        show.seasonProgress = [SeasonProgress(seasonNumber: 1, name: "S1", episodeCount: 1, watched: 0),
                               SeasonProgress(seasonNumber: 2, name: "S2", episodeCount: 2, watched: 0)]
        let id = try XCTUnwrap(s.createItem(show)).id
        s.updateItem(id) { $0.playback = Playback(url: "https://example.com/e1", position: 900, duration: 1000) }
        s.markEpisodeWatched(id)
        XCTAssertEqual(s.item(id)?.seasonProgress?.map(\.watched), [1, 0])
        XCTAssertEqual(s.item(id)?.status, .watching)
        XCTAssertNil(s.item(id)?.playback)
        s.markEpisodeWatched(id)
        s.markEpisodeWatched(id)
        XCTAssertEqual(s.item(id)?.seasonProgress?.map(\.watched), [1, 2])
        XCTAssertEqual(s.item(id)?.status, .completed)
    }
}
