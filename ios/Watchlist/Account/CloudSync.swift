import Foundation
import NucleusUI
import Observation
import UIKit

/// Keeps the device's watchlist and the copy in the Nucleus ID account (one app-data key) in
/// step: fetch, merge, write back with If-Match, so a write
/// from another device in between gets merged instead of overwritten.
@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable { case idle, syncing, offline, error(String), tooLarge }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?

    private let store: WatchlistStore
    private let auth: NucleusID
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false

    private static let path = "api/v1/app-data/watchlist"
    private static let pushDelay: Duration = .milliseconds(1500)
    private static let maxAttempts = 4

    init(store: WatchlistStore, auth: NucleusID) {
        self.store = store
        self.auth = auth
        state = SyncState.load()
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
        if mode == .clean { store.clearData() }
        state.dirty = mode != .clean
        await syncNow()
    }

    private func signedOut(clean: Bool) async {
        await syncNow()
        if clean { store.clearData() }
        reset()
    }

    /// Forget the account copy's version; the device keeps its data.
    private func reset() {
        pushTask?.cancel()
        state = SyncState()
        SyncState.clear()
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
        status = .syncing
        let wasDirty = state.dirty
        state.dirty = false
        do {
            try await run(localDirty: wasDirty)
            lastSyncedAt = Date()
            state.lastSyncedAt = Timestamp.now()
            status = .idle
            adoptAccountTheme()
        } catch {
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
        state.save()
    }

    private func run(localDirty: Bool) async throws {
        // Nothing changed here and the account copy is still the one we last saw: a cheap 304.
        if !localDirty, let version = state.version {
            if case .unchanged = try await fetch(ifNoneMatch: version) { return }
        }
        for _ in 0..<Self.maxAttempts {
            guard case .value(let remoteDoc, let remoteVersion) = try await fetch(ifNoneMatch: nil) else { continue }
            let local = store.document
            let merged = remoteDoc.map { WatchlistDocument.merge(local, $0) } ?? WatchlistDocument.normalize(local.json)
            if merged.fingerprint != local.fingerprint {
                store.replace(with: merged, silent: true)
            }
            if let remoteDoc, merged.fingerprint == remoteDoc.fingerprint {
                state.version = remoteVersion
                return
            }
            if let version = try await push(merged, version: remoteVersion) {
                state.version = version
                return
            }
        }
        throw Failure.conflict
    }

    /// Only after a sync, so an accent this app already picked on another device is known first.
    private func adoptAccountTheme() {
        guard let accent = NucleusTheme.shared.account?.adoption(appPickedAt: store.settings.accentPickedAt),
              accent != store.settings.accent else { return }
        store.updateSettings { $0.accent = accent }
    }

    private enum Remote {
        case unchanged
        case value(WatchlistDocument?, Int?)
    }

    enum Failure: Error {
        case http(Int, String?)
        case conflict

        var message: String {
            switch self {
            case .http(let code, let reason): reason ?? "HTTP \(code)"
            case .conflict: String(localized: "Another device kept changing the watchlist. Try again.")
            }
        }
    }

    private func fetch(ifNoneMatch: Int?) async throws -> Remote {
        var req = URLRequest(url: NucleusID.origin.appending(path: Self.path))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let ifNoneMatch { req.setValue("\"\(ifNoneMatch)\"", forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await auth.authorized(req)
        switch response.statusCode {
        case 304: return .unchanged
        case 404: return .value(nil, nil)
        case 200..<300:
            let body = try JSONDecoder().decode(JSONValue.self, from: data).object ?? [:]
            return .value(body["value"].map(WatchlistDocument.normalize), body["version"]?.int)
        default: throw Self.failure(response.statusCode, data)
        }
    }

    /// The new version, or nil when someone else wrote first (412) and we should merge again.
    private func push(_ doc: WatchlistDocument, version: Int?) async throws -> Int? {
        var req = URLRequest(url: NucleusID.origin.appending(path: Self.path))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let version { req.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match") } else { req.setValue("*", forHTTPHeaderField: "If-None-Match") }
        req.httpBody = try JSONEncoder().encode(JSONValue.object(["value": doc.json]))
        let (data, response) = try await auth.authorized(req)
        if response.statusCode == 412 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw Self.failure(response.statusCode, data) }
        return (try JSONDecoder().decode(JSONValue.self, from: data)).object?["version"]?.int
    }

    private static func failure(_ code: Int, _ data: Data) -> Failure {
        let body = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object
        let message = body?["message"]?.string ?? body?["error"]?.object?["message"]?.string ?? body?["error_description"]?.string
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
