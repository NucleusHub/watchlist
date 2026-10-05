import Foundation

/// The Movie Database, with the key the person entered in Settings.
struct TMDb {
    let apiKey: String

    enum Failure: LocalizedError {
        case noKey
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noKey: String(localized: "No TMDb API key set. Add one in Settings.")
            case .http(let code): String(localized: "TMDb answered \(code).")
            }
        }
    }

    struct SearchResult: Identifiable, Hashable, Sendable, Codable {
        let id: Int
        let type: ItemType
        let title: String
        let year: String
        let posterPath: String?

        var thumbURL: URL? { posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w92\($0)") } }
        var posterURL: String? { posterPath.map { "https://image.tmdb.org/t/p/w500\($0)" } }
    }

    struct Provider: Sendable {
        let link: String?
        let name: String
        let logo: String?
    }

    static func logoURL(_ path: String?) -> URL? {
        path.flatMap { URL(string: "https://image.tmdb.org/t/p/w45\($0)") }
    }

    private func get(_ path: String, _ params: [String: String] = [:]) async throws -> JSONValue {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw Failure.noKey }
        var c = URLComponents(string: "https://api.themoviedb.org/3\(path)")!
        c.queryItems = [URLQueryItem(name: "api_key", value: key)] + params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, response) = try await URLSession.shared.data(from: c.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Whether TMDb accepts the key. A 401 means it doesn't; network trouble throws.
    func verify() async throws -> Bool {
        do {
            _ = try await get("/configuration")
            return true
        } catch Failure.http(401) {
            return false
        }
    }

    func searchMulti(_ query: String) async throws -> [JSONValue] {
        let data = try await get("/search/multi", ["query": query, "include_adult": "false"])
        return (data.object?["results"]?.array ?? []).filter {
            let t = $0.object?["media_type"]?.string
            return t == "movie" || t == "tv"
        }
    }

    func search(_ query: String) async throws -> [SearchResult] {
        try await searchMulti(query).prefix(7).compactMap(Self.result)
    }

    static func result(_ raw: JSONValue) -> SearchResult? {
        guard let r = raw.object, let id = r["id"]?.int else { return nil }
        let isMovie = r["media_type"]?.string == "movie"
        let date = (isMovie ? r["release_date"] : r["first_air_date"])?.string ?? ""
        return SearchResult(
            id: id, type: isMovie ? .movie : .show,
            title: (isMovie ? r["title"] : r["name"])?.string ?? "",
            year: String(date.prefix(4)), posterPath: r["poster_path"]?.string
        )
    }

    func detail(_ id: Int, type: ItemType) async throws -> [String: JSONValue] {
        try await get(type == .movie ? "/movie/\(id)" : "/tv/\(id)").object ?? [:]
    }

    private static let providerPriority = [8, 337, 384, 386, 350, 15, 531]

    func provider(_ id: Int, type: ItemType) async throws -> Provider? {
        let data = try await get("/\(type == .movie ? "movie" : "tv")/\(id)/watch/providers")
        let results = data.object?["results"]?.object ?? [:]
        guard let region = (results["US"] ?? results.sorted { $0.key < $1.key }.first?.value)?.object else { return nil }
        let flatrate = region["flatrate"]?.array?.compactMap(\.object) ?? []
        let chosen = Self.providerPriority.lazy.compactMap { pid in flatrate.first { $0["provider_id"]?.int == pid } }.first
            ?? flatrate.first
        guard let p = chosen else { return nil }
        return Provider(link: region["link"]?.string, name: p["provider_name"]?.string ?? "", logo: p["logo_path"]?.string)
    }

    static func genres(_ detail: [String: JSONValue]) -> [String] {
        WatchlistStore.cleanGenres(detail["genres"]?.array?.compactMap { $0.object?["name"]?.string } ?? [])
    }

    /// Seasons from a TV detail, keeping how far each season was already watched.
    static func seasonProgress(_ detail: [String: JSONValue], existing: [SeasonProgress]?) -> [SeasonProgress] {
        let prev = Dictionary((existing ?? []).map { ($0.seasonNumber, $0.watched) }, uniquingKeysWith: { a, _ in a })
        return (detail["seasons"]?.array ?? []).compactMap(\.object)
            .compactMap { s -> SeasonProgress? in
                guard let n = s["season_number"]?.int, n > 0, let count = s["episode_count"]?.int, count > 0 else { return nil }
                let name = s["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Season \(n)")
                return SeasonProgress(seasonNumber: n, name: name, episodeCount: count, watched: min(prev[n] ?? 0, count))
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    /// Fills an item from a search result.
    func fill(_ item: inout Item, from result: SearchResult) async throws {
        item.title = result.title
        item.type = result.type
        item.year = Int(result.year)
        item.posterUrl = result.posterURL
        item.tmdbId = result.id
        async let detailTask = detail(result.id, type: result.type)
        async let providerTask = provider(result.id, type: result.type)
        let d = try await detailTask
        let streaming = try? await providerTask
        if let vote = d["vote_average"]?.double, vote > 0 { item.tmdbRating = (vote * 10).rounded() / 10 }
        let genres = Self.genres(d)
        if !genres.isEmpty { item.genres = genres }
        if result.type == .movie {
            if let rt = d["runtime"]?.int, rt > 0 { item.runtime = rt }
        } else {
            if let s = d["number_of_seasons"]?.int, s > 0 { item.seasons = s }
            if let e = d["number_of_episodes"]?.int, e > 0 {
                item.episodes = e
                if let per = d["episode_run_time"]?.array?.first?.int { item.showRuntime = e * per }
            }
            item.seasonProgress = Self.seasonProgress(d, existing: item.seasonProgress)
        }
        if let streaming {
            item.watchLink = streaming.link ?? ""
            item.streamingProvider = streaming.name
            item.streamingLogo = streaming.logo
        }
    }

    /// Fills in what an existing item is missing. Returns false if TMDb doesn't know it.
    func refresh(_ item: inout Item) async throws -> Bool {
        let mediaType = item.type == .movie ? "movie" : "tv"
        var id = item.tmdbId
        var posterPath: String?
        if id == nil {
            let candidates = try await searchMulti(item.title).filter { $0.object?["media_type"]?.string == mediaType }
            guard var match = candidates.first?.object else { return false }
            if let year = item.year, let exact = candidates.compactMap(\.object).first(where: {
                String(($0["release_date"]?.string ?? $0["first_air_date"]?.string ?? "").prefix(4)) == String(year)
            }) { match = exact }
            id = match["id"]?.int
            posterPath = match["poster_path"]?.string
        }
        guard let tmdbId = id else { return false }
        let type = item.type
        async let detailTask = detail(tmdbId, type: type)
        async let providerTask = provider(tmdbId, type: type)
        let d = try await detailTask
        let streaming = try? await providerTask

        if item.tmdbId == nil { item.tmdbId = tmdbId }
        if let vote = d["vote_average"]?.double, vote > 0 { item.tmdbRating = (vote * 10).rounded() / 10 }
        if item.posterUrl == nil || item.posterUrl?.hasPrefix("https://image.tmdb.org") == true,
           let poster = posterPath ?? d["poster_path"]?.string {
            item.posterUrl = "https://image.tmdb.org/t/p/w500\(poster)"
        }
        if item.genres.isEmpty {
            let genres = Self.genres(d)
            if !genres.isEmpty { item.genres = genres }
        }
        if item.year == nil, let date = d["release_date"]?.string ?? d["first_air_date"]?.string { item.year = Int(date.prefix(4)) }
        if item.type == .movie {
            if item.runtime == nil, let rt = d["runtime"]?.int, rt > 0 { item.runtime = rt }
        } else {
            if item.seasons == nil, let s = d["number_of_seasons"]?.int, s > 0 { item.seasons = s }
            if item.episodes == nil, let e = d["number_of_episodes"]?.int, e > 0 { item.episodes = e }
            if item.showRuntime == nil, let e = d["number_of_episodes"]?.int, e > 0, let per = d["episode_run_time"]?.array?.first?.int {
                item.showRuntime = e * per
            }
            let sp = Self.seasonProgress(d, existing: item.seasonProgress)
            if !sp.isEmpty { item.seasonProgress = sp }
        }
        if let streaming {
            item.watchLink = streaming.link
            item.streamingProvider = streaming.name
            item.streamingLogo = streaming.logo
        }
        return true
    }
}
