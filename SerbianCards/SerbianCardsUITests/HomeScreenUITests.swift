import XCTest

final class HomeScreenUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    private func navigateToHomeIfNeeded() -> Bool {
        // If we land on API key entry, skip — can't test home without a key
        if app.staticTexts["Welcome to Serbian Cards"].waitForExistence(timeout: 3) {
            return false
        }
        // Already on home
        return app.navigationBars["Serbian Cards"].waitForExistence(timeout: 5)
    }

    func testHomeScreenElementsDoNotOverlap() throws {
        try XCTSkipUnless(navigateToHomeIfNeeded(), "App is on API key entry — no key in test simulator")

        let statTexts = app.staticTexts
        let newLabel = statTexts["New"]
        let dueLabel = statTexts["Due"]
        let totalLabel = statTexts["Total"]
        let masteredLabel = statTexts["Mastered"]

        guard newLabel.exists, dueLabel.exists, totalLabel.exists, masteredLabel.exists else {
            XCTFail("All stat labels should be visible on home screen")
            return
        }

        // Navigation bar should not overlap stat cards
        let navBar = app.navigationBars["Serbian Cards"]
        let navFrame = navBar.frame
        let newFrame = newLabel.frame
        XCTAssertFalse(
            navFrame.intersects(newFrame),
            "Navigation bar (\(navFrame)) should not overlap 'New' stat card (\(newFrame))"
        )

        // Stat cards in same row should not overlap each other
        assertNoOverlap(newLabel, dueLabel, "New", "Due")
        assertNoOverlap(dueLabel, totalLabel, "Due", "Total")

        // Buttons should exist and not overlap each other
        let learnButton = app.buttons["Learn New Words"]
        let reviewButton = app.buttons["Review"]
        let settingsButton = app.buttons["Settings"]

        if learnButton.exists && reviewButton.exists {
            assertNoOverlap(learnButton, reviewButton, "Learn", "Review")
        }
        if reviewButton.exists && settingsButton.exists {
            assertNoOverlap(reviewButton, settingsButton, "Review", "Settings")
        }

        // Mastered card should not overlap buttons
        if learnButton.exists {
            assertNoOverlap(masteredLabel, learnButton, "Mastered", "Learn")
        }
    }

    func testAddWordsScreenElementsDoNotOverlap() throws {
        try XCTSkipUnless(navigateToHomeIfNeeded(), "App is on API key entry — no key in test simulator")

        let addButton = app.buttons["Add Words"]
        guard addButton.waitForExistence(timeout: 5) else {
            XCTFail("Add Words button should exist on home screen")
            return
        }
        addButton.tap()

        let navTitle = app.staticTexts["Add Words"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3))

        let picker = app.segmentedControls.firstMatch
        if picker.exists {
            let parseButton = app.buttons["Parse with GPT"]
            let splitButton = app.buttons["Simple Split"]
            if parseButton.exists && splitButton.exists {
                assertNoOverlap(parseButton, splitButton, "Parse button", "Split button")
            }
        }
    }

    private func assertNoOverlap(
        _ elementA: XCUIElement,
        _ elementB: XCUIElement,
        _ nameA: String,
        _ nameB: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frameA = elementA.frame
        let frameB = elementB.frame
        XCTAssertFalse(
            frameA.intersects(frameB),
            "'\(nameA)' (\(frameA)) overlaps with '\(nameB)' (\(frameB))",
            file: file,
            line: line
        )
    }
}
