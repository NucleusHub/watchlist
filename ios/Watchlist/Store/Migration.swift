import Foundation

/// Carries data over from the Capacitor version of the app, once. Capacitor Preferences kept
/// every value as a JSON string in UserDefaults under "CapacitorStorage.<key>".
@MainActor
enum Migration {
    private static let doneKey = "migratedFromCapacitor"
    private static func key(_ name: String) -> String { "CapacitorStorage.\(name)" }

    static func run(store: WatchlistStore, preferences: Preferences, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        func json(_ name: String) -> JSONValue? {
            guard let raw = defaults.string(forKey: key(name)), let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: data)
        }

        // Only adopt the old database if this install has none of its own yet.
        if !store.hasSavedFile, let db = json("watchlist-db") {
            store.replace(with: WatchlistDocument.normalize(db), silent: true)
            store.flush()
        }

        if let s = json("watchlist-nucleus-id")?.object, NucleusSession.load() == nil,
           let access = s["accessToken"]?.string, let refresh = s["refreshToken"]?.string,
           let user = s["user"]?.object, let sub = user["sub"]?.string {
            let handle = user["handle"]?.string ?? ""
            NucleusSession(
                accessToken: access, refreshToken: refresh, expiresAt: s["expiresAt"]?.double ?? 0,
                user: .init(sub: sub, handle: handle, name: user["name"]?.string ?? handle, email: user["email"]?.string)
            ).save()
        }
        // Tokens don't belong in UserDefaults; the keychain has them now.
        defaults.removeObject(forKey: key("watchlist-nucleus-id"))
        defaults.removeObject(forKey: key("watchlist-nucleus-id-pending"))

        if let s = json("watchlist-sync")?.object {
            SyncState(version: s["version"]?.int, lastSyncedAt: s["lastSyncedAt"]?.string, dirty: s["dirty"]?.bool ?? false).save(defaults)
        }
        if json("watchlist-welcome-seen")?.bool == true { preferences.hasSeenWelcome = true }
        if let shake = json("watchlist-shake-to-report")?.bool { preferences.shakeToReport = shake }

        // Taps from the watch the old app hadn't applied yet.
        if let ops = json("watch-inbox")?.array {
            WatchOps.apply(ops.compactMap(WatchOp.init), to: store)
            defaults.removeObject(forKey: key("watch-inbox"))
        }
        // Plugin installs ("watchlist-plugins", "watchlist-plugin:*") stay for when plugins come to this app.
    }
}

/// One tap on the Apple Watch: favorite or mark watched, with the time it happened.
struct WatchOp {
    enum Field: String { case favorite, completed }

    let id: String
    let itemId: String
    let field: Field
    let value: Bool
    let at: String

    init?(_ json: JSONValue) {
        guard let o = json.object, let id = o["id"]?.string, let itemId = o["itemId"]?.string,
              let field = Field(rawValue: o["field"]?.string ?? ""), let value = o["value"]?.bool,
              let at = o["at"]?.string else { return nil }
        self.id = id
        self.itemId = itemId
        self.field = field
        self.value = value
        self.at = at
    }
}

@MainActor
enum WatchOps {
    /// Oldest first, and an edit made on the phone after the tap wins.
    static func apply(_ ops: [WatchOp], to store: WatchlistStore) {
        for op in ops.sorted(by: { (Timestamp.millis($0.at) ?? 0) < (Timestamp.millis($1.at) ?? 0) }) {
            guard let item = store.item(op.itemId),
                  (Timestamp.millis(op.at) ?? 0) > (Timestamp.millis(item.updatedAt) ?? 0) else { continue }
            switch op.field {
            case .favorite:
                store.updateItem(op.itemId) { $0.favorite = op.value }
            case .completed:
                if op.value { store.markWatched(op.itemId) } else { store.updateItem(op.itemId) { $0.status = .planned } }
            }
        }
    }
}
