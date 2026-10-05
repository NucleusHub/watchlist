import Foundation
import Observation

/// The watchlist on this device: one JSON document in Application Support, written shortly
/// after each change. Every write keeps the rules synced documents rely on (timestamps,
/// tombstones, completedAt), so copies on different devices merge cleanly.
enum ProgressReset: String, CaseIterable {
    case current, season, show
}

@MainActor
@Observable
final class WatchlistStore {
    private(set) var document = WatchlistDocument()
    /// Goes up each time a title becomes watched, so the UI can celebrate.
    private(set) var celebrations = 0
    private var saveTask: Task<Void, Never>?
    private let fileURL: URL?
    @ObservationIgnored private var changeHandlers: [() -> Void] = []
    @ObservationIgnored private var anyChangeHandlers: [() -> Void] = []

    nonisolated static let maxGenres = 12
    nonisolated static let maxGenreLength = 40

    nonisolated static var defaultURL: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "watchlist.json")
    }

    /// `fileURL: nil` keeps everything in memory (previews and tests).
    init(fileURL: URL? = WatchlistStore.defaultURL, document: WatchlistDocument? = nil) {
        self.fileURL = fileURL
        if let document {
            self.document = document
        } else if let fileURL, let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode(WatchlistDocument.self, from: data) {
            self.document = decoded
        }
    }

    var hasSavedFile: Bool { fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    // MARK: Reading

    /// Newest first, like `getItems`.
    var items: [Item] {
        document.items.sorted { (Timestamp.millis($0.createdAt) ?? 0) > (Timestamp.millis($1.createdAt) ?? 0) }
    }

    var collections: [WatchCollection] {
        document.collections.sorted {
            $0.position != $1.position
                ? $0.position < $1.position
                : (Timestamp.millis($0.createdAt) ?? 0) < (Timestamp.millis($1.createdAt) ?? 0)
        }
    }

    var settings: WatchlistSettings { document.settings }

    func item(_ id: String) -> Item? { document.items.first { $0.id == id } }
    func collection(_ id: String) -> WatchCollection? { document.collections.first { $0.id == id } }

    func members(of collectionID: String) -> [Item] {
        items.filter { $0.isIn(collectionID) }
    }

    /// Members in the order set by hand, the rest after them newest first.
    func orderedMembers(of collection: WatchCollection) -> [Item] {
        let members = members(of: collection.id)
        let order = collection.itemOrder
        guard !order.isEmpty else { return members }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return members.enumerated()
            .sorted { (rank[$0.element.id] ?? .max, $0.offset) < (rank[$1.element.id] ?? .max, $1.offset) }
            .map(\.element)
    }

    /// The posters a collection's cover shows: picked titles, otherwise the first members.
    func coverPosters(of collection: WatchCollection) -> [String] {
        let byID = Dictionary(document.items.map { ($0.id, $0.posterUrl) }, uniquingKeysWith: { first, _ in first })
        let picked = collection.coverItemIds.compactMap { byID[$0] ?? nil }
        if !picked.isEmpty { return picked }
        return members(of: collection.id).compactMap(\.posterUrl).prefix(collection.coverCount).map { $0 }
    }

    // MARK: Items

    @discardableResult
    func createItem(_ draft: Item) -> Item? {
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { return nil }
        let at = Timestamp.now()
        item.set("_id", .string(RecordID.make()))
        item.set("dateAdded", .string(at))
        item.set("createdAt", .string(at))
        item.updatedAt = at
        item.genres = Self.cleanGenres(item.genres)
        if item.status == .completed, item.completedAt == nil { item.set("completedAt", .string(at)) }
        document.items.append(item)
        commit()
        return item
    }

    /// Applies `change` to the item, then stamps it. The id and `completedAt` can't be set
    /// directly; `completedAt` follows the status.
    @discardableResult
    func updateItem(_ id: String, _ change: (inout Item) -> Void) -> Item? {
        guard let i = document.items.firstIndex(where: { $0.id == id }) else { return nil }
        let before = document.items[i]
        var item = before
        change(&item)
        item.set("_id", .string(before.id))
        item.raw["completedAt"] = before.raw["completedAt"] ?? .null
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.genres != before.genres { item.genres = Self.cleanGenres(item.genres) }
        if item.status != before.status {
            item.set("completedAt", item.status == .completed ? .string(Timestamp.now()) : .null)
            if item.status == .completed { celebrations += 1 }
        }
        item.updatedAt = Timestamp.now()
        document.items[i] = item
        commit()
        return item
    }

    func deleteItem(_ id: String) {
        guard let i = document.items.firstIndex(where: { $0.id == id }) else { return }
        document.items.remove(at: i)
        document.deleted[id] = Timestamp.now()
        commit()
    }

    func toggleFavorite(_ id: String) {
        updateItem(id) { $0.favorite.toggle() }
    }

    /// Mark watched: completed, and every episode of a tracked show watched.
    func markWatched(_ id: String) {
        updateItem(id) { item in
            item.status = .completed
            item.playback = nil
            item.lastPage = nil
            if item.isShow, let progress = item.seasonProgress, !progress.isEmpty {
                item.seasonProgress = progress.map { var s = $0; s.watched = s.episodeCount; return s }
            }
        }
    }

    /// Takes back watching progress. `.current` forgets the saved time and page (a movie's whole progress, or the
    /// episode in progress); `.season` also unwatches the season being watched; `.show` unwatches everything.
    func resetProgress(_ id: String, _ scope: ProgressReset) {
        updateItem(id) { item in
            item.clearWatchHistory()
            guard item.isShow, scope != .current else { return }
            if var seasons = item.seasonProgress, !seasons.isEmpty {
                if scope == .show {
                    seasons = seasons.map { var s = $0; s.watched = 0; return s }
                } else if let i = item.currentSeasonIndex {
                    seasons[i].watched = 0
                }
                item.seasonProgress = seasons
                let totals = item.episodeTotals
                item.status = Item.status(watched: totals.watched, total: totals.total)
            } else if scope == .show {
                item.status = .planned
            }
        }
    }

    /// One more episode of a tracked show; the saved playback is spent either way.
    func markEpisodeWatched(_ id: String) {
        updateItem(id) { item in
            item.watchNextEpisode()
            item.playback = nil
        }
    }

    func cycleStatus(_ id: String) {
        updateItem(id) { item in
            let order = WatchStatus.allCases
            item.status = order[(order.firstIndex(of: item.status)! + 1) % order.count]
        }
    }

    nonisolated static func cleanGenres(_ genres: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in genres {
            let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxGenreLength))
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
            if out.count == maxGenres { break }
        }
        return out
    }

    // MARK: Collections

    @discardableResult
    func createCollection(name: String, description: String = "", coverUrl: String? = nil,
                          coverItemIds: [String] = [], coverCount: Int = 4) -> WatchCollection? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var col = WatchCollection(name: name)
        col.details = description.trimmingCharacters(in: .whitespacesAndNewlines)
        col.coverUrl = coverUrl
        col.coverItemIds = coverItemIds
        col.coverCount = coverCount
        let at = Timestamp.now()
        col.set("_id", .string(RecordID.make()))
        col.set("createdAt", .string(at))
        col.updatedAt = at
        document.collections.append(col)
        commit()
        return col
    }

    @discardableResult
    func updateCollection(_ id: String, _ change: (inout WatchCollection) -> Void) -> WatchCollection? {
        guard let i = document.collections.firstIndex(where: { $0.id == id }) else { return nil }
        var col = document.collections[i]
        change(&col)
        col.set("_id", .string(id))
        col.name = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
        col.details = col.details.trimmingCharacters(in: .whitespacesAndNewlines)
        col.updatedAt = Timestamp.now()
        document.collections[i] = col
        commit()
        return col
    }

    /// Deletes the collection and takes it off every item that was in it.
    func deleteCollection(_ id: String) {
        guard let i = document.collections.firstIndex(where: { $0.id == id }) else { return }
        document.collections.remove(at: i)
        let at = Timestamp.now()
        document.deleted[id] = at
        for j in document.items.indices where document.items[j].isIn(id) {
            document.items[j].collectionIds.removeAll { $0 == id }
            document.items[j].updatedAt = at
        }
        commit()
    }

    func addItems(_ itemIDs: [String], to collectionID: String) {
        guard collection(collectionID) != nil else { return }
        let wanted = Set(itemIDs)
        let at = Timestamp.now()
        var modified = false
        for j in document.items.indices where wanted.contains(document.items[j].id) && !document.items[j].isIn(collectionID) {
            document.items[j].collectionIds.append(collectionID)
            document.items[j].updatedAt = at
            modified = true
        }
        if modified { commit() }
    }

    func setCollections(_ collectionIDs: [String], for itemID: String) {
        updateItem(itemID) { $0.collectionIds = collectionIDs }
    }

    func saveOrder(_ itemIDs: [String], in collectionID: String) {
        updateCollection(collectionID) { $0.itemOrder = itemIDs }
    }

    // MARK: Settings

    /// Saves settings, stamping them only when something actually changed (they sync).
    func updateSettings(_ change: (inout WatchlistSettings) -> Void) {
        var next = document.settings
        change(&next)
        next.updatedAt = document.settings.updatedAt
        guard next != document.settings else { return }
        next.updatedAt = Timestamp.now()
        document.settings = next
        commit()
    }

    // MARK: Whole document

    /// Swaps in a new document (a sync merge or an imported backup).
    func replace(with document: WatchlistDocument, silent: Bool = false) {
        self.document = document
        commit(silent: silent)
    }

    /// Empties the watchlist on this device. Settings are device setup, not data, and stay.
    func clearData() {
        document = WatchlistDocument(settings: document.settings)
        commit(silent: true)
    }

    // MARK: Saving

    /// Called after every local change; the sync layer pushes on it.
    func onLocalChange(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    /// Called after every change, including ones that came from a sync.
    func onAnyChange(_ handler: @escaping () -> Void) {
        anyChangeHandlers.append(handler)
    }

    private func commit(silent: Bool = false) {
        scheduleSave()
        if !silent { changeHandlers.forEach { $0() } }
        anyChangeHandlers.forEach { $0() }
    }

    private func scheduleSave() {
        guard let fileURL else { return }
        saveTask?.cancel()
        let snapshot = document
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: fileURL)
        }
    }

    /// Writes immediately, used when the app is about to go to the background.
    func flush() {
        guard let fileURL else { return }
        saveTask?.cancel()
        Self.write(document, to: fileURL)
    }

    private nonisolated static func write(_ document: WatchlistDocument, to url: URL) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
