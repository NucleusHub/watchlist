import Foundation

/// One genre, title or person in someone's MovieDNA, with how much they're into it.
struct DNATrait: Identifiable, Hashable, Sendable {
    let key: String
    let kind: DNAKind
    let name: String
    let poster: String?
    /// -100 (avoid) … 100 (love it).
    let strength: Double
    /// What the library alone says; nil for entries only added by hand.
    let learned: Double?
    let isManual: Bool
    let boosts: Int
    let followed: Bool

    var id: String { key }
    var itemType: ItemType { key.hasPrefix("show:") ? .show : .movie }
}

struct MovieDNA: Hashable, Sendable {
    /// Strongest first.
    var traits: [DNATrait] = []

    static let empty = MovieDNA()

    func traits(_ kind: DNAKind) -> [DNATrait] { traits.filter { $0.kind == kind } }
    func trait(_ key: String) -> DNATrait? { traits.first { $0.key == key } }
}

/// Works MovieDNA out from the library plus what the person set. Pure, so it can run on every change.
enum MovieDNAEngine {
    /// The first Interested press; each later one counts `boostFalloff` times the one before.
    static let boostValue = 0.6
    static let boostFalloff = 0.8
    /// Interested fades: a press counts half after this many days.
    static let boostHalfLife: Double = 45
    static let maxBoosts = 20
    static let followValue = 2.0
    static let notInterestedPenalty = 0.4

    /// How strongly the title itself pulls, before Interested presses.
    static func score(_ item: Item) -> Double {
        var s = 0.0
        if let rating = item.rating, rating > 0 {
            // 6/10 is neutral; 10 is a strong yes, 2 a strong no.
            s += 1.5 * max(-1, min(1, (rating - 6) / 4))
        } else if item.status == .completed {
            s += 0.3
        }
        if item.favorite { s += 1 }
        switch item.status {
        case .watching: s += 0.4
        case .planned: s += 0.2
        case .completed: break
        }
        return s
    }

    /// What the Interested presses add up to now: later presses add less, and every press fades.
    static func boost(_ presses: [String], now: Date = Date()) -> Double {
        presses.enumerated().reduce(0) { sum, press in
            guard let at = Timestamp.date(press.element) else { return sum }
            let days = max(0, now.timeIntervalSince(at) / 86400)
            return sum + boostValue * pow(boostFalloff, Double(press.offset)) * pow(0.5, days / boostHalfLife)
        }
    }

    /// Squashes a raw score onto -100…100; `scale` is the score that reaches about 76.
    static func strength(_ raw: Double, scale: Double) -> Double {
        (100 * tanh(raw / scale)).rounded()
    }

    static func profile(items: [Item], settings: MovieDNASettings, now: Date = Date()) -> MovieDNA {
        guard settings.enabled else { return .empty }
        let entries = settings.entries
        var genreScore: [String: Double] = [:]
        var genreName: [String: String] = [:]
        var titleScore: [String: (name: String, poster: String?, raw: Double)] = [:]

        func feed(_ genres: [String], _ raw: Double) {
            for g in genres {
                let key = DNAKey.genre(g)
                genreScore[key, default: 0] += raw
                if genreName[key] == nil { genreName[key] = g }
            }
        }

        var seen = Set<String>()
        for item in items {
            let key = DNAKey.title(item)
            guard seen.insert(key).inserted, entries[key]?.hidden != true, settings.notInterested[key] == nil else { continue }
            let entry = entries[key]
            let raw = score(item) + boost(entry?.boosts ?? [], now: now)
            feed(item.genres, raw)
            // Titles only on the list feed their genres but aren't a trait of their own.
            if item.rating != nil || item.favorite || entry?.boosts.isEmpty == false {
                titleScore[key] = (item.title, item.posterUrl, raw)
            }
        }
        // Titles boosted from elsewhere (Discover, a person's page) that aren't in the library.
        for (key, entry) in entries where entry.kind == .title && !seen.contains(key) && !entry.hidden && !entry.boosts.isEmpty {
            let raw = boost(entry.boosts, now: now)
            feed(entry.genres, raw)
            titleScore[key] = (entry.name, entry.poster, raw)
        }
        for (_, title) in settings.notInterested {
            feed(title.genres, -notInterestedPenalty)
        }

        var traits: [DNATrait] = []
        func add(_ key: String, _ kind: DNAKind, _ name: String, poster: String? = nil, learned: Double?) {
            let entry = entries[key]
            guard entry?.hidden != true else { return }
            guard let value = entry?.strength ?? learned else { return }
            traits.append(DNATrait(key: key, kind: kind, name: entry?.name.isEmpty == false ? entry!.name : name,
                                   poster: poster ?? entry?.poster, strength: max(-100, min(100, value)), learned: learned, isManual: entry?.strength != nil,
                                   boosts: entry?.boosts.count ?? 0, followed: entry?.followed ?? false))
        }

        for (key, raw) in genreScore { add(key, .genre, genreName[key] ?? key, learned: strength(raw, scale: 4)) }
        for (key, title) in titleScore { add(key, .title, title.name, poster: title.poster, learned: strength(title.raw, scale: 1.5)) }
        for (key, entry) in entries where genreScore[key] == nil && titleScore[key] == nil {
            switch entry.kind {
            case .person:
                let raw = (entry.followed ? followValue : 0) + boost(entry.boosts, now: now)
                add(key, .person, entry.name, learned: raw == 0 ? nil : strength(raw, scale: 2))
            case .genre, .title:
                add(key, entry.kind, entry.name, learned: nil)
            }
        }
        traits.sort { $0.strength != $1.strength ? $0.strength > $1.strength : $0.name.localizedCompare($1.name) == .orderedAscending }
        return MovieDNA(traits: traits)
    }
}
