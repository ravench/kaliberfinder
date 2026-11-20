import XCTest
@testable import Kaliberfinder

final class LocalizationTests: XCTestCase {
    private func table(_ lang: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: lang),
                                 "\(lang) strings missing")
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private func placeholders(_ s: String) -> Int {
        s.components(separatedBy: "%").count - 1
    }

    func testEveryLanguageHasAllKeysWithPlaceholders() throws {
        let en = try table("en")
        XCTAssertFalse(en.isEmpty)
        for lang in ["en", "fr", "it", "es"] {
            let t = try table(lang)
            if lang != "en" { XCTAssertEqual(Set(t.keys), Set(en.keys), "\(lang) has different keys") }
            for (key, value) in t {
                XCTAssertFalse(value.isEmpty, "\(lang): \(key)")
                XCTAssertEqual(placeholders(value), placeholders(key), "\(lang) translation of \(key) changes the placeholders")
            }
        }
    }

    func testCategoryTitlesAreTranslated() throws {
        let en = try table("en")
        for category in CartridgeCatalog.Category.allCases {
            XCTAssertNotNil(en[category.rawValue], category.rawValue)
        }
        XCTAssertEqual(en["Gesamtlänge"], "Overall length")
        XCTAssertEqual(en["Gürtel"], "Belt")
    }

    func testDeveloperScreenAndCopyrightAreTranslated() throws {
        let en = try table("en")
        XCTAssertEqual(en["Entwickleroptionen"], "Developer options")
        XCTAssertEqual(en["Trainingsdaten aufnehmen"], "Record training data")
        XCTAssertEqual(en["Unbelegte Kaliber zeigen"], "Show unsourced calibres")
        XCTAssertEqual(en["Kanonenkaliber zeigen"], "Show cannon calibres")
        XCTAssertEqual(en["Unbelegt"], "Unsourced")
        XCTAssertEqual(en["Neue Aufnahmeserie"], "New capture series")
        XCTAssertEqual(en["%lld von %lld Fotos hinzugefügt"], "%lld of %lld photos added")
        XCTAssertEqual(en["Nicht in der Liste"], "Not in the list")
        XCTAssertEqual(en["© 2026 Simon Giotta"], "© 2026 Simon Giotta")
    }

    /// The line under «Mögliche Kaliber» on both result screens (review 2026-11-18), in every language.
    func testTheSafetyNoteIsTranslated() throws {
        let key = "Nur zur Bestimmung: Ein Treffer ist keine Freigabe zum Schiessen. Prüfe Bodenstempel und Kaliberangabe der Waffe."
        let expected = ["en": "safe to fire", "fr": "n'autorise pas le tir", "it": "non autorizza a sparare", "es": "no autoriza a disparar"]
        for (lang, words) in expected {
            XCTAssertTrue(try XCTUnwrap(try table(lang)[key], lang).contains(words), lang)
        }
    }

    /// The nose's source part (Raven, 2026-11-20): the curved part, round or pointed; «ogive» means just that.
    func testHeadLengthIsTheNoseOfRoundAndPointedBullets() throws {
        let expected = ["en": "Nose length", "fr": "Longueur de l'ogive", "it": "Lunghezza dell'ogiva", "es": "Longitud de la ojiva"]
        for (lang, title) in expected {
            XCTAssertEqual(try table(lang)["Kopflänge"], title, lang)
            XCTAssertNil(try table(lang)["Spitzenlänge"], lang)
        }
    }

    func testSpanishUsesTheCartridgeTermsOfMunicionOrg() throws {
        let es = try table("es")
        XCTAssertEqual(es["Hülse"], "Vaina")
        XCTAssertEqual(es["Rand"], "Pestaña")
        XCTAssertEqual(es["Boden"], "Culote")
        XCTAssertEqual(es["Zündhütchen"], "Pistón")
        XCTAssertEqual(es["Schweiz"], "Suiza")
    }
}
