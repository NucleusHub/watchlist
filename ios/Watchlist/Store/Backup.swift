import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Backup files: the whole document as pretty JSON, the same format the first app exported.
enum Backup {
    struct Preview {
        let document: WatchlistDocument
        let exportedAt: Date?
    }

    enum Failure: LocalizedError {
        case notABackup

        var errorDescription: String? { String(localized: "That file isn't a Watchlist backup.") }
    }

    static func fileName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "watchlist-\(f.string(from: date)).json"
    }

    static func data(_ document: WatchlistDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document.exportJSON())
    }

    static func read(_ data: Data) throws -> Preview {
        guard let o = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object,
              o["format"]?.string == WatchlistDocument.format, o["items"]?.array != nil else { throw Failure.notABackup }
        return Preview(document: .normalize(.object(o)), exportedAt: Timestamp.date(o["exportedAt"]?.string))
    }

    /// Adds the file to what's here; newest edit of each record wins.
    static func merge(_ file: WatchlistDocument, into current: WatchlistDocument) -> WatchlistDocument {
        WatchlistDocument.merge(current, file)
    }

    /// Makes the device exactly the file. Everything not in it gets a tombstone and everything in
    /// it a fresh stamp, so the next sync carries the replacement to the account instead of
    /// merging the old data back.
    static func replace(_ current: WatchlistDocument, with file: WatchlistDocument, at date: Date = Date()) -> WatchlistDocument {
        let at = Timestamp.string(date)
        let keep = Set(file.items.map(\.id) + file.collections.map(\.id))
        var deleted = file.deleted
        for id in current.items.map(\.id) + current.collections.map(\.id) where !keep.contains(id) { deleted[id] = at }
        for id in keep { deleted[id] = nil }
        var next = file
        next.deleted = deleted
        for i in next.items.indices { next.items[i].updatedAt = at }
        for i in next.collections.indices { next.collections[i].updatedAt = at }
        next.settings.updatedAt = at
        return next
    }
}

/// The export, handed to the share sheet as a .json file.
struct BackupFile: Transferable {
    let document: WatchlistDocument

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = URL.temporaryDirectory.appending(path: Backup.fileName())
            try Backup.data(file.document).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
