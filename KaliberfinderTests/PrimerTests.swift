import XCTest
@testable import Kaliberfinder

final class PrimerTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id))
    }

    func testRimfireAndCaselessHaveNoPrimer() throws {
        XCTAssertNil(try cartridge(".22 LR").primer)
        XCTAssertNil(try cartridge(".17 HMR").primer)
        XCTAssertNil(try cartridge(".44 Rundkugel (.454)").primer)
        XCTAssertNil(try cartridge("4.5 mm Diabolo (.177)").primer)
    }

    func testEveryCentrefireCaseHasAPrimerThatFits() {
        // Pfannl's watchmaker rounds took a tiny primer of their own that no source sizes; calibre-data
        // gives them the smallest Boxer size, wider than their heads, until one does.
        let tiny: Set = ["2.7 mm Kolibri", "3 mm Kolibri", "4.25 mm Liliput"]
        for c in CartridgeCatalog.all where c.hasCase && c.kind != "rimfire" {
            guard let primer = c.primer else { XCTFail("\(c.name) has no primer"); continue }
            if !tiny.contains(c.id) { XCTAssertLessThan(primer.diameter, c.dimensions.base * 0.75, c.name) }
            XCTAssertNotEqual(primer.title, primer.type, "\(c.name): no title for \(primer.type)")
        }
    }

    func testHeadGeometry() throws {
        let nine = try cartridge("9x19 mm")
        XCTAssertEqual(nine.headDiameter, 9.96)
        XCTAssertLessThan(CaseBaseView.faceDiameter(nine), nine.headDiameter)
        let special = try cartridge(".38 Special")
        XCTAssertEqual(special.headDiameter, special.dimensions.rim)
        XCTAssertEqual(CaseBaseView.faceDiameter(special), special.dimensions.base)
    }

    func testTextsAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        for type in ["small-pistol", "large-pistol", "small-rifle", "large-rifle", "shotshell-209", "bmg-35", "berdan-nitro"] {
            let title = Cartridge.Primer(type: type, diameter: 1).title
            XCTAssertNotNil(en[title], title)
        }
        XCTAssertFalse(CaseBaseView.accessibilityText(try cartridge(".22 LR")).isEmpty)
        XCTAssertFalse(CaseBaseView.accessibilityText(try cartridge("9x19 mm")).isEmpty)
    }
}
