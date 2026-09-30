import Foundation
import WatchConnectivity
import Capacitor

// Mirrors the watchlist to the Apple Watch and takes its edits back.
// The web app stays the only writer of the database: edits from the watch are
// queued in the "watch-inbox" preference and applied by src/sync/watchInbox.js,
// which also covers the app not running when they arrive.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    // Capacitor Preferences stores every key under this prefix in UserDefaults.
    private static let dbKey = "CapacitorStorage.watchlist-db"
    private static let inboxKey = "CapacitorStorage.watch-inbox"
    private static let maxItems = 1500

    var bridgeProvider: () -> CAPBridgeProtocol? = { nil }
    private var pushWork: DispatchWorkItem?
    private var lastSent: Data?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { self.schedulePush() }
    }

    private func schedulePush() {
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push(force: false) }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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

    // MARK: Snapshot

    private func readJSON(_ key: String) -> Any? {
        guard let raw = UserDefaults.standard.string(forKey: key), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func inbox() -> [[String: Any]] {
        readJSON(Self.inboxKey) as? [[String: Any]] ?? []
    }

    private func snapshot() -> Data? {
        let doc = readJSON(Self.dbKey) as? [String: Any] ?? [:]
        var items = (doc["items"] as? [[String: Any]] ?? []).compactMap(Self.watchItem)
        // Queued edits aren't in the database yet; show them anyway so the watch doesn't flip back.
        for op in inbox() {
            guard let id = op["itemId"] as? String, let i = items.firstIndex(where: { $0["id"] as? String == id }) else { continue }
            Self.apply(op, to: &items[i])
        }
        items.sort { ($0["createdAt"] as? String ?? "") > ($1["createdAt"] as? String ?? "") }
        let collections = (doc["collections"] as? [[String: Any]] ?? []).compactMap { c -> [String: Any]? in
            guard let id = c["_id"] as? String, let name = c["name"] as? String else { return nil }
            return [
                "id": id, "name": name,
                "position": c["position"] as? Double ?? 0,
                "itemOrder": c["itemOrder"] as? [String] ?? [],
                "createdAt": c["createdAt"] as? String ?? "",
            ]
        }
        let body: [String: Any] = ["items": Array(items.prefix(Self.maxItems)), "collections": collections]
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private static func watchItem(_ i: [String: Any]) -> [String: Any]? {
        guard let id = i["_id"] as? String, let title = i["title"] as? String else { return nil }
        var out: [String: Any] = [
            "id": id, "title": title,
            "type": i["type"] as? String ?? "movie",
            "status": i["status"] as? String ?? "planned",
            "favorite": i["favorite"] as? Bool ?? false,
            "collectionIds": i["collectionIds"] as? [String] ?? [],
            "genres": Array((i["genres"] as? [String] ?? []).prefix(3)),
            "createdAt": i["createdAt"] as? String ?? "",
            "updatedAt": i["updatedAt"] as? String ?? "",
        ]
        // Custom posters are inlined data URLs, far too heavy to ship to the watch.
        if let poster = i["posterUrl"] as? String, poster.hasPrefix("http") {
            out["posterUrl"] = poster.replacingOccurrences(of: "/t/p/w500/", with: "/t/p/w185/")
        }
        for key in ["year", "runtime", "showRuntime", "seasons", "episodes", "tmdbRating", "rating"] {
            if let n = i[key] as? NSNumber { out[key] = n }
        }
        return out
    }

    private static func apply(_ op: [String: Any], to item: inout [String: Any]) {
        guard let value = op["value"] as? Bool, let at = op["at"] as? String,
              at > (item["updatedAt"] as? String ?? "") else { return }
        switch op["field"] as? String {
        case "favorite": item["favorite"] = value
        case "completed": item["status"] = value ? "completed" : "planned"
        default: return
        }
        item["updatedAt"] = at
    }

    // MARK: Edits from the watch

    private func receive(_ payload: [String: Any]) {
        guard let ops = payload["ops"] as? [[String: Any]], !ops.isEmpty else { return }
        DispatchQueue.main.async {
            var queued = self.inbox()
            let known = Set(queued.compactMap { $0["id"] as? String })
            queued += ops.filter { !known.contains($0["id"] as? String ?? "") }
            guard let data = try? JSONSerialization.data(withJSONObject: queued),
                  let raw = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(raw, forKey: Self.inboxKey)
            self.bridgeProvider()?.triggerWindowJSEvent(eventName: "watchinbox")
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        DispatchQueue.main.async { self.push(force: false) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // The person switched watches; start over with the new one.
        lastSent = nil
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.push(force: false) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        if message["refresh"] as? Bool == true {
            DispatchQueue.main.async { self.push(force: true) }
        }
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }
}
