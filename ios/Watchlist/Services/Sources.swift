import Foundation
import NucleusPlugins
import WatchlistPluginKit

/// A search result from any source, as the add and edit screen lists it.
struct SourceHit: Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let sourceName: String
    let title: String
    /// "1999" or "1998 · TV": what the source says to tell results apart.
    let detail: String
    let thumbnail: URL?
    let type: ItemType
    /// Opaque; handed back to the source that made it.
    let payload: Data
}

/// Somewhere to look titles up and fill an item from: TMDb, or a plugin's source.
protocol ItemSource: Sendable {
    var id: String { get }
    var name: String { get }
    func search(_ query: String) async throws -> [SourceHit]
    func fill(_ item: inout Item, from hit: SourceHit) async throws
}

struct TMDbSource: ItemSource {
    static let id = "tmdb"
    let tmdb: TMDb

    var id: String { Self.id }
    var name: String { "TMDb" }

    func search(_ query: String) async throws -> [SourceHit] {
        try await tmdb.search(query).map { r in
            SourceHit(id: "tmdb:\(r.id)", sourceID: id, sourceName: name, title: r.title, detail: r.year, thumbnail: r.thumbURL,
                      type: r.type, payload: (try? JSONEncoder().encode(r)) ?? Data())
        }
    }

    func fill(_ item: inout Item, from hit: SourceHit) async throws {
        try await tmdb.fill(&item, from: JSONDecoder().decode(TMDb.SearchResult.self, from: hit.payload))
    }
}

/// A plugin's `SearchSource`, adapted to the app's items.
struct PluginItemSource: ItemSource {
    let source: any SearchSource

    var id: String { source.id }
    var name: String { source.name }

    func search(_ query: String) async throws -> [SourceHit] {
        try await source.search(query).map { hit in
            SourceHit(id: hit.id, sourceID: id, sourceName: name, title: hit.title, detail: hit.subtitle, thumbnail: hit.thumbnail,
                      type: hit.kind == .movie ? .movie : .show, payload: hit.payload)
        }
    }

    func fill(_ item: inout Item, from hit: SourceHit) async throws {
        let original = SearchHit(id: hit.id, title: hit.title, subtitle: hit.detail, thumbnail: hit.thumbnail,
                                 kind: hit.type == .movie ? .movie : .show, payload: hit.payload)
        item.apply(try await source.draft(for: original), from: id)
    }
}

extension Item {
    /// Fills the item from what a plugin source knows, keeping how far each season was already watched.
    mutating func apply(_ draft: SourceDraft, from sourceID: String) {
        title = draft.title
        type = draft.kind == .movie ? .movie : .show
        year = draft.year
        posterUrl = draft.posterURL
        source = sourceID
        if let runtime = draft.runtime { self.runtime = runtime }
        if let seasons = draft.seasons { self.seasons = seasons }
        if let episodes = draft.episodes { self.episodes = episodes }
        if let showRuntime = draft.showRuntime { self.showRuntime = showRuntime }
        if !draft.genres.isEmpty { genres = WatchlistStore.cleanGenres(draft.genres) }
        if !draft.seasonList.isEmpty {
            let watched = Dictionary((seasonProgress ?? []).map { ($0.seasonNumber, $0.watched) }, uniquingKeysWith: { a, _ in a })
            seasonProgress = draft.seasonList.map {
                SeasonProgress(seasonNumber: $0.number, name: String(localized: "Season \($0.number)"), episodeCount: $0.episodeCount,
                               watched: min(watched[$0.number] ?? 0, $0.episodeCount))
            }
        }
    }
}

/// The sources the add and edit screen can use right now, and which of them the person turned on.
@MainActor
struct SourceCatalog {
    let registry: PluginRegistry
    let settings: WatchlistSettings

    /// TMDb first, then whatever active plugins contribute.
    var available: [any ItemSource] {
        [TMDbSource(tmdb: TMDb(apiKey: settings.tmdbApiKey))]
            + registry.contributions(to: .searchSources).map { PluginItemSource(source: $0.value) }
    }

    /// Available and chosen. TMDb also needs its key.
    var active: [any ItemSource] {
        let chosen = Set(settings.searchSources)
        return available.filter { source in
            chosen.contains(source.id) && (source.id != TMDbSource.id || !settings.tmdbApiKey.isEmpty)
        }
    }

    func source(_ id: String) -> (any ItemSource)? { available.first { $0.id == id } }
}
