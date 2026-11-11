import XCTest

/// The App Store screenshots: six screens in one language, saved as PNG files. Not part of CI; run
/// it by hand on the 6.9" iPhone and the 13" iPad simulators, once per language (README, «App Store
/// screenshots»):
///
///     TEST_RUNNER_SCREENS_LANG=en TEST_RUNNER_SCREENS_DIR=/tmp/screens/iphone-en xcodebuild test \
///       -project Kaliberfinder.xcodeproj -scheme KaliberfinderScreens -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///       -only-testing:KaliberfinderUITests/AppStoreScreensTests
///
/// Buttons are found by their text in the chosen language, read from the app's Localizable.xcstrings;
/// tools/test_appstore_screens.py checks in CI that every text the tour looks up exists in all four.
final class AppStoreScreensTests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment
    private var language: String { env["SCREENS_LANG"] ?? "de" }
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Region by language: Swiss formats, British English (the app's English).
    static let locales = ["de": "de_CH", "en": "en_GB", "fr": "fr_CH", "it": "it_CH"]

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", Self.locales[language] ?? "de_CH"]
    }

    func testScreens() {
        // 1, 2: a 9 mm photo and its matches, then all matches at 1:1.
        let photo = Self.root.appendingPathComponent("KaliberfinderTests/Fixtures/photo-9x19-wood.jpg")
        app.launchArguments += ["-screenTourPhoto", photo.path]
        app.launch()
        XCTAssertTrue(app.navigationBars[t("Treffer")].waitForExistence(timeout: 15), "Matches missing")
        _ = app.staticTexts[t("Mögliche Kaliber")].waitForExistence(timeout: 90)
        save("01-matches")
        let compare = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix("Alle passenden 1:1 vergleichen (%lld)")))
        if open(compare.firstMatch), app.navigationBars["1:1"].waitForExistence(timeout: 5) {
            save("02-real-size")
        }

        // 3: the start screen, from a fresh launch without the photo.
        app.terminate()
        app.launchArguments = Array(app.launchArguments.dropLast(2))
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        save("03-start")

        // 4, 5: the GP 11's page and its dimensioned drawing.
        if open(app.buttons[t("Alle Kaliber")].firstMatch) {
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("GP 11")
            }
            if open(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "7.5x55")).firstMatch) {
                save("04-calibre")
                if open(app.buttons[t("Masszeichnung anzeigen")].firstMatch) {
                    save("05-drawing")
                }
            }
        }

        // 6: entering measured dimensions.
        app.terminate()
        app.launch()
        if open(app.buttons[t("Masse eingeben")].firstMatch) {
            save("06-dimensions")
        }
    }

    /// The text of the German key `key` in the chosen language (the key itself in German).
    private func t(_ key: String) -> String {
        Self.translate(key, language: language, catalogue: Self.catalogue)
    }

    /// A text with a number placeholder up to the placeholder: «Compare all matches 1:1 (%lld)» → «Compare all matches 1:1».
    private func prefix(_ key: String) -> String {
        Self.prefix(of: t(key))
    }

    static func prefix(of text: String) -> String {
        String(text.prefix { $0 != "(" && $0 != "%" }).trimmingCharacters(in: .whitespaces)
    }

    static let catalogue: [String: Any] = {
        let url = root.appendingPathComponent("Kaliberfinder/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json["strings"] as? [String: Any] ?? [:]
    }()

    static func translate(_ key: String, language: String, catalogue: [String: Any]) -> String {
        let entry = catalogue[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String ?? key
    }

    private func open(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("\(element) not found")
            return false
        }
        element.tap()
        return true
    }

    /// The screen as an attachment and, with SCREENS_DIR set, as <dir>/<name>.png.
    private func save(_ name: String) {
        sleep(2) // let animations settle and scroll indicators fade
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = env["SCREENS_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNoThrow(try shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png")))
    }
}
