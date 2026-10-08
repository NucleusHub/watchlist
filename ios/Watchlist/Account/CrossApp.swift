import CryptoKit
import Foundation

/// The cross-app side of Nucleus ID: commands other apps send (marking titles watched) and the
/// `library` view they read. Runs inside a sync pass and never fails it.
@MainActor
final class CrossApp {
    /// How a command ended, kept until the server has it: `applied` or `rejected`, with a result.
    struct Settlement: Codable, Equatable {
        var status: String
        var result: JSONValue

        static func applied(_ result: JSONValue) -> Settlement { Settlement(status: "applied", result: result) }
        static func rejected(_ reason: String) -> Settlement {
            Settlement(status: "rejected", result: ["reason": .string(reason)])
        }
    }

    struct Command: Equatable {
        var id: String
        var type: String
        var payload: JSONValue
    }

    private let store: WatchlistStore
    private let auth: NucleusID
    private let defaults: UserDefaults
    /// Applied but not yet settled, by command id; a re-delivered one isn't applied twice.
    private var settlements: [String: Settlement]

    private static let settlementsKey = "crossAppSettlements"
    private static let libraryHashKey = "crossAppLibraryHash"

    init(store: WatchlistStore, auth: NucleusID, defaults: UserDefaults = .standard) {
        self.store = store
        self.auth = auth
        self.defaults = defaults
        settlements = defaults.data(forKey: Self.settlementsKey)
            .flatMap { try? JSONDecoder().decode([String: Settlement].self, from: $0) } ?? [:]
    }

    /// Signed out or switched accounts: nothing to settle, and the next account needs the view.
    func reset() {
        settlements = [:]
        defaults.removeObject(forKey: Self.settlementsKey)
        defaults.removeObject(forKey: Self.libraryHashKey)
    }

    // MARK: Inbox

    /// Commands not applied yet; empty when the inbox can't be read.
    func inbox() async -> [Command] {
        var req = URLRequest(url: NucleusID.origin.appending(path: "api/v1/commands/inbox"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, status) = await send(req), (200..<300).contains(status),
              let body = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return (body.object?["commands"]?.array ?? []).compactMap { value in
            guard let o = value.object, let id = o["id"]?.string, let type = o["type"]?.string,
                  settlements[id] == nil else { return nil }
            return Command(id: id, type: type, payload: o["payload"] ?? .null)
        }
    }

    /// Applies each command to the store; settled later, once the result is pushed.
    func apply(_ commands: [Command]) {
        guard !commands.isEmpty else { return }
        for command in commands {
            settlements[command.id] = Self.apply(type: command.type, payload: command.payload, to: store)
        }
        saveSettlements()
    }

    /// Tells the server how each applied command ended. Kept for the next sync when that fails.
    func settle() async {
        for (id, settlement) in settlements.sorted(by: { $0.key < $1.key }) {
            var req = URLRequest(url: NucleusID.origin.appending(path: "api/v1/commands/\(id)/settle"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(JSONValue.object(["status": .string(settlement.status), "result": settlement.result]))
            guard let (_, status) = await send(req) else { break }
            // 404 or 409: gone, cancelled, or settled by another device; nothing left to do.
            if (200..<300).contains(status) || [404, 409].contains(status) {
                settlements[id] = nil
            }
        }
        saveSettlements()
    }

    private func saveSettlements() {
        if settlements.isEmpty {
            defaults.removeObject(forKey: Self.settlementsKey)
        } else if let data = try? JSONEncoder().encode(settlements) {
            defaults.set(data, forKey: Self.settlementsKey)
        }
    }

    // MARK: Library view

    /// Publishes `library` when it changed since the last publish.
    func publishLibrary() async {
        let value = Self.library(store.document)
        let hash = Self.hash(value)
        guard hash != defaults.string(forKey: Self.libraryHashKey) else { return }
        var req = URLRequest(url: NucleusID.origin.appending(path: "api/v1/views/library"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(JSONValue.object(["value": value]))
        guard let (_, status) = await send(req), (200..<300).contains(status) else { return }
        defaults.set(hash, forKey: Self.libraryHashKey)
    }

    private func send(_ req: URLRequest) async -> (Data, Int)? {
        guard let (data, response) = try? await auth.authorized(req) else { return nil }
        return (data, response.statusCode)
    }

    /// What other apps see of the watchlist: titles and season progress, newest first.
    nonisolated static func library(_ document: WatchlistDocument) -> JSONValue {
        let items = document.items
            .filter { document.deleted[$0.id] == nil }
            .sorted {
                let a = Timestamp.millis($0.createdAt) ?? 0, b = Timestamp.millis($1.createdAt) ?? 0
                return a != b ? a > b : $0.id < $1.id
            }
            .map { item -> JSONValue in
                let seasons = item.isShow ? item.seasonProgress ?? [] : []
                // Inlined photos are too big to share; only real URLs go out.
                let poster = item.posterUrl.flatMap { $0.hasPrefix("http") ? $0 : nil }
                return [
                    "id": .string(item.id), "title": .string(item.title), "type": .string(item.type.rawValue),
                    "tmdbId": JSONValue(item.tmdbId), "poster": JSONValue(poster), "status": .string(item.status.rawValue),
                    "seasons": .array(seasons.map {
                        ["number": .number(Double($0.seasonNumber)), "name": .string($0.name),
                         "episodeCount": .number(Double($0.episodeCount)), "watched": .number(Double($0.watched))]
                    }),
                ]
            }
        return ["items": .array(items)]
    }

    nonisolated static func hash(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Commands

    /// Applies one command. Safe to repeat: marks only add progress and unmarks only take it back.
    static func apply(type: String, payload: JSONValue, to store: WatchlistStore) -> Settlement {
        guard type == "markWatched" || type == "unmarkWatched" else { return .rejected("unknownType") }
        guard let p = payload.object, let itemID = p["itemId"]?.string, !itemID.isEmpty,
              let season = optionalInt(p["season"]), let fromEp = optionalInt(p["fromEp"]),
              let toEp = optionalInt(p["toEp"]), let restoreTo = optionalInt(p["restoreTo"]) else {
            return .rejected("badPayload")
        }
        guard let item = store.item(itemID) else { return .rejected("itemNotFound") }
        let previousStatus: JSONValue = .string(item.status.rawValue)
        // Seasons only count for a show; a movie is always marked as a whole.
        let seasonNumber = item.isShow ? season : nil
        let previousWatched = seasonNumber.flatMap { n in item.seasonProgress?.first { $0.seasonNumber == n }?.watched }
        if seasonNumber != nil, previousWatched == nil { return .rejected("seasonNotFound") }
        let result: JSONValue = previousWatched.map { ["previousWatched": .number(Double($0)), "previousStatus": previousStatus] }
            ?? ["previousStatus": previousStatus]

        if type == "markWatched" {
            if let n = seasonNumber {
                if let fromEp, fromEp < 1 { return .rejected("badPayload") }
                let total = item.seasonProgress?.first { $0.seasonNumber == n }?.episodeCount ?? 0
                // No range given: the whole season.
                let through = toEp ?? total
                guard through >= (fromEp ?? 1) else { return .rejected("badPayload") }
                store.markSeasonWatched(itemID, season: n, through: through)
                // What the task left behind; an unmark only rolls back while the season is still there.
                let after = store.item(itemID)?.seasonProgress?.first { $0.seasonNumber == n }?.watched ?? through
                return .applied(["previousWatched": .number(Double(previousWatched ?? 0)), "watched": .number(Double(after)),
                                 "previousStatus": previousStatus])
            }
            if !(item.isCompleted && (!item.episodeTotals.tracked || item.episodeTotals.watched >= item.episodeTotals.total)) {
                store.markWatched(itemID)
            }
            // A whole show marks every season, so an unmark needs each one's count to put back.
            let seasons = item.isShow ? item.seasonProgress ?? [] : []
            guard !seasons.isEmpty else { return .applied(result) }
            return .applied(["previousStatus": previousStatus, "previousSeasons": .array(seasons.map {
                ["number": .number(Double($0.seasonNumber)), "watched": .number(Double($0.watched))]
            })])
        }

        if let n = seasonNumber, let restoreTo {
            guard restoreTo >= 0, let expected = optionalInt(p["expectWatched"]) else { return .rejected("badPayload") }
            // Watched past what the task marked: rolling back would take that progress too.
            if let expected, let current = previousWatched, current > expected { return .rejected("progressMoved") }
            store.unmarkSeasonWatched(itemID, season: n, keeping: restoreTo)
            return .applied(result)
        }
        if item.isShow, let seasons = p["restoreSeasons"]?.array {
            let counts = seasons.compactMap { s -> (Int, Int)? in
                guard let o = s.object, let n = o["number"]?.int, let w = o["watched"]?.int, w >= 0 else { return nil }
                return (n, w)
            }
            store.restoreSeasons(itemID, Dictionary(counts, uniquingKeysWith: min))
            return .applied(result)
        }
        guard let restore = p["restoreStatus"]?.string.flatMap(WatchStatus.init) else { return .rejected("badPayload") }
        if item.isCompleted, restore != .completed { store.updateItem(itemID) { $0.status = restore } }
        return .applied(result)
    }

    /// `.some(nil)` when the key is absent or null, nil when it holds something that isn't a whole number.
    private static func optionalInt(_ value: JSONValue?) -> Int?? {
        guard let value, !value.isNull else { return .some(nil) }
        guard case .number(let n) = value, n.rounded() == n, n.isFinite else { return nil }
        return .some(Int(n))
    }
}
