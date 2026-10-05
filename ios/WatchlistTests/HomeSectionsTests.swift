import NucleusPlugins
import WatchlistPluginKit
import XCTest
@testable import JumpBackInPlugin
@testable import Watchlist

private func title(_ id: String, minutesAgo: Double? = 0, completed: Bool = false, host: String? = "example.com") -> PluginTitle {
    PluginTitle(id: id, title: id, kind: .movie, posterURL: nil, isCompleted: completed,
                lastWatchedAt: minutesAgo.map { Date(timeIntervalSinceNow: -$0 * 60) }, resume: nil, nextEpisode: nil, resumeHost: host)
}

@MainActor
final class HomeSectionsTests: XCTestCase {
    func testPicksTheThreeMostRecentUnfinishedTitlesWithAPageToReturnTo() {
        let picked = JumpBackInSection.pick([
            title("old", minutesAgo: 500), title("done", minutesAgo: 1, completed: true), title("never", minutesAgo: nil),
            title("nowhere", minutesAgo: 2, host: nil), title("a", minutesAgo: 10), title("b", minutesAgo: 5),
            title("c", minutesAgo: 20), title("d", minutesAgo: 30),
        ])
        XCTAssertEqual(picked.map(\.id), ["b", "a", "c"])
    }

    func testPositionsSavedBeforeLastWatchedAtExistedStillCount() {
        var item = Item(title: "Dune", type: .movie)
        item.set("_id", .string("1"))
        item.updatedAt = "2026-01-02T03:04:05.000Z"
        XCTAssertNil(item.pluginTitle.lastWatchedAt, "no position, nothing to jump back to")
        item.playback = Playback(url: "https://www.example.com/watch", position: 600, duration: 6000)
        XCTAssertNotNil(item.pluginTitle.lastWatchedAt)
        XCTAssertEqual(item.pluginTitle.resumeHost, "example.com")
        XCTAssertEqual(item.pluginTitle.resume?.fraction ?? 0, 0.1, accuracy: 0.001)
    }

    func testThePluginContributesAHomeSection() {
        let registry = PluginRegistry(app: "watchlist", state: InMemoryPluginStateStore())
        registry.install(JumpBackInPlugin())
        XCTAssertEqual(registry.contributions(to: .homeSections).map(\.id), ["jump-back-in"])
        registry.setEnabled(false, for: "jump-back-in")
        XCTAssertTrue(registry.contributions(to: .homeSections).isEmpty)
    }
}
