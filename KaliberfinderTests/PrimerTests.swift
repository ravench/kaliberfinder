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
        for c in CartridgeCatalog.all where c.hasCase && c.kind != "rimfire" {
            guard let primer = c.primer else { XCTFail("\(c.name) has no primer"); continue }
            XCTAssertLessThan(primer.diameter, c.dimensions.base * 0.75, c.name)
            XCTAssertNotEqual(primer.title, primer.type, "\(c.name): no title for \(primer.type)")
        }
    }

    /// The row shows the calibre's own diameter after the title, so a type that comes in several sizes names no
    /// number in its title (review 2026-11-13: «Berdan Nitro (.254)» stood before every Berdan diameter).
    func testATypeOfSeveralSizesNamesNoneInItsTitle() {
        let primers = CartridgeCatalog.all.compactMap(\.primer)
        XCTAssertFalse(primers.isEmpty)
        for (type, sizes) in Dictionary(grouping: primers, by: \.type) where Set(sizes.map(\.diameter)).count > 1 {
            XCTAssertNil(sizes[0].title.rangeOfCharacter(from: .decimalDigits), "\(type): \(sizes[0].title)")
        }
    }

    func testHeadGeometry() throws {
        let nine = try cartridge("9x19 mm")
        XCTAssertEqual(nine.headDiameter, 10.01)  // the SAAMI rim
        XCTAssertLessThan(CaseBaseView.faceDiameter(nine), nine.headDiameter)
        let special = try cartridge(".38 Special")
        XCTAssertEqual(special.headDiameter, special.dimensions.rim)
        XCTAssertEqual(CaseBaseView.faceDiameter(special), special.dimensions.base)
    }

    func testTextsAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        for type in ["small-pistol", "large-pistol", "small-rifle", "large-rifle", "shotshell-209", "bmg-35", "berdan-nitro", "miniature"] {
            let title = Cartridge.Primer(type: type, diameter: 1).title
            XCTAssertNotNil(en[title], title)
        }
        XCTAssertFalse(CaseBaseView.accessibilityText(try cartridge(".22 LR")).isEmpty)
        XCTAssertFalse(CaseBaseView.accessibilityText(try cartridge("9x19 mm")).isEmpty)
    }
}
