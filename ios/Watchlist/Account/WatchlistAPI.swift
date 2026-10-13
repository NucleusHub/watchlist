import Foundation

/// Local ids -> server ObjectIds. Ids that already are ObjectIds map to themselves; older ones get a
/// generated id the first time a record goes up. Local records keep their ids, so nothing is renamed or dropped.
struct IDMap: Codable, Equatable {
    var toServer: [String: String] = [:]

    static func isObjectId(_ id: String) -> Bool {
        id.utf8.count == 24 && id.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70) }
    }

    func server(_ local: String) -> String? { toServer[local] ?? (Self.isObjectId(local) ? local : nil) }

    mutating func assign(_ local: String) -> String {
        if let known = server(local) { return known }
        let id = RecordID.make()
        toServer[local] = id
        return id
    }

    /// The server answered with another id than the one sent (collections always get their own).
    mutating func adopt(local: String, server: String) {
        if local != server { toServer[local] = server }
    }

    var reverse: [String: String] { Dictionary(toServer.map { ($1, $0) }, uniquingKeysWith: { first, _ in first }) }
}

/// What the device remembers about the server copy: ids, the last `updatedAt` both sides agreed on
/// (so "gone from the server" only counts for records that were synced), and records left out on purpose.
struct SyncBook: Codable, Equatable {
    var initialized = false
    var ids = IDMap()
    var synced: [String: String] = [:]
    var skipped: Set<String> = []
    var settingsHash: String?

    private static let key = "syncBook"

    static func load(_ defaults: UserDefaults = .standard) -> SyncBook {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SyncBook.self, from: $0) } ?? SyncBook()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

struct ServerSnapshot {
    var items: [[String: JSONValue]] = []
    var collections: [[String: JSONValue]] = []
    var settings: [String: JSONValue] = [:]

    var isEmpty: Bool { items.isEmpty && collections.isEmpty }

    var syncedStamps: [String: String] {
        var out: [String: String] = [:]
        for r in items + collections { if let id = r["_id"]?.string { out[id] = r["updatedAt"]?.string ?? "" } }
        return out
    }
}

/// A server record to take locally. `localID` nil: not on the device yet. `expected`: the local
/// `updatedAt` it was planned against, so an edit made meanwhile isn't overwritten.
struct Pull: Equatable {
    var raw: [String: JSONValue]
    var localID: String?
    var expected: String?
}

struct Removal: Equatable {
    var localID: String
    var sid: String
    var expected: String?
}

struct RecordPlan<R: JSONRecord> {
    var create: [R] = []
    var update: [R] = []
    var delete: [String] = []
    var pull: [Pull] = []
    var remove: [Removal] = []
    var inSync: [String: String] = [:]
}

enum SettingsStep: Equatable { case none, push, pull }

struct SyncPlan {
    var items = RecordPlan<Item>()
    var collections = RecordPlan<WatchCollection>()
    var settings = SettingsStep.none
}

enum PlanMode: Equatable {
    case normal
    /// The device wins everywhere; whatever the server has that the device doesn't is deleted.
    case keepDevice
}

/// Maps records to and from the Watchlist REST API (docs/ios-api.md) and decides what to send.
enum WatchlistAPI {
    // MARK: Records

    static func body(_ item: Item, ids: inout IDMap, includeID: Bool) -> JSONValue {
        var o = item.raw
        o.removeValue(forKey: "updatedAt")
        if includeID { o["_id"] = .string(ids.assign(item.id)) } else { o.removeValue(forKey: "_id") }
        o["collectionIds"] = .array(item.collectionIds.map { .string(ids.assign($0)) })
        if o["overview"]?.string?.isEmpty == true { o["overview"] = .null }
        return .object(o)
    }

    /// Only what the collection routes accept; order goes through its own call.
    static func body(_ c: WatchCollection, ids: inout IDMap) -> JSONValue {
        .object([
            "name": .string(c.name), "description": .string(c.details), "coverUrl": JSONValue(c.coverUrl),
            "coverItemIds": .array(c.coverItemIds.map { .string(ids.assign($0)) }), "coverCount": JSONValue(c.coverCount),
        ])
    }

    static func order(of c: WatchCollection, ids: inout IDMap) -> [String] { c.itemOrder.map { ids.assign($0) } }

    static func item(from server: [String: JSONValue], reverse: [String: String]) -> Item {
        var o = server
        for key in ["__v", "profileId"] { o.removeValue(forKey: key) }
        o["_id"] = .string(local(server["_id"]?.string ?? "", reverse))
        if let refs = server["collectionIds"]?.array { o["collectionIds"] = .array(refs.compactMap(\.string).map { .string(local($0, reverse)) }) }
        return Item(raw: o)
    }

    static func collection(from server: [String: JSONValue], reverse: [String: String]) -> WatchCollection {
        var o = server
        for key in ["__v", "profileId", "itemCount", "previewPosters", "coverPosters"] { o.removeValue(forKey: key) }
        o["_id"] = .string(local(server["_id"]?.string ?? "", reverse))
        for key in ["coverItemIds", "itemOrder"] {
            if let refs = server[key]?.array { o[key] = .array(refs.compactMap(\.string).map { .string(local($0, reverse)) }) }
        }
        if let parent = server["parentId"]?.string { o["parentId"] = .string(local(parent, reverse)) }
        return WatchCollection(raw: o)
    }

    private static func local(_ sid: String, _ reverse: [String: String]) -> String { reverse[sid] ?? sid }

    // MARK: Settings

    private static func target(_ v: JSONValue?) -> JSONValue {
        let o = v?.object
        func text(_ key: String, _ fallback: String) -> JSONValue {
            .string(o?[key]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
        }
        return .object(["type": text("type", "tmdb"), "customUrl": .string(o?["customUrl"]?.string ?? ""), "titleFormat": text("titleFormat", "raw")])
    }

    /// The PUT /settings body, in the shape the server stores, so a local and a server copy compare equal.
    static func settingsBody(_ raw: [String: JSONValue]) -> [String: JSONValue] {
        var o: [String: JSONValue] = [:]
        if let d = raw["openDefaults"]?.object {
            o["movie"] = target(d["movie"])
            o["show"] = target(d["show"])
        }
        var seen = Set<String>(["tmdb"])
        let extra = (raw["searchSources"]?.array?.compactMap(\.string) ?? []).filter { !$0.isEmpty && seen.insert($0).inserted }
        o["searchSources"] = .array((["tmdb"] + extra).map(JSONValue.string))
        o["pluginPlacements"] = .object((raw["pluginPlacements"]?.object ?? [:]).filter { ["tab", "panel", "hidden"].contains($0.value.string ?? "") })
        o["tmdbApiKey"] = .string((raw["tmdbApiKey"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        if let a = raw["accent"]?.object, let id = a["id"]?.string, !id.isEmpty {
            o["accent"] = .object(["id": .string(id), "custom": JSONValue(a["custom"]?.string), "updatedAt": a["updatedAt"] ?? .null])
        }
        return o
    }

    /// Compares settings ignoring the accent's own stamp.
    static func settingsHash(_ raw: [String: JSONValue]) -> String {
        var o = settingsBody(raw)
        if var a = o["accent"]?.object { a.removeValue(forKey: "updatedAt"); o["accent"] = .object(a) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(JSONValue.object(o))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func settings(applying server: [String: JSONValue], to local: WatchlistSettings) -> WatchlistSettings {
        var s = local
        if let d = server["openDefaults"]?.object {
            s.raw["openDefaults"] = .object(d.filter { $0.key == "movie" || $0.key == "show" })
        }
        for key in ["searchSources", "pluginPlacements", "tmdbApiKey"] { if let v = server[key] { s.raw[key] = v } }
        if let a = server["accent"], a.object != nil { s.raw["accent"] = a }
        return s
    }

    // MARK: Planning

    /// `deleteAllowed`: server ids a device-side deletion may remove; nil means every tombstone counts.
    static func plan(local: WatchlistDocument, server: ServerSnapshot, book: SyncBook,
                     mode: PlanMode = .normal, deleteAllowed: Set<String>? = nil) -> SyncPlan {
        var plan = SyncPlan()
        plan.items = recordPlan(local.items, server.items, deleted: local.deleted, book: book, mode: mode, deleteAllowed: deleteAllowed)
        plan.collections = recordPlan(local.collections, server.collections, deleted: local.deleted, book: book, mode: mode, deleteAllowed: deleteAllowed)
        let l = settingsHash(local.settings.raw), s = settingsHash(server.settings)
        if l == s {
            plan.settings = .none
        } else if mode == .keepDevice {
            plan.settings = .push
        } else if let base = book.settingsHash {
            plan.settings = l != base ? .push : .pull
        } else {
            plan.settings = l == settingsHash(WatchlistSettings.empty.raw) ? .pull : .push
        }
        return plan
    }

    private static func recordPlan<R: JSONRecord>(_ local: [R], _ server: [[String: JSONValue]], deleted: [String: String],
                                                  book: SyncBook, mode: PlanMode, deleteAllowed: Set<String>?) -> RecordPlan<R> {
        var plan = RecordPlan<R>()
        let reverse = book.ids.reverse
        var bySid: [String: [String: JSONValue]] = [:]
        for s in server { if let id = s["_id"]?.string, bySid[id] == nil { bySid[id] = s } }
        var seen = Set<String>()
        for r in local {
            let sid = book.ids.server(r.id)
            let stamp = r.updatedAt
            if book.skipped.contains(sid ?? r.id) {
                if let sid { seen.insert(sid) }
                continue
            }
            guard let sid, let s = bySid[sid] else {
                // Missing on the server: deleted there only if it was synced and not edited since; never a local-only record.
                if let sid, mode == .normal, let base = book.synced[sid], base == (stamp ?? "") {
                    plan.remove.append(Removal(localID: r.id, sid: sid, expected: stamp))
                } else {
                    plan.create.append(r)
                }
                continue
            }
            seen.insert(sid)
            let lu = stamp ?? "", su = s["updatedAt"]?.string ?? ""
            if lu == su { plan.inSync[sid] = su; continue }
            if mode == .keepDevice { plan.update.append(r); continue }
            let base = book.synced[sid]
            let localChanged = lu != base, serverChanged = su != base
            let pushIt = localChanged && (!serverChanged || WatchlistDocument.stamp(r.raw) > WatchlistDocument.stamp(s))
            if pushIt { plan.update.append(r) } else { plan.pull.append(Pull(raw: s, localID: r.id, expected: stamp)) }
        }
        for s in server {
            guard let sid = s["_id"]?.string, !seen.contains(sid), !book.skipped.contains(sid) else { continue }
            seen.insert(sid)
            if mode == .keepDevice { plan.delete.append(sid); continue }
            let tombstone = deleted[reverse[sid] ?? sid] ?? deleted[sid]
            if let tombstone, deleteAllowed?.contains(sid) ?? true, WatchlistDocument.stamp(s) <= (Timestamp.millis(tombstone) ?? 0) {
                plan.delete.append(sid)
            } else {
                plan.pull.append(Pull(raw: s, localID: nil, expected: nil))
            }
        }
        return plan
    }

    // MARK: Applying

    /// Takes the pulls and removals into `list`, skipping any record edited since it was planned.
    /// Returns the server ids that were applied, with the stamp now shared.
    static func apply<R: JSONRecord>(_ pulls: [Pull], _ removals: [Removal], to list: inout [R],
                                     make: ([String: JSONValue]) -> R) -> (pulled: [String: String], removed: [String]) {
        var pulled: [String: String] = [:]
        var removed: [String] = []
        for p in pulls {
            let record = make(p.raw)
            if let lid = p.localID {
                guard let i = list.firstIndex(where: { $0.id == lid }), list[i].updatedAt == p.expected else { continue }
                list[i] = record
            } else {
                guard !list.contains(where: { $0.id == record.id }) else { continue }
                list.append(record)
            }
            pulled[p.raw["_id"]?.string ?? ""] = p.raw["updatedAt"]?.string ?? ""
        }
        for r in removals {
            guard let i = list.firstIndex(where: { $0.id == r.localID }), list[i].updatedAt == r.expected else { continue }
            list.remove(at: i)
            removed.append(r.sid)
        }
        return (pulled, removed)
    }

    /// After a write, the local copy takes the server's `updatedAt` (and `completedAt`, which it derives), if untouched meanwhile.
    static func stamp<R: JSONRecord>(_ list: inout [R], localID: String, expected: String?, updatedAt: String, completedAt: JSONValue?) {
        guard let i = list.firstIndex(where: { $0.id == localID }), list[i].updatedAt == expected else { return }
        list[i].raw["updatedAt"] = .string(updatedAt)
        if let completedAt { list[i].raw["completedAt"] = completedAt }
    }

    // MARK: First sign-in rows

    struct PickRow: Identifiable, Equatable {
        enum Side: Equatable { case device, web, both, deletedOnDevice }
        let id: String
        let isCollection: Bool
        let title: String
        let side: Side
    }

    /// Every record that differs between the device and the server, for cherry-picking.
    /// `id` is the key kept in `SyncBook.skipped` when the row is left unchecked.
    static func pickRows(local: WatchlistDocument, server: ServerSnapshot, ids: IDMap) -> [PickRow] {
        var book = SyncBook()
        book.ids = ids
        let p = plan(local: local, server: server, book: book)
        var rows: [PickRow] = []
        func add<R: JSONRecord>(_ plan: RecordPlan<R>, collection: Bool, title: (R) -> String, serverTitle: ([String: JSONValue]) -> String) {
            rows += plan.create.map { PickRow(id: ids.server($0.id) ?? $0.id, isCollection: collection, title: title($0), side: .device) }
            rows += plan.update.map { PickRow(id: ids.server($0.id) ?? $0.id, isCollection: collection, title: title($0), side: .both) }
            for pull in plan.pull {
                let sid = pull.raw["_id"]?.string ?? ""
                rows.append(PickRow(id: sid, isCollection: collection, title: serverTitle(pull.raw), side: pull.localID == nil ? .web : .both))
            }
        }
        add(p.items, collection: false, title: \.title, serverTitle: { $0["title"]?.string ?? "" })
        add(p.collections, collection: true, title: \.name, serverTitle: { $0["name"]?.string ?? "" })
        let byID = Dictionary((server.items + server.collections).compactMap { r in r["_id"]?.string.map { ($0, r["title"]?.string ?? r["name"]?.string ?? "") } },
                              uniquingKeysWith: { first, _ in first })
        for (collection, deletes) in [(false, p.items.delete), (true, p.collections.delete)] {
            rows += deletes.map { PickRow(id: $0, isCollection: collection, title: byID[$0] ?? "", side: .deletedOnDevice) }
        }
        return rows
    }
}
