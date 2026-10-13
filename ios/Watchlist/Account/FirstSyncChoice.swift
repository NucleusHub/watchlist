import Foundation

enum FirstSignInOption {
    case merge, keepWeb, keepDevice, startEmpty
    case pick(Set<String>)
}

/// Both sides as they were when the first sync found data on each, for the "how to combine" sheet.
struct FirstSyncChoice: Identifiable {
    let id = UUID()
    let local: WatchlistDocument
    let server: ServerSnapshot
    let rows: [WatchlistAPI.PickRow]
    /// What "Keep this iPhone" would delete on the server.
    let deletions: (items: Int, collections: Int)

    init(local: WatchlistDocument, server: ServerSnapshot, ids: IDMap) {
        self.local = local
        self.server = server
        rows = WatchlistAPI.pickRows(local: local, server: server, ids: ids)
        var book = SyncBook()
        book.ids = ids
        let plan = WatchlistAPI.plan(local: local, server: server, book: book, mode: .keepDevice)
        deletions = (plan.items.delete.count, plan.collections.delete.count)
    }

    /// The server's copy as a document, with the device's settings unless the server has its own.
    func document(settingsFrom settings: WatchlistSettings) -> WatchlistDocument {
        let items = server.items.map { WatchlistAPI.item(from: $0, reverse: [:]) }.filter { !$0.id.isEmpty && !$0.title.isEmpty }
        let collections = server.collections.map { WatchlistAPI.collection(from: $0, reverse: [:]) }.filter { !$0.id.isEmpty && !$0.name.isEmpty }
        return WatchlistDocument(items: items, collections: collections, settings: WatchlistAPI.settings(applying: server.settings, to: settings))
    }

    /// Rows checked by default: everything except deletions made on the device.
    var defaultSelection: Set<String> { Set(rows.filter { $0.side != .deletedOnDevice }.map(\.id)) }
}
