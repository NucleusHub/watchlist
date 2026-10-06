import XCTest

/// Walks the main screens with sample data and saves a screenshot of each.
/// Run with TEST_RUNNER_SHOT_DIR=/some/folder to keep them; otherwise they're attached to the result.
final class ScreenshotTests: XCTestCase {
    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-skipWelcome", "-sampleData"] + extra
        app.launch()
        _ = app.staticTexts["Dune: Part Two"].waitForExistence(timeout: 10)
        return app
    }

    func testScreens() {
        for (name, args) in [
            ("home-small", ["-grid", "small"]),
            ("home-big", ["-grid", "big"]),
            ("home-list", ["-grid", "list"]),
            ("item", ["-route", "item"]),
            ("collection", ["-route", "collection", "-grid", "big"]),
            ("settings", ["-route", "settings"]),
            ("stats", ["-route", "stats"]),
            ("editor", ["-route", "edit"]),
            ("seasons", ["-route", "seasons"]),
            ("light", ["-appearance", "light", "-grid", "big"]),
            ("cs-home", ["-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ", "-grid", "list"]),
            ("cs-stats", ["-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ", "-route", "stats"]),
            ("cs-settings", ["-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ", "-route", "settings"]),
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-resetAll", "-skipWelcome", "-sampleData"] + args
            app.launch()
            Thread.sleep(forTimeInterval: 2.5)
            shoot(name)
            app.terminate()
        }
    }

    func testContextMenuAndCollections() {
        let app = launch(["-grid", "big"])
        Thread.sleep(forTimeInterval: 2)
        app.staticTexts["Dune: Part Two"].press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 1)
        shoot("context-menu")
        XCTAssertTrue(app.buttons["Edit"].exists, "native context menu shows")
        app.tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["Collections"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shoot("collections")
    }

    func testWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        shoot("welcome")
    }

    /// Start on Welcome leads into the tour; every page, then Done closes it.
    func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll"]
        app.launch()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        app.buttons["Start"].tap()
        let next = app.buttons["tourNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "tour opens after Welcome")
        for page in 1...8 {
            Thread.sleep(forTimeInterval: 2.2)
            shoot("tour-\(page)")
            next.tap()
        }
        XCTAssertTrue(next.waitForNonExistence(timeout: 3), "Done closes the tour")
    }
}
