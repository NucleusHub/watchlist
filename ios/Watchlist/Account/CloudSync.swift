import Foundation
import NucleusUI
import Observation
import UIKit

/// Keeps the device's watchlist and the account's data on the Watchlist server in step through its REST API
/// (docs/ios-api.md): list, diff by `_id`, then single-record create/update/delete. The first sync on a
/// device lets the user pick how to combine both sides.
@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable { case idle, syncing, offline, error(String), tooLarge, needsChoice }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?
    /// Set while the first sync waits for the user's answer.
    private(set) var choice: FirstSyncChoice?

    private let store: WatchlistStore
    private let auth: NucleusID
    @ObservationIgnored private let crossApp: CrossApp
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var book: SyncBook
    @ObservationIgnored private var pending: SyncOptions?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false

    private static let path = "api/watchlist"
    private static let pushDelay: Duration = .milliseconds(1500)

    init(store: WatchlistStore, auth: NucleusID) {
        self.store = store
        self.auth = auth
        crossApp = CrossApp(store: store, auth: auth)
        state = SyncState.load()
        book = SyncBook.load()
        lastSyncedAt = Timestamp.date(state.lastSyncedAt)
        store.onLocalChange { [weak self] in self?.schedulePush() }
        auth.onSignedIn = { [weak self] mode in await self?.signedIn(mode) }
        auth.onSignedOut = { [weak self] clean in await self?.signedOut(clean: clean) }
        auth.onExpired = { [weak self] in self?.reset() }
    }

    var hasUnsentChanges: Bool { state.dirty }

    // MARK: Triggers

    private func schedulePush() {
        state.dirty = true
        state.save()
        guard auth.isSignedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func signedIn(_ mode: NucleusID.Mode) async {
        state.version = nil
        // Starting clean: nothing from this device goes up, the account's copy comes down.
        if mode == .clean {
            saveBackup("before-clean-sign-in")
            store.clearData()
            book = SyncBook()
        }
        state.dirty = mode != .clean
        await syncNow()
    }

    private func signedOut(clean: Bool) async {
        await syncNow()
        if clean {
            saveBackup("before-sign-out")
            store.clearData()
        }
        reset()
    }

    /// Forget the account copy's version; the device keeps its data.
    private func reset() {
        pushTask?.cancel()
        state = SyncState()
        book = SyncBook()
        choice = nil
        pending = nil
        SyncState.clear()
        crossApp.reset()
        lastSyncedAt = nil
        status = .idle
    }

    /// Going to the background: send what's unsent while iOS still gives us a moment.
    func flushInBackground() {
        guard state.dirty, auth.isSignedIn else { return }
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask { task.end() }
        Task {
            await syncNow()
            task.end()
        }
    }

    // MARK: Syncing

    struct SyncOptions {
        var mode: PlanMode = .normal
        var deleteAllowed: Set<String>?
    }

    func syncNow() async {
        guard auth.isSignedIn else { return }
        pushTask?.cancel()
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task { await runOnce() }
        running = task
        await task.value
        running = nil
        if again {
            again = false
            await syncNow()
        }
    }

    private func runOnce() async {
        if choice != nil { status = .needsChoice; return }
        status = .syncing
        let wasDirty = state.dirty
        state.dirty = false
        defer { state.save(); book.save() }
        do {
            let first = !book.initialized
            var options = pending ?? SyncOptions()
            if first, pending == nil {
                if let ask = try await firstSyncChoice() {
                    choice = ask
                    state.dirty = wasDirty
                    status = .needsChoice
                    return
                }
                // Nothing to choose between: a plain merge, which never deletes on the server.
                options.deleteAllowed = []
            }
            pending = nil
            try await run(options)
            book.initialized = true
            await crossApp.settle()
            await crossApp.publishLibrary()
            lastSyncedAt = Date()
            state.lastSyncedAt = Timestamp.now()
            status = .idle
            adoptAccountTheme()
        } catch {
            pending = nil
            state.dirty = state.dirty || wasDirty
            if !auth.isSignedIn {
                status = .idle
            } else if error is URLError {
                status = .offline
            } else if case Failure.http(413, _) = error {
                status = .tooLarge
            } else {
                status = .error((error as? Failure)?.message ?? error.localizedDescription)
            }
        }
    }

    private func run(_ options: SyncOptions) async throws {
        let commands = await crossApp.inbox()
        try await round(options)
        // Applied after the pull, so a title added on the web is already here; then sent up.
        if !commands.isEmpty {
            crossApp.apply(commands)
            try await round(SyncOptions())
        }
    }

    /// One pass: list the server, diff, write single records, then take the pulls locally.
    private func round(_ options: SyncOptions) async throws {
        let snapshot = try await fetchSnapshot()
        let before = store.document
        let plan = WatchlistAPI.plan(local: before, server: snapshot, book: book, mode: options.mode, deleteAllowed: options.deleteAllowed)
        var itemStamps: [Stamped] = [], collectionStamps: [Stamped] = []

        for c in plan.collections.create + plan.collections.update {
            let isNew = plan.collections.create.contains { $0.id == c.id }
            let knownIDs = book.ids
            let body = WatchlistAPI.body(c, ids: &book.ids)
            let order = WatchlistAPI.order(of: c, ids: &book.ids)
            if book.ids != knownIDs { book.save() }
            let sid = book.ids.server(c.id)
            var written: JSONValue
            if isNew || sid == nil {
                written = try await call("POST", "collections", body)
            } else if let updated = try await call("PATCH", "collections/\(sid!)", body, missingOK: true) {
                written = updated
            } else {
                written = try await call("POST", "collections", body)
            }
            guard let wsid = written.object?["_id"]?.string else { continue }
            book.ids.adopt(local: c.id, server: wsid)
            let known = snapshot.collections.first { $0["_id"]?.string == wsid }?["itemOrder"]?.array?.compactMap(\.string) ?? []
            if order != known {
                written = try await call("PUT", "collections/\(wsid)/order", .object(["itemIds": .array(order.map(JSONValue.string))]))
            }
            collectionStamps.append(stamped(written, local: c.id, expected: c.updatedAt))
        }

        for item in plan.items.create + plan.items.update {
            let isNew = plan.items.create.contains { $0.id == item.id }
            let sid = book.ids.server(item.id)
            let knownIDs = book.ids
            var body = WatchlistAPI.body(item, ids: &book.ids, includeID: isNew)
            if book.ids != knownIDs { book.save() }
            let written: JSONValue
            if !isNew, let sid, let updated = try await call("PATCH", "\(sid)", body, missingOK: true) {
                written = updated
            } else {
                body = WatchlistAPI.body(item, ids: &book.ids, includeID: true)
                written = try await call("POST", "", body)
            }
            if let wsid = written.object?["_id"]?.string { book.ids.adopt(local: item.id, server: wsid) }
            itemStamps.append(stamped(written, local: item.id, expected: item.updatedAt))
        }

        for sid in plan.items.delete {
            _ = try await call("DELETE", sid, missingOK: true)
            book.synced[sid] = nil
        }
        for sid in plan.collections.delete {
            _ = try await call("DELETE", "collections/\(sid)", missingOK: true)
            book.synced[sid] = nil
        }

        var pulledSettings: WatchlistSettings?
        switch plan.settings {
        case .none:
            book.settingsHash = WatchlistAPI.settingsHash(before.settings.raw)
        case .push:
            _ = try await call("PUT", "settings", .object(WatchlistAPI.settingsBody(before.settings.raw)))
            book.settingsHash = WatchlistAPI.settingsHash(before.settings.raw)
        case .pull:
            let next = WatchlistAPI.settings(applying: snapshot.settings, to: before.settings)
            pulledSettings = next
            book.settingsHash = WatchlistAPI.settingsHash(next.raw)
        }

        // Back on the device. Anything edited while the requests ran is left for the next round.
        var doc = store.document
        let reverse = book.ids.reverse
        let items = WatchlistAPI.apply(plan.items.pull, plan.items.remove, to: &doc.items) { WatchlistAPI.item(from: $0, reverse: reverse) }
        let collections = WatchlistAPI.apply(plan.collections.pull, plan.collections.remove, to: &doc.collections) { WatchlistAPI.collection(from: $0, reverse: reverse) }
        for s in itemStamps { WatchlistAPI.stamp(&doc.items, localID: s.local, expected: s.expected, updatedAt: s.updatedAt, completedAt: s.completedAt) }
        for s in collectionStamps { WatchlistAPI.stamp(&doc.collections, localID: s.local, expected: s.expected, updatedAt: s.updatedAt, completedAt: nil) }
        if let pulledSettings, doc.settings == before.settings { doc.settings = pulledSettings }
        for (id, at) in before.deleted where doc.deleted[id] == at { doc.deleted[id] = nil }
        if doc != store.document { store.replace(with: doc, silent: true) }

        for (sid, at) in plan.items.inSync.merging(plan.collections.inSync, uniquingKeysWith: { a, _ in a }) { book.synced[sid] = at }
        for (sid, at) in items.pulled.merging(collections.pulled, uniquingKeysWith: { a, _ in a }) { book.synced[sid] = at }
        for sid in items.removed + collections.removed { book.synced[sid] = nil }
        for s in itemStamps + collectionStamps { if let sid = book.ids.server(s.local) { book.synced[sid] = s.updatedAt } }
    }

    private struct Stamped {
        var local: String
        var expected: String?
        var updatedAt: String
        var completedAt: JSONValue?
    }

    private func stamped(_ written: JSONValue, local: String, expected: String?) -> Stamped {
        let o = written.object
        return Stamped(local: local, expected: expected, updatedAt: o?["updatedAt"]?.string ?? "", completedAt: o?["completedAt"])
    }

    // MARK: First sign-in

    /// Only when the account was never synced here and both the device and the server hold data.
    private func firstSyncChoice() async throws -> FirstSyncChoice? {
        let snapshot = try await fetchSnapshot()
        guard !store.document.isEmpty, !snapshot.isEmpty else { return nil }
        return FirstSyncChoice(local: store.document, server: snapshot, ids: book.ids)
    }

    /// The sheet was closed without answering: nothing is synced until the next "Sync now".
    func deferChoice() { choice = nil }

    /// Runs the user's pick. A backup of the device goes first and any failure to write it stops everything.
    /// Returns an error message, or nil when done.
    func resolve(_ option: FirstSignInOption) async -> String? {
        guard let choice else { return nil }
        do {
            _ = try Backup.save(store.document, label: "before-sync")
            switch option {
            case .merge:
                pending = SyncOptions(deleteAllowed: [])
            case .keepDevice:
                // The server's copy too, since it is about to be replaced.
                _ = try Backup.save(choice.document(settingsFrom: .empty), label: "web-before-sync")
                pending = SyncOptions(mode: .keepDevice)
            case .pick(let selected):
                let rows = choice.rows
                book.skipped = Set(rows.map(\.id)).subtracting(selected)
                pending = SyncOptions(deleteAllowed: Set(rows.filter { $0.side == .deletedOnDevice }.map(\.id)).intersection(selected))
            case .keepWeb:
                let doc = choice.document(settingsFrom: store.settings)
                store.replace(with: doc, silent: true)
                book = SyncBook(initialized: true, synced: choice.server.syncedStamps, settingsHash: WatchlistAPI.settingsHash(doc.settings.raw))
            case .startEmpty:
                // The server keeps everything; its records are skipped here until fetched on purpose.
                store.clearData()
                book = SyncBook(initialized: true, skipped: Set(choice.server.syncedStamps.keys), settingsHash: WatchlistAPI.settingsHash(store.settings.raw))
            }
            book.save()
        } catch {
            return error.localizedDescription
        }
        self.choice = nil
        await syncNow()
        if case .error(let message) = status { return message }
        return nil
    }

    var hasSkipped: Bool { !book.skipped.isEmpty }

    /// Brings in what "Choose items" or "Start empty" left out.
    func fetchSkipped() async {
        book.skipped = []
        book.save()
        await syncNow()
    }

    private func saveBackup(_ label: String) {
        guard !store.document.isEmpty else { return }
        _ = try? Backup.save(store.document, label: label)
    }

    /// Only after a sync, so an accent this app already picked on another device is known first.
    private func adoptAccountTheme() {
        guard let accent = NucleusTheme.shared.account?.adoption(appPickedAt: store.settings.accentPickedAt),
              accent != store.settings.accent else { return }
        store.updateSettings { $0.accent = accent }
    }

    enum Failure: Error {
        case http(Int, String?)

        var message: String {
            switch self {
            case .http(let code, let reason): reason ?? "HTTP \(code)"
            }
        }
    }

    // MARK: HTTP

    private func fetchSnapshot() async throws -> ServerSnapshot {
        async let items = call("GET", "")
        async let collections = call("GET", "collections")
        async let settings = call("GET", "settings")
        return try await ServerSnapshot(
            items: items.array?.compactMap(\.object) ?? [],
            collections: collections.array?.compactMap(\.object) ?? [],
            settings: settings.object ?? [:]
        )
    }

    /// `missingOK`: a 404 gives nil instead of throwing (the record is already gone).
    private func call(_ method: String, _ path: String, _ body: JSONValue? = nil) async throws -> JSONValue {
        guard let value = try await call(method, path, body, missingOK: false) else { return .null }
        return value
    }

    private func call(_ method: String, _ path: String, _ body: JSONValue? = nil, missingOK: Bool) async throws -> JSONValue? {
        var url = NucleusID.origin.appending(path: Self.path)
        if !path.isEmpty { url = url.appending(path: path) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await auth.authorized(req)
        if response.statusCode == 404, missingOK { return nil }
        guard (200..<300).contains(response.statusCode) else { throw Self.failure(response.statusCode, data) }
        return data.isEmpty ? .null : try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func failure(_ code: Int, _ data: Data) -> Failure {
        let body = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object
        let message = body?["message"]?.string ?? body?["error"]?.string ?? body?["error"]?.object?["message"]?.string ?? body?["error_description"]?.string
        return .http(code, message)
    }
}

/// The expiration handler has to end the task it belongs to, so the id lives in a box.
@MainActor
private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
