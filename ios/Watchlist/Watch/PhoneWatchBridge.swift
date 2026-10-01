import Foundation
import WatchConnectivity

/// Mirrors the watchlist to the Apple Watch and applies its taps. The wire format is the one the
/// watch app already speaks: a snapshot in the application context (or a file when it's too big),
/// and `{"ops": [...]}` messages back.
@MainActor
final class PhoneWatchBridge: NSObject {
    private let store: WatchlistStore
    private var pushTask: Task<Void, Never>?
    private var lastSent: Data?
    private static let maxItems = 1500

    init(store: WatchlistStore) {
        self.store = store
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        store.onAnyChange { [weak self] in self?.schedulePush() }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.push(force: false)
        }
    }

    private func push(force: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = snapshot(), force || data != lastSent else { return }
        lastSent = data
        do {
            try session.updateApplicationContext(["snapshot": data])
        } catch {
            // Too big for an application context: send it as a file instead.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-snapshot.json")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            session.outstandingFileTransfers.forEach { $0.cancel() }
            session.transferFile(url, metadata: ["kind": "snapshot"])
        }
    }

    func snapshot() -> Data? {
        let items = store.items.prefix(Self.maxItems).map { item -> JSONValue in
            var out: [String: JSONValue] = [
                "id": .string(item.id), "title": .string(item.title), "type": .string(item.type.rawValue),
                "status": .string(item.status.rawValue), "favorite": .bool(item.favorite),
                "collectionIds": JSONValue(item.collectionIds), "genres": JSONValue(Array(item.genres.prefix(3))),
                "createdAt": .string(item.createdAt ?? ""), "updatedAt": .string(item.updatedAt ?? ""),
            ]
            // Custom posters are inlined data URLs, far too heavy to ship to the watch.
            if let poster = item.posterUrl, poster.hasPrefix("http") {
                out["posterUrl"] = .string(poster.replacingOccurrences(of: "/t/p/w500/", with: "/t/p/w185/"))
            }
            for key in ["year", "runtime", "showRuntime", "seasons", "episodes", "tmdbRating", "rating"] {
                if let n = item.double(key) { out[key] = .number(n) }
            }
            return .object(out)
        }
        let collections = store.collections.map { c -> JSONValue in
            ["id": .string(c.id), "name": .string(c.name), "position": .number(c.position),
             "itemOrder": JSONValue(c.itemOrder), "createdAt": .string(c.createdAt ?? "")]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(JSONValue.object(["items": .array(Array(items)), "collections": .array(collections)]))
    }

    fileprivate func receive(_ ops: [JSONValue]) {
        WatchOps.apply(ops.compactMap(WatchOp.init), to: store)
        push(force: false)
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in self.push(force: false) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The person switched watches; start over with the new one.
        Task { @MainActor in self.lastSent = nil }
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push(force: false) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler(["ok": true])
    }

    // The watch sends without asking for a reply; without this the message is dropped.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    private nonisolated func handle(_ message: [String: Any]) {
        let ops = Self.ops(message)
        let refresh = message["refresh"] as? Bool == true
        Task { @MainActor in
            if !ops.isEmpty { self.receive(ops) }
            if refresh { self.push(force: true) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let ops = Self.ops(userInfo)
        Task { @MainActor in self.receive(ops) }
    }

    private nonisolated static func ops(_ payload: [String: Any]) -> [JSONValue] {
        guard let raw = payload["ops"], JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let ops = try? JSONDecoder().decode([JSONValue].self, from: data) else { return [] }
        return ops
    }
}
