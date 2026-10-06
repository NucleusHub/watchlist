import WatchlistPluginKit
import XCTest
@testable import NewsPlugin

final class NewsTests: XCTestCase {
    private func article(_ title: String, summary: String = "", hoursAgo: Double = 1, link: String? = nil) -> Article {
        Article(title: title, link: URL(string: link ?? "https://example.com/\(abs(title.hashValue))")!,
                date: Date().addingTimeInterval(-hoursAgo * 3600), source: "Variety", summary: summary)
    }

    func testRSSItemsParseWithEntitiesAndDates() {
        let xml = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>Feed</title>
        <item><title><![CDATA[‘Dune’ &amp; More]]></title><link>https://variety.com/a</link>
          <pubDate>Mon, 06 Oct 2026 10:00:00 +0000</pubDate><description><![CDATA[<p>Denis Villeneuve&#8217;s next.</p>]]></description></item>
        <item><title>No link</title></item>
        <item><title>Bad link</title><link>javascript:alert(1)</link></item>
        </channel></rss>
        """
        let items = RSSParser.parse(Data(xml.utf8), source: "Variety")
        XCTAssertEqual(items.map(\.title), ["‘Dune’ & More"])
        XCTAssertEqual(items.first?.summary, "Denis Villeneuve’s next.")
        XCTAssertNotNil(items.first?.date)
    }

    func testWholeWordAccentInsensitiveMatching() {
        XCTAssertTrue(NewsInterests.contains("Timothee Chalamet joins", "Timothée Chalamet", caseSensitive: false))
        XCTAssertFalse(NewsInterests.contains("Dunes of the desert", "Dune", caseSensitive: true))
        XCTAssertFalse(NewsInterests.contains("a dune buggy", "Dune", caseSensitive: true), "single words only count capitalised")
        XCTAssertTrue(NewsInterests.contains("‘Dune’ returns", "Dune", caseSensitive: true))
        XCTAssertFalse(NewsInterests.matchable("Up"))
        XCTAssertFalse(NewsInterests.matchable("Home"), "too common to mean the title")
        XCTAssertTrue(NewsInterests.matchable("The Bear"))
    }

    func testReasonsPreferFollowsThenTheWatchlist() {
        let dna = PluginMovieDNA(enabled: true, genres: [], titles: [],
                                 people: [PluginPersonTrait(personID: 1, name: "Denis Villeneuve", strength: 76, followed: true)], notInterested: [])
        let library = [PluginLibraryTitle(kind: .movie, tmdbID: 1, title: "Dune: Part Two", genres: [], rating: nil, favorite: false, isCompleted: false, finishedAt: nil)]
        let interests = NewsInterests(dna: dna, library: library)
        XCTAssertEqual(interests.reason(for: article("Denis Villeneuve on ‘Dune: Part Two’")), .following("Denis Villeneuve"))
        XCTAssertEqual(interests.reason(for: article("Box office", summary: "Dune: Part Two holds")), .watchlist("Dune: Part Two"))
        XCTAssertNil(interests.reason(for: article("Cannes lineup announced")))
    }

    func testMergeDropsSyndicatedCopiesAndSortsNewestFirst() {
        let merged = NewsModel.merge([article("Old", hoursAgo: 5), article("Same Story!", hoursAgo: 2, link: "https://a.com/1"),
                                      article("same story", hoursAgo: 1, link: "https://b.com/2"), article("New", hoursAgo: 0.5)])
        XCTAssertEqual(merged.map(\.title), ["New", "same story", "Old"])
    }
}
