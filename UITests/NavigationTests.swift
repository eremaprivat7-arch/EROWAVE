import XCTest
final class NavigationTests:XCTestCase {
    func testDiscoveryLibraryAndPlayer() throws {
        let app=XCUIApplication()
        app.launchArguments=["-uiTest","-didWelcome","YES"]
        app.launch()
        app.buttons["tab.Discover"].tap()
        let field = app.textFields["query"]
        let tappable = NSPredicate(format: "exists == true AND hittable == true")
        let ready = XCTNSPredicateExpectation(predicate: tappable, object: field)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Discover search field did not become tappable")
            return
        }
        field.tap()
        field.typeText("Undertow\n")
        XCTAssertEqual(field.value as? String, "Undertow")
        app.buttons["tab.Library"].tap()
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout:5))
        app.buttons["tab.Home"].tap()
        let row=app.buttons["track.wave:0"]
        XCTAssertTrue(row.waitForExistence(timeout:5)); row.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout:5))
        app.buttons["Close player"].tap()
        app.buttons["tab.Library"].tap(); XCTAssertTrue(app.buttons["miniPlayer"].exists)
        app.buttons["miniPlayer"].tap(); XCTAssertTrue(app.buttons["Close player"].exists)
    }
}
