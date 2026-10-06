import Foundation

/// A small watchlist for previews, UI tests and screenshots.
enum SampleData {
    static var document: WatchlistDocument {
        func item(_ id: String, _ title: String, _ type: ItemType, year: Int, status: WatchStatus = .planned,
                  favorite: Bool = false, poster: String? = nil, genres: [String] = [], runtime: Int? = nil,
                  seasons: Int? = nil, episodes: Int? = nil, rating: Double? = nil, tmdb: Double? = nil,
                  tmdbID: Int? = nil, collections: [String] = [], daysAgo: Double) -> Item {
            var i = Item(title: title, type: type)
            let at = Timestamp.string(Date().addingTimeInterval(-daysAgo * 86400))
            i.set("_id", .string(id))
            i.set("createdAt", .string(at))
            i.set("dateAdded", .string(at))
            i.updatedAt = at
            i.status = status
            i.favorite = favorite
            i.posterUrl = poster.map { "https://image.tmdb.org/t/p/w500\($0)" }
            i.genres = genres
            i.year = year
            i.runtime = runtime
            i.seasons = seasons
            i.episodes = episodes
            i.rating = rating
            i.tmdbRating = tmdb
            i.tmdbId = tmdbID
            i.collectionIds = collections
            if status == .completed { i.set("completedAt", .string(at)) }
            return i
        }
        var weekend = WatchCollection(name: "Weekend picks")
        weekend.set("_id", .string("c00000000000000000000001"))
        weekend.set("createdAt", .string(Timestamp.now()))
        weekend.updatedAt = Timestamp.now()
        return WatchlistDocument(
            items: [
                item("a00000000000000000000001", "Dune: Part Two", .movie, year: 2024, favorite: true,
                     poster: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg", genres: ["Science Fiction", "Adventure"],
                     runtime: 166, tmdb: 8.2, tmdbID: 693134, collections: ["c00000000000000000000001"], daysAgo: 1),
                item("a00000000000000000000002", "Severance", .show, year: 2022, status: .watching,
                     poster: "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg", genres: ["Drama", "Mystery"],
                     seasons: 2, episodes: 19, tmdb: 8.4, tmdbID: 95396, collections: ["c00000000000000000000001"], daysAgo: 2),
                item("a00000000000000000000003", "Oppenheimer", .movie, year: 2023, status: .completed,
                     poster: "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", genres: ["Drama", "History"],
                     runtime: 180, rating: 9, tmdb: 8.1, tmdbID: 872585, daysAgo: 3),
                item("a00000000000000000000004", "The Bear", .show, year: 2022,
                     poster: "/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg", genres: ["Comedy", "Drama"],
                     seasons: 3, episodes: 28, tmdb: 8.2, tmdbID: 136315, daysAgo: 4),
            ],
            collections: [weekend]
        )
    }
}
