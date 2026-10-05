import Foundation
import NucleusPlugins

/// What a plugin implements to add a place to search for titles, next to TMDb. Plugins only produce data;
/// the app turns a `SourceDraft` into a watchlist item, so this contract doesn't depend on the app's model.
public protocol SearchSource: Sendable {
    /// Stable id the person's "search sources" choice is stored under, e.g. `"kitsu-anime"`.
    var id: String { get }
    /// Shown in Settings and next to results.
    var name: String { get }
    func search(_ query: String) async throws -> [SearchHit]
    /// Everything the source knows about a hit, for filling in the item. May make further requests.
    func draft(for hit: SearchHit) async throws -> SourceDraft
}

public enum MediaKind: String, Codable, Sendable {
    case movie, show
}

public struct SearchHit: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// "2013 · TV": whatever helps tell results apart.
    public let subtitle: String
    public let thumbnail: URL?
    public let kind: MediaKind
    /// Opaque to the app; handed back to `draft(for:)`.
    public let payload: Data

    public init(id: String, title: String, subtitle: String, thumbnail: URL?, kind: MediaKind, payload: Data = Data()) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.thumbnail = thumbnail
        self.kind = kind
        self.payload = payload
    }
}

public struct SourceSeason: Hashable, Sendable {
    public let number: Int
    public let episodeCount: Int

    public init(number: Int, episodeCount: Int) {
        self.number = number
        self.episodeCount = episodeCount
    }
}

public struct SourceDraft: Sendable {
    public var title: String
    public var kind: MediaKind
    public var year: Int?
    public var posterURL: String?
    /// Minutes, for movies.
    public var runtime: Int?
    public var seasons: Int?
    public var episodes: Int?
    /// Total minutes for the whole show.
    public var showRuntime: Int?
    public var genres: [String]
    public var seasonList: [SourceSeason]

    public init(title: String, kind: MediaKind, year: Int? = nil, posterURL: String? = nil, runtime: Int? = nil, seasons: Int? = nil,
                episodes: Int? = nil, showRuntime: Int? = nil, genres: [String] = [], seasonList: [SourceSeason] = []) {
        self.title = title
        self.kind = kind
        self.year = year
        self.posterURL = posterURL
        self.runtime = runtime
        self.seasons = seasons
        self.episodes = episodes
        self.showRuntime = showRuntime
        self.genres = genres
        self.seasonList = seasonList
    }
}

public extension ExtensionPoint where Contribution == any SearchSource {
    /// Plugins contribute their sources here, one contribution per source; the contribution id is the source id.
    static var searchSources: Self { .init("watchlist.searchSources") }
}
