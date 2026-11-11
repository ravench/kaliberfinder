import XCTest
@testable import Kaliberfinder

final class PrimerTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id))
    }

    func testKnownPrimers() throws {
        XCTAssertEqual(try cartridge("9x19 mm").primer, Cartridge.Primer(type: "small-pistol", diameter: 4.45))
        XCTAssertEqual(try cartridge(".45 ACP").primer?.type, "large-pistol")
        XCTAssertEqual(try cartridge("5.6 mm GP 90").primer?.type, "small-rifle")
        XCTAssertEqual(try cartridge("7.5x55 mm Swiss (GP 11)").primer, Cartridge.Primer(type: "large-rifle", diameter: 5.33))
        XCTAssertEqual(try cartridge(".50 BMG").primer?.diameter ?? 0, 8.03, accuracy: 0.001)
        XCTAssertEqual(try cartridge("12/70").primer?.type, "shotshell-209")
        XCTAssertEqual(try cartridge("9.3x72 mm R").primer, Cartridge.Primer(type: "berdan-nitro", diameter: 6.45))
    }

    func testRimfireAndCaselessHaveNoPrimer() throws {
        XCTAssertNil(try cartridge(".22 LR").primer)
        XCTAssertNil(try cartridge(".17 HMR").primer)
        XCTAssertNil(try cartridge(".44 Rundkugel (.454)").primer)
        XCTAssertNil(try cartridge("4.5 mm Diabolo (.177)").primer)
    }

    func testEveryCentrefireCaseHasAPrimerThatFits() {
        // The Kolibri and Liliput pistol rounds (COTW 18) have heads of 3.6 to 5 mm and primers smaller than
        // any reloading size; calibre-data lists them, unchecked, as small pistol (4.45 mm), the smallest it has.
        let tinyPrimers: Set = ["2.7 mm Kolibri", "3 mm Kolibri", "4.25 mm Liliput"]
        for c in CartridgeCatalog.all where c.hasCase && c.kind != "rimfire" {
            guard let primer = c.primer else { XCTFail("\(c.name) has no primer"); continue }
            if !tinyPrimers.contains(c.name) {
                XCTAssertLessThan(primer.diameter, c.dimensions.base * 0.75, c.name)
            }
            XCTAssertNotEqual(primer.title, primer.type, "\(c.name): no title for \(primer.type)")
        }
    }

    func testOnlyFourBoxerSizesPlus209BMGAndBerdanNitro() {
        let sizes = Set(CartridgeCatalog.all.compactMap { $0.primer?.diameter })
        XCTAssertEqual(sizes, [4.45, 5.33, 6.15, 8.03, 6.45])
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
