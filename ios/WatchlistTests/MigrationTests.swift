import XCTest
@testable import Watchlist

@MainActor
final class MigrationTests: XCTestCase {
    func testCarriesOverCapacitorStorage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MigrationTests"))
        defaults.removePersistentDomain(forName: "MigrationTests")
        defer { defaults.removePersistentDomain(forName: "MigrationTests"); NucleusSession.clear() }
        NucleusSession.clear()

        let db = #"{"items":[{"_id":"a","title":"Dune","type":"movie","status":"planned","favorite":false,"createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}],"collections":[],"settings":{"tmdbApiKey":"k"},"deleted":{}}"#
        defaults.set(db, forKey: "CapacitorStorage.watchlist-db")
        defaults.set(#"{"accessToken":"at","refreshToken":"nrt_x","expiresAt":1790000000000,"user":{"sub":"u1","handle":"jan","name":"Jan","email":null}}"#, forKey: "CapacitorStorage.watchlist-nucleus-id")
        defaults.set(#"{"version":7,"lastSyncedAt":"2026-09-01T00:00:00.000Z","dirty":true}"#, forKey: "CapacitorStorage.watchlist-sync")
        defaults.set("true", forKey: "CapacitorStorage.watchlist-welcome-seen")
        defaults.set(#"[{"id":"op1","itemId":"a","field":"favorite","value":true,"at":"2026-02-01T00:00:00.000Z"}]"#, forKey: "CapacitorStorage.watch-inbox")

        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let prefs = Preferences(defaults: defaults)
        Migration.run(store: store, preferences: prefs, defaults: defaults)

        XCTAssertEqual(store.item("a")?.title, "Dune")
        XCTAssertEqual(store.item("a")?.favorite, true, "watch inbox applied")
        XCTAssertEqual(store.settings.tmdbApiKey, "k")
        XCTAssertEqual(NucleusSession.load()?.user.handle, "jan")
        XCTAssertEqual(NucleusSession.load()?.expiresAt, 1_790_000_000_000)
        XCTAssertNil(defaults.string(forKey: "CapacitorStorage.watchlist-nucleus-id"), "tokens leave UserDefaults")
        XCTAssertEqual(SyncState.load(defaults), SyncState(version: 7, lastSyncedAt: "2026-09-01T00:00:00.000Z", dirty: true))
        XCTAssertTrue(prefs.hasSeenWelcome)

        // Runs only once.
        store.deleteItem("a")
        Migration.run(store: store, preferences: prefs, defaults: defaults)
        XCTAssertNil(store.item("a"))
    }
}
