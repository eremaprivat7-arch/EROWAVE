import XCTest
final class NavigationTests:XCTestCase {
    func testDiscoveryLibraryAndPlayer() throws {
        let app=XCUIApplication()
        app.launchArguments=["-uiTest","-didWelcome","YES"]
        app.launch()
        app.buttons["tab.Discover"].tap()
        app.textFields["query"].tap(); app.textFields["query"].typeText("ERØWAVE Studio\n")
        XCTAssertTrue(app.textFields["query"].exists)
        app.buttons["tab.Library"].tap()
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout:5))
        app.buttons["tab.Home"].tap()
        let row=app.buttons.containing(.staticText,identifier:"Undertow").first
        XCTAssertTrue(row.waitForExistence(timeout:5)); row.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout:5))
        app.buttons["Close player"].tap()
        app.buttons["tab.Library"].tap(); XCTAssertTrue(app.buttons["miniPlayer"].exists)
        app.buttons["miniPlayer"].tap(); XCTAssertTrue(app.buttons["Close player"].exists)
    }
}
