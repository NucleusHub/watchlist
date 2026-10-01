import XCTest

final class LaunchTests: XCTestCase {
    func testLaunchesWithSampleData() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-skipWelcome", "-sampleData"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Dune: Part Two"].waitForExistence(timeout: 10))
    }
}
