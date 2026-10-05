import WatchlistPluginKit
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

    // MARK: Resetting progress

    private func watched(_ item: Item?) -> [Int]? { item?.seasonProgress?.map(\.watched) }

    private func watchedShow(_ store: WatchlistStore) throws -> String {
        var show = Item(title: "S", type: .show)
        show.seasonProgress = [SeasonProgress(seasonNumber: 1, name: "S1", episodeCount: 2, watched: 2),
                               SeasonProgress(seasonNumber: 2, name: "S2", episodeCount: 3, watched: 1)]
        show.status = .watching
        let id = try XCTUnwrap(store.createItem(show)).id
        store.updateItem(id) {
            $0.playback = Playback(url: "https://example.com/s2e2", position: 600, duration: 1500)
            $0.lastPage = "https://example.com/s2e2"
            $0.set("lastWatchedAt", "2026-10-01T10:00:00.000Z")
        }
        return id
    }

    func testResettingAMoviesProgressForgetsTheTimeAndTheJumpBackInSpot() throws {
        let s = store()
        let id = try XCTUnwrap(s.createItem(Item(title: "A", type: .movie))).id
        s.updateItem(id) {
            $0.playback = Playback(url: "https://example.com/m", position: 600, duration: 6000)
            $0.lastPage = "https://example.com/m"
            $0.set("lastWatchedAt", "2026-10-01T10:00:00.000Z")
            $0.status = .watching
        }
        XCTAssertTrue(s.item(id)?.hasProgress == true)
        s.resetProgress(id, .current)
        let item = try XCTUnwrap(s.item(id))
        XCTAssertNil(item.playback)
        XCTAssertNil(item.lastPage)
        XCTAssertNil(item.lastWatchedAt)
        XCTAssertFalse(item.hasProgress)
        XCTAssertEqual(item.status, .watching, "only the time is reset")
        XCTAssertNil(item.pluginTitle.lastWatchedAt, "no longer offered in Jump back in")
        XCTAssertNil(item.pluginTitle.resumeHost)
    }

    func testResettingTheCurrentEpisodeKeepsWatchedEpisodes() throws {
        let s = store()
        let id = try watchedShow(s)
        s.resetProgress(id, .current)
        XCTAssertNil(s.item(id)?.playback)
        XCTAssertNil(s.item(id)?.lastWatchedAt)
        XCTAssertEqual(watched(s.item(id)), [2, 1])
        XCTAssertEqual(s.item(id)?.status, .watching)
    }

    func testResettingTheSeasonUnwatchesOnlyTheSeasonBeingWatched() throws {
        let s = store()
        let id = try watchedShow(s)
        s.resetProgress(id, .season)
        XCTAssertEqual(watched(s.item(id)), [2, 0], "season 2 is the one in progress")
        XCTAssertEqual(s.item(id)?.status, .watching)
        XCTAssertNil(s.item(id)?.lastPage)
    }

    func testResettingAFinishedShowsSeasonResetsItsLastSeasonAndReopensIt() throws {
        let s = store()
        let id = try watchedShow(s)
        s.updateItem(id) { $0.seasonProgress = $0.seasonProgress?.map { var x = $0; x.watched = x.episodeCount; return x } }
        XCTAssertEqual(s.item(id)?.status, .watching)
        s.markWatched(id)
        s.resetProgress(id, .season)
        XCTAssertEqual(watched(s.item(id)), [2, 0])
        XCTAssertEqual(s.item(id)?.status, .watching)
        XCTAssertNil(s.item(id)?.completedAt)
    }

    func testResettingTheWholeShowStartsItOver() throws {
        let s = store()
        let id = try watchedShow(s)
        s.resetProgress(id, .show)
        XCTAssertEqual(watched(s.item(id)), [0, 0])
        XCTAssertEqual(s.item(id)?.status, .planned)
        XCTAssertFalse(s.item(id)?.hasProgress == true)
    }

    func testResettingAnUntrackedShowCanStillStartItOver() throws {
        let s = store()
        let id = try XCTUnwrap(s.createItem(Item(title: "U", type: .show))).id
        s.updateItem(id) {
            $0.status = .watching
            $0.playback = Playback(url: "https://example.com/e", position: 60, duration: 1500)
        }
        s.resetProgress(id, .season)
        XCTAssertEqual(s.item(id)?.status, .watching, "no seasons to reset")
        XCTAssertNil(s.item(id)?.playback)
        s.resetProgress(id, .show)
        XCTAssertEqual(s.item(id)?.status, .planned)
    }

    func testResetActionsFitTheTitle() throws {
        let s = store()
        let showID = try watchedShow(s)
        XCTAssertEqual(s.item(showID)?.resetActions.map(\.id), ["current", "season", "show"])
        XCTAssertEqual(s.item(showID)?.resetActions.map(\.isDestructive), [false, true, true])
        let movieID = try XCTUnwrap(s.createItem(Item(title: "M", type: .movie))).id
        XCTAssertEqual(s.item(movieID)?.resetActions.count, 0, "nothing to reset")
        s.updateItem(movieID) { $0.playback = Playback(url: "https://example.com/m", position: 60, duration: 6000) }
        XCTAssertEqual(s.item(movieID)?.resetActions.map(\.id), ["current"])
    }
}
