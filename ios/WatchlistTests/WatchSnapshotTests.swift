import XCTest
@testable import Watchlist

/// The phone's snapshot must decode with the watch app's own types (WatchlistWatch/Model.swift).
@MainActor
final class WatchSnapshotTests: XCTestCase {
    func testWatchReadsPhoneSnapshot() throws {
        var doc = SampleData.document
        doc.items[0].set("year", "2024")
        doc.items[1].posterUrl = "data:image/jpeg;base64,AAAA"
        let store = WatchlistStore(fileURL: nil, document: doc)
        let data = try XCTUnwrap(PhoneWatchBridge(store: store).snapshot())
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        XCTAssertEqual(snapshot.items.count, doc.items.count)
        XCTAssertEqual(snapshot.collections.first?.name, "Weekend picks")
        let dune = try XCTUnwrap(snapshot.items.first { $0.title == "Dune: Part Two" })
        XCTAssertEqual(dune.year, 2024, "string years still arrive as numbers")
        XCTAssertTrue(dune.posterUrl?.contains("/w185/") == true, "posters shrink for the watch")
        XCTAssertNil(snapshot.items.first { $0.title == "Severance" }?.posterUrl, "inlined images stay on the phone")
    }

    func testWatchOpsApplyLikeTheWeb() throws {
        let store = WatchlistStore(fileURL: nil, document: SampleData.document)
        let id = try XCTUnwrap(store.items.first { !$0.isCompleted && !$0.favorite }).id
        let later = Timestamp.string(Date().addingTimeInterval(60))
        let earlier = "2000-01-01T00:00:00.000Z"
        WatchOps.apply([
            Watchlist.WatchOp(JSONValue.object(["id": "1", "itemId": .string(id), "field": "completed", "value": true, "at": .string(later)]))!,
            Watchlist.WatchOp(JSONValue.object(["id": "2", "itemId": .string(id), "field": "favorite", "value": true, "at": .string(earlier)]))!,
        ], to: store)
        XCTAssertEqual(store.item(id)?.status, .completed)
        XCTAssertNotEqual(store.item(id)?.favorite, true, "a tap older than the phone's last edit loses")
    }
}
