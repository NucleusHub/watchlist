import Foundation
import WatchConnectivity

// The watch's copy of the watchlist: the last snapshot from the phone plus the
// taps it hasn't confirmed yet, both kept on disk so the app opens offline.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty
    @Published private(set) var hasSynced = false

    private var pending: [WatchOp] = []
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    private static let snapshotURL = dir.appendingPathComponent("snapshot.json")
    private static let pendingURL = dir.appendingPathComponent("pending.json")

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.snapshotURL), let s = try? decoder.decode(Snapshot.self, from: data) {
            snapshot = s
            hasSynced = true
        }
        if let data = try? Data(contentsOf: Self.pendingURL) {
            pending = (try? decoder.decode([WatchOp].self, from: data)) ?? []
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Reading

    var items: [WatchItem] {
        snapshot.items.sorted { a, b in
            a.isCompleted != b.isCompleted ? !a.isCompleted : a.createdAt > b.createdAt
        }
    }

    var collections: [WatchCollection] {
        snapshot.collections.sorted { a, b in
            a.position != b.position ? a.position < b.position : a.createdAt < b.createdAt
        }
    }

    func item(_ id: String) -> WatchItem? {
        snapshot.items.first { $0.id == id }
    }

    /// Members in the order set on the phone, the rest newest first after them.
    func items(in collection: WatchCollection) -> [WatchItem] {
        let rank = Dictionary(collection.itemOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return snapshot.items
            .filter { $0.collectionIds.contains(collection.id) }
            .sorted { a, b in
                let ra = rank[a.id] ?? .max, rb = rank[b.id] ?? .max
                return ra != rb ? ra < rb : a.createdAt > b.createdAt
            }
    }

    func count(in collection: WatchCollection) -> Int {
        snapshot.items.filter { $0.collectionIds.contains(collection.id) }.count
    }

    // MARK: Editing

    func toggleFavorite(_ item: WatchItem) {
        record(WatchOp(id: UUID().uuidString, itemId: item.id, field: .favorite, value: !item.favorite, at: ISOTime.now()))
    }

    func toggleCompleted(_ item: WatchItem) {
        record(WatchOp(id: UUID().uuidString, itemId: item.id, field: .completed, value: !item.isCompleted, at: ISOTime.now()))
    }

    private func record(_ op: WatchOp) {
        pending.append(op)
        if let i = snapshot.items.firstIndex(where: { $0.id == op.itemId }) {
            op.apply(to: &snapshot.items[i])
        }
        savePending()
        send([op])
    }

    private func send(_ ops: [WatchOp]) {
        let session = WCSession.default
        guard session.activationState == .activated, !ops.isEmpty else { return }
        let payload: [String: Any] = ["ops": ops.map(\.payload)]
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: nil) { _ in
            // Lost on the way; the queued transfer gets there once the phone is back.
            session.transferUserInfo(payload)
        }
    }

    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["refresh": true], replyHandler: nil, errorHandler: nil)
    }

    // MARK: Snapshots from the phone

    fileprivate func receive(_ data: Data) {
        guard var next = try? decoder.decode(Snapshot.self, from: data) else { return }
        // A tap the phone hasn't seen yet is still pending; keep showing it.
        pending.removeAll { op in
            guard let i = next.items.firstIndex(where: { $0.id == op.itemId }) else { return true }
            if next.items[i].updatedAt >= op.at { return true }
            op.apply(to: &next.items[i])
            return false
        }
        snapshot = next
        hasSynced = true
        try? data.write(to: Self.snapshotURL, options: .atomic)
        savePending()
    }

    fileprivate func activated() {
        let session = WCSession.default
        if let data = session.receivedApplicationContext["snapshot"] as? Data { receive(data) }
        // userInfo transfers survive relaunches, so only resend what never left.
        let queued = Set(session.outstandingUserInfoTransfers.flatMap {
            ($0.userInfo["ops"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        })
        send(pending.filter { !queued.contains($0.id) })
        refresh()
    }

    private func savePending() {
        if let data = try? encoder.encode(pending) { try? data.write(to: Self.pendingURL, options: .atomic) }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["snapshot"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted once this returns, so read it here.
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.refresh() }
    }
}
