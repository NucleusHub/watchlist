import XCTest
@testable import Watchlist

final class StatsLayoutTests: XCTestCase {
    func testSmallCardsPairUp() {
        XCTAssertEqual(StatsLayout.standard.rows().map(\.count), [1, 2, 2, 1, 1, 1])
    }

    func testHiddenCardsLeaveTheRows() {
        var layout = StatsLayout.standard
        layout.entries[1].visible = false
        // In progress hidden: Planned pairs with Total, Ratings is left alone.
        XCTAssertEqual(layout.rows()[1].map(\.card), [.planned, .total])
        XCTAssertEqual(layout.rows()[2].map(\.card), [.ratings])
    }

    func testUnavailableCardsAreSkipped() {
        let rows = StatsLayout.standard.rows(available: Set(StatsCard.allCases).subtracting([.availableOn, .topYears]))
        XCTAssertEqual(rows.joined().last?.card, .byType)
    }

    func testOldLayoutsGainNewCards() {
        let old = StatsLayout(entries: [.init(card: .ratings, size: .large), .init(card: .ratings, size: .small)])
        let done = old.completed()
        XCTAssertEqual(done.entries.first?.size, .large)
        XCTAssertEqual(done.entries.count, StatsCard.allCases.count)
    }

    func testSavedLayoutRoundTrips() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StatsLayoutTests"))
        defaults.removePersistentDomain(forName: "StatsLayoutTests")
        var layout = StatsLayout.standard
        layout.entries.swapAt(0, 7)
        layout.entries[2].visible = false
        layout.save(defaults)
        XCTAssertEqual(StatsLayout.load(defaults), layout)
    }
}
