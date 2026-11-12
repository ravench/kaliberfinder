import XCTest
@testable import Kaliberfinder

/// The release notes CI puts into a build show once, the first time that build is opened after an update.
final class ChangelogTests: XCTestCase {
    private let suite = "ChangelogTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let changelog = Changelog(notes: ["de": ["Neu: A", "Neu: B"], "en": ["New: A", "New: B"]])

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suite)
    }

    func testShownOncePerBuild() {
        defaults.set("1041", forKey: Changelog.shownBuildKey)  // an update, not a fresh install
        XCTAssertEqual(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog), ["New: A", "New: B"])
        XCTAssertNil(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog), "shown again")
        XCTAssertEqual(Changelog.toShow(build: "1043", language: "en", defaults: defaults, changelog: changelog)?.count, 2, "a new build shows its notes")
    }

    func testAFreshInstallShowsNothingButTheNextUpdateDoes() {
        XCTAssertNil(Changelog.toShow(build: "1100", language: "de", defaults: defaults, changelog: changelog), "first launch after install")
        XCTAssertEqual(defaults.string(forKey: Changelog.shownBuildKey), "1100")
        XCTAssertEqual(Changelog.toShow(build: "1101", language: "de", defaults: defaults, changelog: changelog), ["Neu: A", "Neu: B"])
    }

    func testAMissingLanguageFallsBackToGerman() {
        XCTAssertEqual(changelog.bullets(language: "it"), ["Neu: A", "Neu: B"])
        XCTAssertNil(Changelog(notes: ["it": []]).bullets(language: "it"))
    }

    func testABuildWithoutNotesShowsNothingButIsRemembered() {
        defaults.set("0", forKey: Changelog.shownBuildKey)
        XCTAssertNil(Changelog.toShow(build: "1", language: "de", defaults: defaults, changelog: Changelog(notes: [:])))
        XCTAssertEqual(defaults.string(forKey: Changelog.shownBuildKey), "1")
        XCTAssertNil(Changelog.toShow(build: "2", language: "de", defaults: defaults, changelog: nil))
    }

    func testTheTourFixtureHasAllLanguages() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "changelog", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Changelog.self, from: Data(contentsOf: url))
        for language in ["de", "en", "fr", "it"] {
            XCTAssertEqual(fixture.bullets(language: language)?.count, 5, language)
        }
    }
}
