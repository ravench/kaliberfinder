import XCTest

/// A tour of the main screens, one screenshot per stop. The PR screens workflow runs it on the
/// pull request and on its base branch and posts the screens that changed as a comment.
/// A pull request that changes a screen the tour does not reach adds a stop.
final class PRScreensTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        // A broken stop should not cost the screenshots of the others.
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    func testTour() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        snap("01-Start")
        scroll()
        snap("02-Start-unten")
        scroll(up: false)

        if open(app.buttons["Masse eingeben"].firstMatch) {
            snap("03-Masse-eingeben")
            back()
        }
        if open(app.buttons["Alle Kaliber"].firstMatch) {
            snap("04-Alle-Kaliber")
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("9x19")
            }
            if open(app.staticTexts["9x19 mm"].firstMatch) {
                snap("05-Kaliber")
            }
        }
    }

    private func open(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(element) not found")
            return false
        }
        element.tap()
        return true
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Drags the screen by a fixed distance and holds before letting go, so there is no momentum
    /// and both runs end on the same scroll position (a swipe's distance varies).
    private func scroll(up: Bool = true) {
        let window = app.windows.firstMatch
        let low = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let (from, to) = up ? (low, high) : (high, low)
        from.press(forDuration: 0.2, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func snap(_ name: String) {
        sleep(2) // let animations settle and scroll indicators fade
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
