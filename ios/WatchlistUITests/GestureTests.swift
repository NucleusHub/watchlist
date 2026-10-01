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
        shoot("collections-list")
    }

    func testMarkingWatchedCelebrates() {
        launch(["-grid", "big"])
        app.buttons["Mark as watched"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.45)
        shoot("confetti")
    }
}
