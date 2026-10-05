import XCTest

/// Regressions from the first device test: swipes on rows and chip strips must not change tabs.
final class GestureTests: XCTestCase {
    private var app: XCUIApplication!

    private func shoot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-skipWelcome", "-sampleData"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Dune: Part Two"].waitForExistence(timeout: 10))
    }

    private var onWatchlist: Bool { app.staticTexts["Dune: Part Two"].exists }

    func testSwipingARowDoesNotChangeTab() {
        launch(["-grid", "list"])
        let row = app.staticTexts["The Bear"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        row.press(forDuration: 0.01, thenDragTo: row.withOffset(CGVector(dx: -200, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 0.8)
        shoot("swipe-row")
        XCTAssertTrue(app.buttons["Delete"].exists, "the row's delete action shows")
        XCTAssertTrue(onWatchlist, "still on the watchlist")
    }

    func testSwipingJumpBackInSnapsToTheNextCardWithoutChangingTab() {
        launch(["-grid", "list", "-sampleJump"])
        let first = app.buttons["Continue watching Dune: Part Two"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        first.swipeLeft()
        Thread.sleep(forTimeInterval: 2)
        shoot("jump-swiped")
        XCTAssertTrue(onWatchlist, "still on the watchlist")
        XCTAssertTrue(app.buttons["Continue watching Severance"].isHittable, "snapped to the second card")
    }

    func testScrollingGenresDoesNotChangeTab() {
        launch(["-grid", "list"])
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Drama")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        chip.press(forDuration: 0.01, thenDragTo: chip.withOffset(CGVector(dx: -250, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(onWatchlist, "still on the watchlist")
    }

    func testSwipingThePageChangesTab() {
        launch(["-grid", "big"])
        let from = app.staticTexts["The Bear"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        from.press(forDuration: 0.01, thenDragTo: from.withOffset(CGVector(dx: -250, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.staticTexts["Weekend picks"].waitForExistence(timeout: 3), "swiping the page goes to collections")
        XCTAssertFalse(app.buttons["Back"].exists, "and the title under the finger wasn't opened")
        shoot("collections-list")
    }

    /// Swiping back over a collection card used to open that collection: a Button fires when the finger
    /// lifts anywhere inside it, however far it travelled.
    func testSwipingBackOverACollectionGoesToTheWatchlistWithoutOpeningIt() {
        for (name, velocity, hold) in [("fast", XCUIGestureVelocity.fast, 0.01), ("default", .default, 0.05), ("slow", .slow, 0.1)] {
            launch(["-grid", "big"])
            app.buttons["Collections"].firstMatch.tap()
            let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Weekend picks")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 3), name)
            let from = card.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
            from.press(forDuration: hold, thenDragTo: from.withOffset(CGVector(dx: 220, dy: 0)), withVelocity: velocity, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 1)
            shoot("swipe-back-\(name)")
            XCTAssertFalse(app.staticTexts["Weekend picks"].exists && app.buttons["Back"].exists || app.buttons["Add titles"].exists, "\(name): a collection was opened")
            XCTAssertTrue(onWatchlist, "\(name): swiping right goes back to the watchlist")
            app.terminate()
        }
    }

    func testTappingCardsStillOpensThem() {
        launch(["-grid", "big"])
        app.staticTexts["The Bear"].tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 3), "a tap opens the title")
        app.buttons["Back"].tap()
        app.buttons["Collections"].firstMatch.tap()
        app.staticTexts["Weekend picks"].tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 3), "a tap opens the collection")
    }

    func testMarkingWatchedCelebrates() {
        launch(["-grid", "big"])
        app.buttons["Mark as watched"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.45)
        shoot("confetti")
    }
}
