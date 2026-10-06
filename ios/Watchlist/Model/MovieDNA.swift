import Foundation

enum DNAKind: String, CaseIterable, Codable, Sendable {
    case genre, title, person
}

/// Stable keys for MovieDNA entries: `genre:drama`, `movie:603`, `show:1399`, `person:287`.
enum DNAKey {
    static func genre(_ name: String) -> String { "genre:\(name.trimmingCharacters(in: .whitespaces).lowercased())" }
    static func person(_ tmdbID: Int) -> String { "person:\(tmdbID)" }

    /// TMDb titles share a key across devices and libraries; typed-in ones fall back to the record id.
    static func title(_ item: Item) -> String {
        item.tmdbId.map { title(type: item.type, tmdbID: $0) } ?? "item:\(item.id)"
    }

    static func title(type: ItemType, tmdbID: Int) -> String { "\(type.rawValue):\(tmdbID)" }
}

/// One thing the person told MovieDNA about a genre, title or person.
struct DNAEntry: Hashable, Sendable {
    var kind: DNAKind
    var name: String
    /// Set by hand, -100…100; nil keeps the learned value.
    var strength: Double?
    /// Removed by hand; it stays out until a rebuild.
    var hidden = false
    /// When Interested was pressed, oldest first.
    var boosts: [String] = []
    /// The genres a boosted title carries, for titles that aren't in the library.
    var genres: [String] = []
    /// For titles and people that aren't in the library.
    var poster: String?
    var followed = false

    init(kind: DNAKind, name: String, strength: Double? = nil) {
        self.kind = kind
        self.name = name
        self.strength = strength
    }

    init?(_ value: JSONValue) {
        guard let o = value.object, let kind = DNAKind(rawValue: o["kind"]?.string ?? "") else { return nil }
        self.kind = kind
        name = o["name"]?.string ?? ""
        strength = o["strength"]?.double
        hidden = o["hidden"]?.bool ?? false
        boosts = o["boosts"]?.array?.compactMap(\.string) ?? []
        genres = o["genres"]?.array?.compactMap(\.string) ?? []
        poster = o["poster"]?.string
        followed = o["followed"]?.bool ?? false
    }

    var json: JSONValue {
        var o: [String: JSONValue] = ["kind": .string(kind.rawValue), "name": .string(name)]
        if let strength { o["strength"] = .number(strength) }
        if hidden { o["hidden"] = true }
        if !boosts.isEmpty { o["boosts"] = JSONValue(boosts) }
        if !genres.isEmpty { o["genres"] = JSONValue(genres) }
        if let poster { o["poster"] = .string(poster) }
        if followed { o["followed"] = true }
        return .object(o)
    }

    /// Nothing left worth keeping.
    var isEmpty: Bool { strength == nil && !hidden && boosts.isEmpty && !followed }
}

/// A title the person said they don't want to see.
struct NotInterested: Hashable, Sendable {
    var name: String
    var genres: [String]
    var at: String

    init(name: String, genres: [String], at: String) {
        self.name = name
        self.genres = genres
        self.at = at
    }

    init?(_ value: JSONValue) {
        guard let o = value.object else { return nil }
        name = o["name"]?.string ?? ""
        genres = o["genres"]?.array?.compactMap(\.string) ?? []
        at = o["at"]?.string ?? ""
    }

    var json: JSONValue { ["name": .string(name), "genres": JSONValue(genres), "at": .string(at)] }
}

/// What the person set in MovieDNA, kept in `settings.movieDNA` so it syncs with the account.
/// What it learns from the library isn't stored: `MovieDNAEngine` works that out from the titles.
struct MovieDNASettings: Hashable, Sendable {
    var enabled = true
    var entries: [String: DNAEntry] = [:]
    var notInterested: [String: NotInterested] = [:]

    init() {}

    init(_ value: JSONValue?) {
        guard let o = value?.object else { return }
        enabled = o["enabled"]?.bool ?? true
        entries = o["entries"]?.object?.compactMapValues(DNAEntry.init) ?? [:]
        notInterested = o["notInterested"]?.object?.compactMapValues(NotInterested.init) ?? [:]
    }

    var json: JSONValue {
        [
            "enabled": .bool(enabled),
            "entries": .object(entries.mapValues(\.json)),
            "notInterested": .object(notInterested.mapValues(\.json)),
        ]
    }

    /// Changes one entry, creating it if needed; entries left with nothing in them are dropped.
    mutating func edit(_ key: String, kind: DNAKind, name: String, _ change: (inout DNAEntry) -> Void) {
        var entry = entries[key] ?? DNAEntry(kind: kind, name: name)
        if !name.isEmpty { entry.name = name }
        change(&entry)
        entries[key] = entry.isEmpty ? nil : entry
    }
}

extension WatchlistSettings {
    var movieDNA: MovieDNASettings {
        get { MovieDNASettings(raw["movieDNA"]) }
        set { raw["movieDNA"] = newValue.json }
    }
}
