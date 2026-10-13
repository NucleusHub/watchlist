import XCTest
@testable import Watchlist

final class WatchlistAPITests: XCTestCase {
    private let a = "aaaaaaaaaaaaaaaaaaaaaaaa", b = "bbbbbbbbbbbbbbbbbbbbbbbb", c = "cccccccccccccccccccccccc"

    private func item(_ id: String, _ title: String, at: String, collections: [String] = []) -> Item {
        var i = Item(title: title, type: .movie)
        i.raw["_id"] = .string(id)
        i.raw["updatedAt"] = .string(at)
        i.collectionIds = collections
        return i
    }

    private func remote(_ id: String, _ title: String, at: String) -> [String: JSONValue] {
        ["_id": .string(id), "title": .string(title), "type": "movie", "updatedAt": .string(at), "collectionIds": []]
    }

    private func doc(_ items: [Item] = [], deleted: [String: String] = [:]) -> WatchlistDocument {
        WatchlistDocument(items: items, deleted: deleted)
    }

    // MARK: Mapping

    func testObjectIdCheck() {
        XCTAssertTrue(IDMap.isObjectId(a))
        XCTAssertTrue(IDMap.isObjectId(RecordID.make()))
        XCTAssertFalse(IDMap.isObjectId("legacy-1"))
        XCTAssertFalse(IDMap.isObjectId(String(a.dropLast())))
    }

    func testLegacyIdGetsAnObjectIdOnceAndMapsBack() {
        var ids = IDMap()
        let sid = ids.assign("1699999999-abc")
        XCTAssertTrue(IDMap.isObjectId(sid))
        XCTAssertEqual(ids.assign("1699999999-abc"), sid)
        XCTAssertEqual(ids.assign(a), a)
        XCTAssertEqual(ids.reverse[sid], "1699999999-abc")
    }

    func testItemBodyRemapsIdsAndOverviewAndDropsUpdatedAt() {
        var ids = IDMap()
        var i = item("old-1", "Heat", at: "2026-01-01T00:00:00.000Z", collections: ["old-col", b])
        i.raw["overview"] = .string("")
        let body = WatchlistAPI.body(i, ids: &ids, includeID: true).object!
        XCTAssertEqual(body["_id"]?.string, ids.toServer["old-1"])
        XCTAssertEqual(body["collectionIds"]?.array?.compactMap(\.string), [ids.toServer["old-col"]!, b])
        XCTAssertEqual(body["overview"], .null)
        XCTAssertNil(body["updatedAt"])
        XCTAssertNil(WatchlistAPI.body(i, ids: &ids, includeID: false).object?["_id"])
    }

    func testCollectionBodyKeepsOnlyWritableFields() {
        var ids = IDMap()
        var col = Watchlist.WatchCollection(name: "Noir")
        col.raw["_id"] = .string("legacy")
        col.details = "Dark"
        let body = WatchlistAPI.body(col, ids: &ids).object!
        XCTAssertEqual(Set(body.keys), ["name", "description", "coverUrl", "coverItemIds", "coverCount"])
        XCTAssertEqual(body["description"]?.string, "Dark")
    }

    func testServerRecordsMapBackToLocalIds() {
        let reverse = [a: "legacy"]
        let i = WatchlistAPI.item(from: ["_id": .string(a), "title": "X", "__v": 0, "collectionIds": [.string(a), .string(b)]], reverse: reverse)
        XCTAssertEqual(i.id, "legacy")
        XCTAssertEqual(i.collectionIds, ["legacy", b])
        XCTAssertNil(i.raw["__v"])
        let col = WatchlistAPI.collection(from: ["_id": .string(b), "name": "N", "itemCount": 3, "previewPosters": [], "itemOrder": [.string(a)]], reverse: reverse)
        XCTAssertEqual(col.id, b)
        XCTAssertEqual(col.itemOrder, ["legacy"])
        XCTAssertNil(col.raw["itemCount"])
    }

    func testSettingsBodyIsNormalisedLikeTheServer() {
        let raw: [String: JSONValue] = ["searchSources": ["kitsu", "tmdb", "kitsu"], "pluginPlacements": ["x": "tab", "y": "bogus"], "tmdbApiKey": " k "]
        let body = WatchlistAPI.settingsBody(raw)
        XCTAssertEqual(body["searchSources"]?.array?.compactMap(\.string), ["tmdb", "kitsu"])
        XCTAssertEqual(body["pluginPlacements"]?.object?.keys.sorted(), ["x"])
        XCTAssertEqual(body["tmdbApiKey"]?.string, "k")
        XCTAssertNil(body["movie"])
        XCTAssertEqual(WatchlistAPI.settingsHash(raw), WatchlistAPI.settingsHash(body))
    }

    // MARK: Plan: ids and deletions

    func testLocalOnlyRecordsAreCreatedNeverRemoved() {
        var book = SyncBook()
        book.synced[b] = "t"   // some other synced record; this one never was
        let plan = WatchlistAPI.plan(local: doc([item(a, "New", at: "2026-02-01T00:00:00.000Z")]), server: ServerSnapshot(), book: book)
        XCTAssertEqual(plan.items.create.map(\.id), [a])
        XCTAssertTrue(plan.items.remove.isEmpty)
    }

    func testSyncedRecordMissingOnServerIsRemovedLocally() {
        var book = SyncBook()
        book.synced[a] = "2026-01-01T00:00:00.000Z"
        let plan = WatchlistAPI.plan(local: doc([item(a, "Gone", at: "2026-01-01T00:00:00.000Z")]), server: ServerSnapshot(), book: book)
        XCTAssertEqual(plan.items.remove.map(\.sid), [a])
        XCTAssertTrue(plan.items.create.isEmpty)
    }

    func testSyncedRecordEditedLocallyIsKeptWhenServerDeletedIt() {
        var book = SyncBook()
        book.synced[a] = "2026-01-01T00:00:00.000Z"
        let plan = WatchlistAPI.plan(local: doc([item(a, "Edited", at: "2026-03-01T00:00:00.000Z")]), server: ServerSnapshot(), book: book)
        XCTAssertEqual(plan.items.create.map(\.id), [a])
        XCTAssertTrue(plan.items.remove.isEmpty)
    }

    func testLegacyIdUsesTheMapWhenMatching() {
        var book = SyncBook()
        book.ids.toServer["legacy"] = b
        book.synced[b] = "2026-01-01T00:00:00.000Z"
        let server = ServerSnapshot(items: [remote(b, "T", at: "2026-01-01T00:00:00.000Z")])
        let plan = WatchlistAPI.plan(local: doc([item("legacy", "T", at: "2026-01-02T00:00:00.000Z")]), server: server, book: book)
        XCTAssertEqual(plan.items.update.map(\.id), ["legacy"])
        XCTAssertTrue(plan.items.pull.isEmpty && plan.items.create.isEmpty)
    }

    func testTombstoneDeletesOnServerOnlyWhenNotEditedAfter() {
        let server = ServerSnapshot(items: [remote(a, "Old", at: "2026-01-01T00:00:00.000Z"), remote(b, "Edited on web", at: "2026-05-01T00:00:00.000Z")])
        let deleted = [a: "2026-02-01T00:00:00.000Z", b: "2026-02-01T00:00:00.000Z"]
        let plan = WatchlistAPI.plan(local: doc(deleted: deleted), server: server, book: SyncBook())
        XCTAssertEqual(plan.items.delete, [a])
        XCTAssertEqual(plan.items.pull.compactMap { $0.raw["_id"]?.string }, [b])
    }

    func testTombstonesAreIgnoredWhenNotAllowed() {
        let server = ServerSnapshot(items: [remote(a, "Old", at: "2026-01-01T00:00:00.000Z")])
        let plan = WatchlistAPI.plan(local: doc(deleted: [a: "2026-02-01T00:00:00.000Z"]), server: server, book: SyncBook(), deleteAllowed: [])
        XCTAssertTrue(plan.items.delete.isEmpty)
        XCTAssertEqual(plan.items.pull.count, 1)
    }

    func testServerOnlyRecordIsPulledAndSkippedOnesAreNot() {
        var book = SyncBook()
        book.skipped = [b]
        let server = ServerSnapshot(items: [remote(a, "A", at: "t"), remote(b, "B", at: "t")])
        let plan = WatchlistAPI.plan(local: doc(), server: server, book: book)
        XCTAssertEqual(plan.items.pull.compactMap { $0.raw["_id"]?.string }, [a])
    }

    // MARK: Plan: conflicts and the first-sign-in modes

    func testNewestUpdatedAtWinsOnMerge() {
        let server = ServerSnapshot(items: [remote(a, "A", at: "2026-02-01T00:00:00.000Z"), remote(b, "B", at: "2026-01-01T00:00:00.000Z")])
        let local = doc([item(a, "A", at: "2026-01-01T00:00:00.000Z"), item(b, "B", at: "2026-02-01T00:00:00.000Z"), item(c, "Only here", at: "2026-01-01T00:00:00.000Z")])
        let plan = WatchlistAPI.plan(local: local, server: server, book: SyncBook(), deleteAllowed: [])
        XCTAssertEqual(plan.items.pull.compactMap { $0.raw["_id"]?.string }, [a])
        XCTAssertEqual(plan.items.update.map(\.id), [b])
        XCTAssertEqual(plan.items.create.map(\.id), [c])
        XCTAssertTrue(plan.items.delete.isEmpty)
    }

    func testKeepDeviceDeletesServerOnlyRecordsAndOverwritesTheRest() {
        let server = ServerSnapshot(items: [remote(a, "A", at: "2026-09-01T00:00:00.000Z"), remote(b, "Web only", at: "t")])
        let plan = WatchlistAPI.plan(local: doc([item(a, "A", at: "2026-01-01T00:00:00.000Z")]), server: server, book: SyncBook(), mode: .keepDevice)
        XCTAssertEqual(plan.items.update.map(\.id), [a])
        XCTAssertEqual(plan.items.delete, [b])
        XCTAssertTrue(plan.items.pull.isEmpty)
        let choice = FirstSyncChoice(local: doc([item(a, "A", at: "x")]), server: server, ids: IDMap())
        XCTAssertEqual(choice.deletions.items, 1)
        XCTAssertEqual(choice.deletions.collections, 0)
    }

    func testPickRowsListDifferencesOnly() {
        let server = ServerSnapshot(items: [remote(a, "Same", at: "t"), remote(b, "Web only", at: "t")])
        let rows = WatchlistAPI.pickRows(local: doc([item(a, "Same", at: "t"), item(c, "Here only", at: "t")]), server: server, ids: IDMap())
        XCTAssertEqual(Set(rows.map(\.id)), [b, c])
        XCTAssertEqual(rows.first { $0.id == b }?.side, .web)
        XCTAssertEqual(rows.first { $0.id == c }?.side, .device)
    }

    func testSettingsStep() {
        var local = doc()
        var server = ServerSnapshot()
        XCTAssertEqual(WatchlistAPI.plan(local: local, server: server, book: SyncBook()).settings, .none)
        server.settings = ["tmdbApiKey": "web"]
        XCTAssertEqual(WatchlistAPI.plan(local: local, server: server, book: SyncBook()).settings, .pull)
        local.settings.tmdbApiKey = "phone"
        XCTAssertEqual(WatchlistAPI.plan(local: local, server: server, book: SyncBook()).settings, .push)
        var book = SyncBook()
        book.settingsHash = WatchlistAPI.settingsHash(local.settings.raw)
        XCTAssertEqual(WatchlistAPI.plan(local: local, server: server, book: book).settings, .pull)
    }

    // MARK: Applying

    func testPullsSkipRecordsEditedMeanwhile() {
        var items = [item(a, "A", at: "2026-03-01T00:00:00.000Z")]
        let stale = Pull(raw: remote(a, "Web", at: "2026-02-01T00:00:00.000Z"), localID: a, expected: "2026-01-01T00:00:00.000Z")
        let fresh = Pull(raw: remote(b, "New", at: "t"), localID: nil, expected: nil)
        let result = WatchlistAPI.apply([stale, fresh], [], to: &items) { WatchlistAPI.item(from: $0, reverse: [:]) }
        XCTAssertEqual(items.map(\.id), [a, b])
        XCTAssertEqual(items[0].title, "A")
        XCTAssertEqual(Set(result.pulled.keys), [b])
    }

    func testBackupFileIsWritten() throws {
        let url = try Backup.save(doc([item(a, "A", at: "t")]), label: "test")
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try Backup.read(Data(contentsOf: url))
        XCTAssertEqual(read.document.items.map(\.id), [a])
    }
}
