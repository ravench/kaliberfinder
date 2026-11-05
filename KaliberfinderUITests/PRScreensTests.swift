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

        if open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]) {
            snap("06-Einstellungen")
            app.buttons["Fertig"].firstMatch.tap()
        }
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

    /// The matches for one of Raven's photos (an empty GP 11 case), with the measured frame and the
    /// detected neck and taper drawn over it.
    func testPhotoMatches() {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/set-gp11-case-02.jpg")
        app.terminate()
        app.launchArguments += ["-screenTourPhoto", photo.path]
        app.launch()
        if app.navigationBars["Treffer"].waitForExistence(timeout: 10) {
            // The colour cut-out on the simulator can take a while on a busy runner.
            _ = app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90)
            snap("07-Foto-Treffer")
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

    /// Swipes to the very end (or start): a single swipe or drag stops at a different place on
    /// each run, the end of the content does not.
    private func scroll(up: Bool = true) {
        for _ in 0..<6 {
            if up { app.swipeUp(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
        }
    }

    private func snap(_ name: String) {
        sleep(2) // let animations settle and scroll indicators fade
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
