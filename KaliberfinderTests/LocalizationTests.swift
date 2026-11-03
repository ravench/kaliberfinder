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
        for lang in ["en", "fr", "it"] {
            let t = try table(lang)
            XCTAssertEqual(Set(t.keys), Set(en.keys), "\(lang) has different keys")
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
    }

    func testPickAndCompareHasShortTitle() throws {
        let expected = ["en": "Pick and compare", "fr": "Choisir et comparer", "it": "Scegli e confronta"]
        for (lang, title) in expected {
            XCTAssertEqual(try table(lang)["Auswählen und vergleichen"], title, lang)
            XCTAssertNil(try table(lang)["Kaliber auswählen und vergleichen"], lang)
        }
    }
}
