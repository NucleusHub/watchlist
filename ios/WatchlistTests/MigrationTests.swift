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

    func testReinstallDropsTheLeftoverSignIn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ReinstallTests"))
        defaults.removePersistentDomain(forName: "ReinstallTests")
        defer { defaults.removePersistentDomain(forName: "ReinstallTests"); NucleusSession.clear() }
        let store = WatchlistStore(fileURL: nil, document: WatchlistDocument())
        let session = NucleusSession(accessToken: "at", refreshToken: "rt", expiresAt: 0, user: .init(sub: "u1", handle: "ema", name: "Ema", email: nil))

        // A fresh install with a sign-in only in the keychain: a deleted copy left it.
        session.save()
        Migration.dropLeftoverSession(store: store, defaults: defaults)
        XCTAssertNil(NucleusSession.load())

        // The app ran here before: an update keeps the sign-in.
        Migration.run(store: store, preferences: Preferences(defaults: defaults), defaults: defaults)
        session.save()
        Migration.dropLeftoverSession(store: store, defaults: defaults)
        XCTAssertEqual(NucleusSession.load()?.user.handle, "ema")

        // So does coming from the Capacitor app, which hasn't run the migration yet.
        defaults.removePersistentDomain(forName: "ReinstallTests")
        defaults.set("{}", forKey: "CapacitorStorage.watchlist-sync")
        Migration.dropLeftoverSession(store: store, defaults: defaults)
        XCTAssertNotNil(NucleusSession.load())
    }
}
