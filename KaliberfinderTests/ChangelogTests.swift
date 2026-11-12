import XCTest
@testable import Kaliberfinder

/// The release notes CI puts into a TestFlight build show once, the first time that build is opened.
final class ChangelogTests: XCTestCase {
    private let suite = "ChangelogTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let changelog = Changelog(notes: ["de": ["Neu: A", "Neu: B"], "en": ["New: A", "New: B"]])

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suite)
    }

    func testShownOncePerBuild() {
        XCTAssertEqual(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog), ["New: A", "New: B"])
        XCTAssertNil(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog), "shown again")
        XCTAssertEqual(Changelog.toShow(build: "1043", language: "en", defaults: defaults, changelog: changelog)?.count, 2, "a new build shows its notes")
    }

    func testAMissingLanguageFallsBackToGerman() {
        XCTAssertEqual(changelog.bullets(language: "it"), ["Neu: A", "Neu: B"])
        XCTAssertNil(Changelog(notes: ["it": []]).bullets(language: "it"))
    }

    func testABuildWithoutNotesShowsNothingButIsRemembered() {
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
