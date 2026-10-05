import NucleusPlugins
import WatchlistPluginKit
import XCTest
@testable import Watchlist

private struct FakeSource: SearchSource {
    let id = "fake"
    let name = "Fake"
    func search(_ query: String) async throws -> [SearchHit] { [] }
    func draft(for hit: SearchHit) async throws -> SourceDraft { SourceDraft(title: "x", kind: .show) }
}

private struct FakePlugin: Plugin {
    let manifest = PluginManifest(id: "fake-plugin", name: "Fake", version: "1.0.0", target: ["watchlist"])
    func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .searchSources, id: "fake", FakeSource() as any SearchSource)
    }
}

@MainActor
final class SourcesTests: XCTestCase {
    func testApplyingADraftFillsTheItemAndKeepsWatchedEpisodes() {
        var item = Item(title: "Bebop", type: .movie)
        item.seasonProgress = [SeasonProgress(seasonNumber: 1, name: "Season 1", episodeCount: 20, watched: 7)]
        item.apply(SourceDraft(title: "Cowboy Bebop", kind: .show, year: 1998, posterURL: "https://x/p.jpg", seasons: 1, episodes: 26,
                               showRuntime: 624, seasonList: [SourceSeason(number: 1, episodeCount: 26)]), from: "kitsu-anime")
        XCTAssertEqual(item.title, "Cowboy Bebop")
        XCTAssertEqual(item.type, .show)
        XCTAssertEqual(item.year, 1998)
        XCTAssertEqual(item.posterUrl, "https://x/p.jpg")
        XCTAssertEqual(item.source, "kitsu-anime")
        XCTAssertEqual(item.episodes, 26)
        XCTAssertEqual(item.showRuntime, 624)
        XCTAssertEqual(item.seasonProgress?.map(\.episodeCount), [26])
        XCTAssertEqual(item.seasonProgress?.map(\.watched), [7])
    }

    func testCatalogOffersTMDbAndActivePluginSourcesAndSearchesTheChosenOnes() {
        let registry = PluginRegistry(app: "watchlist", state: InMemoryPluginStateStore())
        registry.install(FakePlugin())
        var settings = WatchlistSettings.empty
        XCTAssertEqual(SourceCatalog(registry: registry, settings: settings).available.map(\.id), ["tmdb", "fake"])

        XCTAssertTrue(SourceCatalog(registry: registry, settings: settings).active.isEmpty, "TMDb needs its key")
        settings.tmdbApiKey = "key"
        XCTAssertEqual(SourceCatalog(registry: registry, settings: settings).active.map(\.id), ["tmdb"])
        settings.searchSources = ["tmdb", "fake"]
        XCTAssertEqual(SourceCatalog(registry: registry, settings: settings).active.map(\.id), ["tmdb", "fake"])
        settings.searchSources = ["fake"]
        XCTAssertEqual(SourceCatalog(registry: registry, settings: settings).active.map(\.id), ["fake"], "no key needed for a plugin source")
    }

    func testSwitchingThePluginOffTakesItsSourceAway() {
        let registry = PluginRegistry(app: "watchlist", state: InMemoryPluginStateStore())
        registry.install(FakePlugin())
        var settings = WatchlistSettings.empty
        settings.searchSources = ["fake"]
        registry.setEnabled(false, for: "fake-plugin")
        let catalog = SourceCatalog(registry: registry, settings: settings)
        XCTAssertEqual(catalog.available.map(\.id), ["tmdb"])
        XCTAssertTrue(catalog.active.isEmpty)
    }
}
