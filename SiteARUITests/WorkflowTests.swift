import XCTest
final class WorkflowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testAuthenticationValidation() {
        let app = XCUIApplication(); app.launch()
        if app.buttons["auth.submit"].waitForExistence(timeout:10) {
            XCTAssertFalse(app.buttons["auth.submit"].isEnabled)
            XCTAssertTrue(app.textFields["auth.email"].exists)
            XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        }
    }
    func testLocalUseSkipsLoginAndCreatesOwnRoom() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["projects.new"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["auth.submit"].exists)
        XCTAssertFalse(app.staticTexts["Apartment Renovation"].exists)
        let title = "UITest-" + UUID().uuidString.prefix(8)
        app.buttons["projects.new"].tap()
        app.alerts.textFields.firstMatch.typeText(String(title)); app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[String(title)].waitForExistence(timeout: 5)); app.staticTexts[String(title)].tap()
        app.buttons["rooms.new"].tap(); app.alerts.textFields.firstMatch.typeText("My room"); app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["My room"].waitForExistence(timeout: 5)); app.staticTexts["My room"].tap()
        XCTAssertTrue(app.buttons["Map room"].waitForExistence(timeout: 5))
        app.buttons["Map room"].tap()
        if app.alerts["AR guidance"].waitForExistence(timeout: 3) { app.alerts.buttons["OK"].tap() }
        XCTAssertTrue(app.staticTexts["Live scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scan.finish"].exists)
        XCTAssertFalse(app.buttons["scan.finish"].isEnabled) // Simulator cannot collect a real map.
        XCTAssertFalse(app.buttons["Register detected marker"].exists)
        XCTAssertFalse(app.buttons["Capture at crosshair"].exists)
        app.buttons["Close"].tap(); app.buttons["Close AR"].tap()
        let back = app.navigationBars.buttons[String(title)]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: back)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        back.tap()
        app.buttons["Delete project and all rooms"].tap(); app.buttons["Delete project"].tap()
        XCTAssertTrue(app.buttons["projects.new"].waitForExistence(timeout: 5))
    }
    /// Requires a configured backend and SITEAR_TEST_EMAIL/PASSWORD in the test process environment.
    func testCreateProjectRoomRenameAndDelete() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["SITEAR_TEST_EMAIL"], let password = env["SITEAR_TEST_PASSWORD"] else { throw XCTSkip("Configure a dedicated backend test account using SITEAR_TEST_EMAIL and SITEAR_TEST_PASSWORD.") }
        let app = XCUIApplication(); app.launch()
        if app.textFields["auth.email"].waitForExistence(timeout:5) {
            app.textFields["auth.email"].tap(); app.textFields["auth.email"].typeText(email)
            app.secureTextFields["auth.password"].tap(); app.secureTextFields["auth.password"].typeText(password)
            app.buttons["auth.submit"].tap()
        }
        XCTAssertTrue(app.buttons["projects.new"].waitForExistence(timeout:20))
        let title = "UITest-" + UUID().uuidString.prefix(8)
        app.buttons["projects.new"].tap()
        app.alerts.textFields.firstMatch.typeText(String(title)); app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[String(title)].waitForExistence(timeout:20)); app.staticTexts[String(title)].tap()
        app.buttons["rooms.new"].tap(); app.alerts.textFields.firstMatch.typeText("Test room"); app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Test room"].waitForExistence(timeout:20)); app.staticTexts["Test room"].tap()
        app.buttons["Rename room"].tap()
        let field = app.alerts.textFields.firstMatch; field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Test room".count) + "Renamed room"); app.alerts.buttons["Save"].tap()
        app.buttons["Delete room"].tap(); app.buttons.matching(identifier: "Delete room").allElementsBoundByIndex.last!.tap()
        app.buttons["Delete project and all rooms"].tap(); app.buttons["Delete project"].tap()
        XCTAssertTrue(app.buttons["projects.new"].waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts[String(title)].exists)
    }
}
