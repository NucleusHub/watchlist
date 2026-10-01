import Foundation

// The trimmed-down copy of the watchlist the iPhone sends (App/WatchBridge.swift).
struct Snapshot: Codable {
    var items: [WatchItem]
    var collections: [WatchCollection]

    static let empty = Snapshot(items: [], collections: [])
}

struct WatchItem: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var type: String
    var status: String
    var favorite: Bool
    var posterUrl: String?
    var collectionIds: [String]
    var genres: [String]
    // Doubles, not Ints: the numbers come from JSON typed by hand on the phone.
    var year: Double?
    var runtime: Double?
    var showRuntime: Double?
    var seasons: Double?
    var episodes: Double?
    var tmdbRating: Double?
    var rating: Double?
    var createdAt: String
    var updatedAt: String

    var isShow: Bool { type == "show" }
    var isCompleted: Bool { status == "completed" }
    var posterURL: URL? { posterUrl.flatMap(URL.init(string:)) }
}

struct WatchCollection: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var position: Double
    var itemOrder: [String]
    var createdAt: String
}

/// One tap on the watch, applied on the phone by PhoneWatchBridge.
struct WatchOp: Codable, Identifiable {
    enum Field: String, Codable { case favorite, completed }

    let id: String
    let itemId: String
    let field: Field
    let value: Bool
    let at: String

    var payload: [String: Any] {
        ["id": id, "itemId": itemId, "field": field.rawValue, "value": value, "at": at]
    }

    func apply(to item: inout WatchItem) {
        // Same guard as the phone: a newer edit there wins.
        guard at > item.updatedAt else { return }
        switch field {
        case .favorite: item.favorite = value
        case .completed: item.status = value ? "completed" : "planned"
        }
        item.updatedAt = at
    }
}

enum ISOTime {
    // Matches JS Date#toISOString, so timestamps compare as plain strings.
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func now() -> String { formatter.string(from: Date()) }
}
