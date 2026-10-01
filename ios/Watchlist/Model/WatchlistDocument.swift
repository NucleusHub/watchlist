import Foundation

/// Everything in one document: what's kept on the device, exported to a file and synced to
/// Nucleus ID. Deletions leave a tombstone in
/// `deleted`, so two copies merge without bringing back what one side removed.
struct WatchlistDocument: Codable, Hashable {
    static let format = "nucleus-watchlist"
    static let formatVersion = 1
    static let tombstoneTTL: TimeInterval = 180 * 24 * 3600

    var items: [Item] = []
    var collections: [WatchCollection] = []
    var settings: WatchlistSettings = .empty
    var deleted: [String: String] = [:]

    var isEmpty: Bool { items.isEmpty && collections.isEmpty }

    init(items: [Item] = [], collections: [WatchCollection] = [], settings: WatchlistSettings = .empty, deleted: [String: String] = [:]) {
        self.items = items
        self.collections = collections
        self.settings = settings
        self.deleted = deleted
    }

    init(from decoder: Decoder) throws {
        self = Self.normalize(try JSONValue(from: decoder))
    }

    func encode(to encoder: Encoder) throws { try json.encode(to: encoder) }

    var json: JSONValue {
        .object([
            "items": .array(items.map { .object($0.raw) }),
            "collections": .array(collections.map { .object($0.raw) }),
            "settings": .object(settings.raw),
            "deleted": .object(deleted.mapValues(JSONValue.string)),
        ])
    }

    /// `normalizeDoc`: drops records without an id or a title/name and fills missing settings.
    static func normalize(_ raw: JSONValue?) -> WatchlistDocument {
        var out = WatchlistDocument()
        guard let o = raw?.object else { return out }
        if let items = o["items"]?.array {
            out.items = items.compactMap { v in
                guard let r = v.object, r["_id"]?.isTruthy == true, r["title"]?.isTruthy == true else { return nil }
                return Item(raw: r)
            }
        }
        if let cols = o["collections"]?.array {
            out.collections = cols.compactMap { v in
                guard let r = v.object, r["_id"]?.isTruthy == true, r["name"]?.isTruthy == true else { return nil }
                return WatchCollection(raw: r)
            }
        }
        if let s = o["settings"]?.object {
            out.settings = WatchlistSettings(raw: WatchlistSettings.empty.raw.merging(s) { _, new in new })
        }
        if let d = o["deleted"]?.object {
            out.deleted = d.compactMapValues(\.string)
        }
        return out
    }

    /// The backup file: the document plus format, version and export date.
    func exportJSON(at date: Date = Date()) -> JSONValue {
        guard case .object(var o) = json else { return json }
        o["format"] = .string(Self.format)
        o["version"] = .number(Double(Self.formatVersion))
        o["exportedAt"] = .string(Timestamp.string(date))
        return .object(o)
    }
}

// MARK: - Merge (checked against the original JavaScript in WatchlistTests/Fixtures)

extension WatchlistDocument {
    /// `stamp(r)`: when a record last changed, in milliseconds; 0 if unknown.
    static func stamp(_ raw: [String: JSONValue]?) -> Double {
        guard let raw else { return 0 }
        let updated = raw["updatedAt"].flatMap { $0.isTruthy ? $0.string : nil }
        let created = raw["createdAt"].flatMap { $0.isTruthy ? $0.string : nil }
        return Timestamp.millis(updated ?? created) ?? 0
    }

    private static func mergeRecords<R: JSONRecord>(_ a: [R], _ b: [R], deleted: [String: String]) -> [R] {
        var map: [String: R] = [:]
        var order: [String] = []
        for r in a + b {
            if let prev = map[r.id] {
                // Strictly newer only, so on a tie the first copy (this device's) stays.
                if stamp(r.raw) > stamp(prev.raw) { map[r.id] = r }
            } else {
                map[r.id] = r
                order.append(r.id)
            }
        }
        // An edit made after the delete wins; anything older stays deleted.
        return order.compactMap { map[$0] }.filter { r in
            guard let at = deleted[r.id] else { return true }
            guard let ms = Timestamp.millis(at) else { return false }
            return ms < stamp(r.raw)
        }
    }

    /// Union of two documents, newest record wins. `a` is this device's copy.
    static func merge(_ a: WatchlistDocument, _ b: WatchlistDocument, now: Date = Date()) -> WatchlistDocument {
        let cutoff = (now.timeIntervalSince1970 - tombstoneTTL) * 1000
        var deleted: [String: String] = [:]
        for (id, at) in a.deleted.sorted(by: { $0.key < $1.key }) + b.deleted.sorted(by: { $0.key < $1.key }) {
            let ms = Timestamp.millis(at)
            if let ms, ms < cutoff { continue }
            if let existing = deleted[id] {
                if let ms, let old = Timestamp.millis(existing), ms > old { deleted[id] = at }
            } else {
                deleted[id] = at
            }
        }
        return WatchlistDocument(
            items: mergeRecords(a.items, b.items, deleted: deleted),
            collections: mergeRecords(a.collections, b.collections, deleted: deleted),
            settings: stamp(b.settings.raw) > stamp(a.settings.raw) ? b.settings : a.settings,
            deleted: deleted
        )
    }

    /// Order-insensitive fingerprint, to tell whether a merge changed anything.
    var fingerprint: String {
        func ids(_ raws: [[String: JSONValue]]) -> String {
            raws.map { "\($0["_id"]?.templateString ?? "undefined")@\($0["updatedAt"]?.templateString ?? "undefined")" }
                .sorted(by: Self.jsLess)
                .joined(separator: ",")
        }
        let settingsStamp = settings.raw["updatedAt"]?.templateString ?? "undefined"
        return "\(ids(items.map(\.raw)))|\(ids(collections.map(\.raw)))|\(settingsStamp)|\(deleted.count)"
    }

    /// `Array.prototype.sort()` order: by UTF-16 code units.
    private static func jsLess(_ x: String, _ y: String) -> Bool {
        x.utf16.lexicographicallyPrecedes(y.utf16)
    }
}
