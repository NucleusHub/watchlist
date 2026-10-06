import XCTest
@testable import Watchlist

final class TMDbExtrasTests: XCTestCase {
    private func json(_ text: String) throws -> [String: JSONValue] {
        try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)).object)
    }

    func testMovieCreditsAndVideos() throws {
        let detail = try json("""
        {"overview": "  Paul unites with the Fremen.  ", "credits": {
            "cast": [{"id": 2, "name": "Zendaya", "character": "Chani", "order": 1, "profile_path": "/z.jpg"},
                     {"id": 1, "name": "Timothée Chalamet", "character": "Paul", "order": 0}],
            "crew": [{"id": 9, "name": "Hans Zimmer", "job": "Original Music Composer", "department": "Sound"},
                     {"id": 5, "name": "Denis Villeneuve", "job": "Director", "department": "Directing"},
                     {"id": 5, "name": "Denis Villeneuve", "job": "Director", "department": "Directing"},
                     {"id": 5, "name": "Denis Villeneuve", "job": "Screenplay", "department": "Writing"}]},
         "videos": {"results": [
            {"site": "YouTube", "key": "clip1", "name": "Clip", "type": "Clip", "official": true, "published_at": "2024-03-01"},
            {"site": "Vimeo", "key": "v", "name": "Elsewhere", "type": "Trailer"},
            {"site": "YouTube", "key": "fan", "name": "Fan trailer", "type": "Trailer", "official": false, "published_at": "2024-05-01"},
            {"site": "YouTube", "key": "t2", "name": "Trailer 2", "type": "Trailer", "official": true, "published_at": "2024-02-01"},
            {"site": "YouTube", "key": "t1", "name": "Trailer 1", "type": "Trailer", "official": true, "published_at": "2023-05-01"}]}}
        """)
        let extras = TMDb.extras(detail, creditsKey: "credits")
        XCTAssertEqual(extras.overview, "Paul unites with the Fremen.")
        XCTAssertEqual(extras.cast.map(\.name), ["Timothée Chalamet", "Zendaya"])
        XCTAssertEqual(extras.cast.last?.role, "Chani")
        XCTAssertEqual(extras.crew.map(\.role), ["Director", "Screenplay", "Original Music Composer"], "known jobs first, duplicates dropped")
        XCTAssertEqual(extras.videos.map(\.key), ["t2", "t1", "fan", "clip1"], "YouTube only; official trailers newest first")
        XCTAssertEqual(extras.videos.first?.url?.absoluteString, "https://www.youtube.com/watch?v=t2")
    }

    func testShowAggregateCreditsPickTheMainRole() throws {
        let detail = try json("""
        {"aggregate_credits": {
            "cast": [{"id": 3, "name": "Adam Scott", "order": 0,
                      "roles": [{"character": "Guest", "episode_count": 1}, {"character": "Mark S.", "episode_count": 19}]}],
            "crew": [{"id": 4, "name": "Dan Erickson", "department": "Writing", "jobs": [{"job": "Creator", "episode_count": 19}]}]}}
        """)
        let extras = TMDb.extras(detail, creditsKey: "aggregate_credits")
        XCTAssertEqual(extras.cast.first?.role, "Mark S.")
        XCTAssertEqual(extras.crew.first?.role, "Creator")
        XCTAssertTrue(extras.videos.isEmpty)
    }

    func testYouTubeKeysFromEveryLinkShape() {
        for link in ["https://www.youtube.com/watch?v=Way9Dexny3w&t=10s", "https://youtu.be/Way9Dexny3w?si=abc",
                     "https://m.youtube.com/watch?v=Way9Dexny3w", "https://www.youtube.com/embed/Way9Dexny3w",
                     "https://youtube.com/shorts/Way9Dexny3w", " https://www.youtube-nocookie.com/embed/Way9Dexny3w "] {
            XCTAssertEqual(TMDb.Video.youTubeKey(link), "Way9Dexny3w", link)
        }
        for link in ["", "Way9Dexny3w", "https://vimeo.com/12345678", "https://www.youtube.com/@channel", "https://youtu.be/x';alert(1)"] {
            XCTAssertNil(TMDb.Video.youTubeKey(link), link)
        }
    }

    func testHandWrittenDescriptionAndTrailerFillInForTMDb() {
        var item = Item(title: "Home video", type: .movie)
        item.overview = "Our trip."
        item.trailerUrl = "https://youtu.be/Way9Dexny3w"
        XCTAssertEqual(ItemDetailView.overview(item, nil), "Our trip.")
        XCTAssertEqual(ItemDetailView.videos(item, nil).map(\.key), ["Way9Dexny3w"])
        let tmdb = TMDb.Extras(overview: "From TMDb", videos: [TMDb.Video(key: "Way9Dexny3w", name: "T", kind: "Trailer", official: true, publishedAt: nil),
                                                               TMDb.Video(key: "other123", name: "T2", kind: "Teaser", official: true, publishedAt: nil)])
        XCTAssertEqual(ItemDetailView.overview(item, tmdb), "From TMDb")
        XCTAssertEqual(ItemDetailView.videos(item, tmdb).map(\.key), ["Way9Dexny3w", "other123"], "the pasted one first, no duplicate")
        item.overview = ""
        XCTAssertNil(item.raw["overview"]?.string, "an empty description isn't stored")
    }
}
