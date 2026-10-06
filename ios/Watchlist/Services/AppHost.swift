import Foundation
import NucleusPlugins
import Observation
import SwiftUI
import UIKit
import WatchlistPluginKit

/// What plugins get from the app: TMDb with the person's key, navigation and MovieDNA follows.
@MainActor
@Observable
final class AppHost: WatchlistHost {
    @ObservationIgnored private let store: WatchlistStore
    @ObservationIgnored private let navigator: Navigator
    @ObservationIgnored private let registry: PluginRegistry
    @ObservationIgnored private var people: [Int: PluginPerson] = [:]
    /// Plugins read these in their view bodies, so they're built once per change, not once per redraw.
    @ObservationIgnored private var libraryCache: (revision: Int, value: [PluginLibraryTitle])?
    @ObservationIgnored private var dnaCache: (revision: Int, value: PluginMovieDNA)?
    /// The hidden player plugins' trailers play through; RootView keeps it in the window and handles failures.
    let trailers = TrailerPlayer()

    init(store: WatchlistStore, navigator: Navigator, registry: PluginRegistry) {
        self.store = store
        self.navigator = navigator
        self.registry = registry
    }

    private var apiKey: String { store.settings.tmdbApiKey }

    func credits(_ kind: MediaKind, tmdbID: Int) async throws -> PluginCredits {
        #if DEBUG
        if DebugLaunch.samplePeople { return SamplePeople.credits }
        #endif
        let extras = try await TMDbExtrasCache.shared.extras(tmdbID, type: ItemType(kind), apiKey: apiKey)
        return PluginCredits(cast: extras.cast.map(\.plugin), crew: extras.crew.map(\.plugin))
    }

    func person(_ id: Int) async throws -> PluginPerson {
        if let hit = people[id] { return hit }
        #if DEBUG
        if DebugLaunch.samplePeople { return SamplePeople.person(id) }
        #endif
        let person = try await TMDb(apiKey: apiKey).person(id)
        people[id] = person
        return person
    }

    func open(_ destination: HostDestination) {
        switch destination {
        case .person(let id):
            guard hasPage(PluginPageID.person) else { return }
            navigator.open(.pluginPage(id: PluginPageID.person, argument: String(id)))
        case .title(let kind, let tmdbID):
            if let item = libraryItem(kind, tmdbID: tmdbID) {
                navigator.open(.item(item.id))
            } else {
                navigator.open(.preview(ItemType(kind), tmdbID))
            }
        case .page(let id, let argument):
            guard hasPage(id) else { return }
            navigator.open(.pluginPage(id: id, argument: argument))
        case .web(let url, let inApp):
            if inApp { navigator.browse(url) } else { UIApplication.shared.open(url) }
        }
    }

    func isFollowing(_ personID: Int) -> Bool {
        store.movieDNASettings.entries[DNAKey.person(personID)]?.followed == true
    }

    func setFollowing(_ following: Bool, personID: Int, name: String, photoURL: URL?) {
        store.setFollowing(following, personID: personID, name: name, photo: photoURL?.absoluteString)
    }

    func inLibrary(_ kind: MediaKind, tmdbID: Int) -> Bool { libraryItem(kind, tmdbID: tmdbID) != nil }

    func tmdb(_ path: String, query: [String: String]) async throws -> Data {
        // Plugins only get to read TMDb, so paths stay plain API paths.
        guard path.hasPrefix("/"), !path.contains(".."), !path.contains("?") else { throw URLError(.badURL) }
        #if DEBUG
        if let canned = SampleTMDb.response(path, query) { return canned }
        #endif
        return try await TMDb(apiKey: apiKey).data(path, query)
    }

    var hasTMDbKey: Bool { !apiKey.isEmpty }

    var movieDNA: PluginMovieDNA {
        // Reading the document keeps views that use this subscribed to changes, even on a cache hit.
        _ = store.document.settings
        if let cache = dnaCache, cache.revision == store.revision { return cache.value }
        let value = makeMovieDNA()
        dnaCache = (store.revision, value)
        return value
    }

    private func makeMovieDNA() -> PluginMovieDNA {
        let settings = store.movieDNASettings
        let dna = store.movieDNA
        let titles = dna.traits(.title).compactMap { t -> PluginTitleTrait? in
            let parts = t.key.split(separator: ":")
            guard parts.count == 2, let id = Int(parts[1]), let kind = MediaKind(rawValue: String(parts[0])) else { return nil }
            return PluginTitleTrait(kind: kind, tmdbID: id, name: t.name, strength: t.strength)
        }
        let people = dna.traits(.person).compactMap { t -> PluginPersonTrait? in
            guard let id = Int(t.key.dropFirst("person:".count)) else { return nil }
            return PluginPersonTrait(personID: id, name: t.name, strength: t.strength, followed: t.followed)
        }
        return PluginMovieDNA(enabled: settings.enabled, genres: dna.traits(.genre).map { PluginTrait(name: $0.name, strength: $0.strength) },
                              titles: titles, people: people, notInterested: Set(settings.notInterested.keys))
    }

    var library: [PluginLibraryTitle] {
        let items = store.document.items
        if let cache = libraryCache, cache.revision == store.revision { return cache.value }
        let value = items.map { item in
            let finished = (item.completedAt ?? item.updatedAt).flatMap(Timestamp.date)
            return PluginLibraryTitle(kind: item.type.mediaKind, tmdbID: item.tmdbId, title: item.title, genres: item.genres,
                                      rating: item.rating, favorite: item.favorite, isCompleted: item.isCompleted, finishedAt: finished)
        }
        libraryCache = (store.revision, value)
        return value
    }

    func addToWatchlist(_ kind: MediaKind, tmdbID: Int) async throws {
        guard !inLibrary(kind, tmdbID: tmdbID) else { return }
        let (item, _) = try await TMDb(apiKey: apiKey).draft(tmdbID, type: ItemType(kind))
        guard !inLibrary(kind, tmdbID: tmdbID) else { return }
        store.createItem(item)
    }

    func markNotInterested(_ kind: MediaKind, tmdbID: Int, title: String, genres: [String]) {
        store.markNotInterested(key: DNAKey.title(type: ItemType(kind), tmdbID: tmdbID), name: title, genres: genres)
    }

    func personSections(personID: Int, name: String) -> AnyView {
        let context = PersonSectionContext(personID: personID, name: name, host: self)
        let sections = registry.contributions(to: .personSections)
        return AnyView(ForEach(sections, id: \.id) { $0.value.view(context) })
    }

    func playTrailer(_ youTubeKey: String) { trailers.play(youTubeKey) }
    func prepareTrailer(_ youTubeKey: String) { trailers.prepare(youTubeKey) }
    var trailerLoadingKey: String? { trailers.loadingKey }

    /// Whether a plugin that's on can open a person, so names are only tappable when they lead somewhere.
    var canOpenPeople: Bool { hasPage(PluginPageID.person) }

    private func hasPage(_ id: String) -> Bool { registry.contributions(to: .pages).contains { $0.id == id } }

    private func libraryItem(_ kind: MediaKind, tmdbID: Int) -> Item? {
        store.document.items.first { $0.tmdbId == tmdbID && $0.type == ItemType(kind) }
    }
}

extension ItemType {
    init(_ kind: MediaKind) { self = kind == .movie ? .movie : .show }
    var mediaKind: MediaKind { self == .movie ? .movie : .show }
}

extension TMDb.Credit {
    var plugin: PluginCredit {
        PluginCredit(personID: personID, name: name, role: role, department: department, photoURL: photoURL)
    }
}

extension TMDb {
    /// A person with everything they worked on and their Wikidata id, in one request.
    func person(_ id: Int) async throws -> PluginPerson {
        let data = try await get("/person/\(id)", ["append_to_response": "combined_credits,external_ids"])
        return Self.person(data.object ?? [:])
    }

    static func person(_ p: [String: JSONValue]) -> PluginPerson {
        func credit(_ c: [String: JSONValue], acting: Bool) -> PluginPersonCredit? {
            guard let id = c["id"]?.int else { return nil }
            let isMovie = c["media_type"]?.string == "movie"
            guard isMovie || c["media_type"]?.string == "tv" else { return nil }
            let title = (isMovie ? c["title"] : c["name"])?.string ?? ""
            let date = (isMovie ? c["release_date"] : c["first_air_date"])?.string.flatMap { $0.isEmpty ? nil : $0 }
            return PluginPersonCredit(
                titleID: id, kind: isMovie ? .movie : .show, title: title, date: date,
                posterURL: c["poster_path"]?.string.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") },
                role: (acting ? c["character"] : c["job"])?.string ?? "",
                department: acting ? "Acting" : c["department"]?.string ?? "",
                voteCount: c["vote_count"]?.int ?? 0
            )
        }
        let combined = p["combined_credits"]?.object ?? [:]
        let cast = (combined["cast"]?.array ?? []).compactMap(\.object).compactMap { credit($0, acting: true) }
        let crew = (combined["crew"]?.array ?? []).compactMap(\.object).compactMap { credit($0, acting: false) }
        let external = p["external_ids"]?.object ?? [:]
        func text(_ key: String) -> String? { p[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        return PluginPerson(
            id: p["id"]?.int ?? 0, name: text("name") ?? "", biography: text("biography") ?? "",
            knownFor: text("known_for_department"), birthday: text("birthday"), deathday: text("deathday"),
            birthplace: text("place_of_birth"),
            photoURL: text("profile_path").flatMap { URL(string: "https://image.tmdb.org/t/p/h632\($0)") },
            wikidataID: external["wikidata_id"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            imdbID: external["imdb_id"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            credits: cast + crew
        )
    }
}

#if DEBUG
/// Canned credits for screenshots and UI tests without a TMDb key (`-samplePeople`).
enum SamplePeople {
    static let credits = PluginCredits(
        cast: [
            PluginCredit(personID: 1190668, name: "Timothée Chalamet", role: "Paul Atreides", department: "Acting", photoURL: nil),
            PluginCredit(personID: 505710, name: "Zendaya", role: "Chani", department: "Acting", photoURL: nil),
            PluginCredit(personID: 933238, name: "Rebecca Ferguson", role: "Lady Jessica", department: "Acting", photoURL: nil),
            PluginCredit(personID: 16828, name: "Javier Bardem", role: "Stilgar", department: "Acting", photoURL: nil),
        ],
        crew: [
            PluginCredit(personID: 137427, name: "Denis Villeneuve", role: "Director", department: "Directing", photoURL: nil),
            PluginCredit(personID: 137427, name: "Denis Villeneuve", role: "Screenplay", department: "Writing", photoURL: nil),
            PluginCredit(personID: 947, name: "Hans Zimmer", role: "Original Music Composer", department: "Sound", photoURL: nil),
        ]
    )

    static func person(_ id: Int) -> PluginPerson {
        func credit(_ title: String, _ date: String, _ role: String, _ department: String, votes: Int, kind: MediaKind = .movie) -> PluginPersonCredit {
            PluginPersonCredit(titleID: abs(title.hashValue % 100_000), kind: kind, title: title, date: date, posterURL: nil,
                               role: role, department: department, voteCount: votes)
        }
        return PluginPerson(
            id: id, name: "Denis Villeneuve",
            biography: "Denis Villeneuve is a French-Canadian film director and writer. He is known for Arrival, Blade Runner 2049 and the Dune films, and for a patient, image-driven style.",
            knownFor: "Directing", birthday: "1967-10-03", deathday: nil, birthplace: "Gentilly, Québec, Canada",
            photoURL: nil, wikidataID: "Q22096", imdbID: "nm0898288",
            credits: [
                credit("Dune: Part Two", "2024-02-27", "Director", "Directing", votes: 6000),
                credit("Dune: Part Two", "2024-02-27", "Screenplay", "Writing", votes: 6000),
                credit("Dune", "2021-09-15", "Director", "Directing", votes: 12000),
                credit("Blade Runner 2049", "2017-10-04", "Director", "Directing", votes: 13000),
                credit("Arrival", "2016-11-10", "Director", "Directing", votes: 18000),
                credit("Sicario", "2015-09-17", "Director", "Directing", votes: 9000),
                credit("Prisoners", "2013-09-19", "Director", "Directing", votes: 11000),
                credit("Dune: Part Three", "", "Director", "Directing", votes: 10),
                credit("Dune: Prophecy", "2024-11-17", "Executive Producer", "Production", votes: 500, kind: .show),
                credit("The Oscars", "2022-03-27", "Self - Nominee", "Acting", votes: 100, kind: .show),
            ]
        )
    }
}
#endif

#if DEBUG
/// Canned TMDb answers for plugin screens without a key (`-sampleDiscover`).
enum SampleTMDb {
    private static let posters = ["/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg", "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg",
                                  "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", "/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg"]
    private static let movieGenres: [(Int, String)] = [(28, "Action"), (12, "Adventure"), (16, "Animation"), (35, "Comedy"), (80, "Crime"),
        (99, "Documentary"), (18, "Drama"), (10751, "Family"), (14, "Fantasy"), (36, "History"), (27, "Horror"), (10402, "Music"),
        (9648, "Mystery"), (10749, "Romance"), (878, "Science Fiction"), (53, "Thriller"), (10752, "War"), (37, "Western")]
    private static let tvGenres: [(Int, String)] = [(10759, "Action & Adventure"), (16, "Animation"), (35, "Comedy"), (80, "Crime"),
        (18, "Drama"), (9648, "Mystery"), (10765, "Sci-Fi & Fantasy"), (37, "Western")]

    static func response(_ path: String, _ query: [String: String]) -> Data? {
        guard ProcessInfo.processInfo.arguments.contains("-sampleDiscover") else { return nil }
        func json(_ value: Any) -> Data { (try? JSONSerialization.data(withJSONObject: value)) ?? Data() }
        if path == "/genre/movie/list" { return json(["genres": movieGenres.map { ["id": $0.0, "name": $0.1] }]) }
        if path == "/genre/tv/list" { return json(["genres": tvGenres.map { ["id": $0.0, "name": $0.1] }]) }
        if path.hasSuffix("/videos") { return json(["results": [["site": "YouTube", "key": "Way9Dexny3w", "type": "Trailer", "official": true]]]) }
        let isTV = path.contains("/tv")
        let label = path.split(separator: "/").filter { Int($0) == nil }.last.map(String.init) ?? "list"
        let seed = abs(path.hashValue % 1000) * 100
        let genreIDs = query["with_genres"].flatMap { Int($0.split(separator: "|").first ?? "") }.map { [$0] } ?? [18, 878]
        let results: [[String: Any]] = (1...10).map { i in
            var r: [String: Any] = ["id": seed + i, "poster_path": posters[i % posters.count], "genre_ids": genreIDs,
                                    "vote_average": 7.0 + Double(i % 3) * 0.5, "vote_count": 1200]
            if path.hasPrefix("/trending") { r["media_type"] = i.isMultiple(of: 3) ? "tv" : "movie" }
            r[isTV ? "name" : "title"] = "\(label.replacingOccurrences(of: "_", with: " ").capitalized) \(i)"
            r[isTV ? "first_air_date" : "release_date"] = "2025-0\(i % 9 + 1)-01"
            if path.hasPrefix("/trending") { r["title"] = "Trending \(i)"; r["release_date"] = "2025-05-01" }
            return r
        }
        return json(["results": results])
    }
}
#endif
