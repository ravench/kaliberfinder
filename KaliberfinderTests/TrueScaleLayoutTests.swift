import XCTest
@testable import Kaliberfinder

final class TrueScaleLayoutTests: XCTestCase {
    private func cartridges(_ ids: [String]) throws -> [Cartridge] {
        try ids.map { try XCTUnwrap(CartridgeCatalog.cartridge(id: $0)) }
    }

    func testBandIsAsTallAsTheRuler() throws {
        let layout = TrueScaleLayout(cartridges: try cartridges(["9x19 mm", "7.5x55 mm Swiss (GP 11)"]), unit: .metric, pointsPerMM: 6)
        // GP 11 is 77.5 mm: plus 5 mm, rounded up to whole centimetres.
        XCTAssertEqual(layout.rulerMM, 90)
        XCTAssertEqual(layout.bandHeight, 540, accuracy: 1e-9)
    }

    func testImperialRulerRoundsToWholeInches() throws {
        let layout = TrueScaleLayout(cartridges: try cartridges(["9x19 mm"]), unit: .imperial, pointsPerMM: 6)
        XCTAssertEqual(layout.rulerMM, 2 * 25.4, accuracy: 1e-9)
        XCTAssertEqual(layout.bandHeight, 2 * 25.4 * 6, accuracy: 1e-9)
    }

    func testEveryCartridgeFitsInTheBand() throws {
        for unit in LengthUnit.allCases {
            for c in CartridgeCatalog.all {
                let layout = TrueScaleLayout(cartridges: [c], unit: unit, pointsPerMM: 6.3)
                XCTAssertGreaterThanOrEqual(layout.rulerMM, c.outline.height + 5, "\(c.id) \(unit)")
                XCTAssertGreaterThanOrEqual(layout.bandHeight, c.outline.height * 6.3, "\(c.id) \(unit)")
            }
        }
    }

    func testTallestCartridgeSetsTheBand() throws {
        let small = TrueScaleLayout(cartridges: try cartridges(["9x19 mm"]), unit: .metric, pointsPerMM: 6)
        let both = TrueScaleLayout(cartridges: try cartridges(["9x19 mm", ".50 BMG"]), unit: .metric, pointsPerMM: 6)
        XCTAssertGreaterThan(both.bandHeight, small.bandHeight)
        XCTAssertEqual(TrueScaleLayout(cartridges: [], unit: .metric, pointsPerMM: 6).rulerMM, 10)
    }

    func testRulerIsPinnedToTheLeftEdgeAndTheBaseLine() throws {
        XCTAssertEqual(TrueScaleLayout.rulerLeadingInset, 0)
        let layout = TrueScaleLayout(cartridges: try cartridges(["9x19 mm"]), unit: .metric, pointsPerMM: 6)
        // The ruler is as tall as the band, so its zero is where the cartridge bases stand.
        XCTAssertEqual(RulerView.y(forMM: 0, height: layout.bandHeight, pointsPerMM: 6), layout.bandHeight)
        // The top of a 29.69 mm cartridge lines up with the 29.69 mm mark.
        let tip = layout.bandHeight - 29.69 * 6
        XCTAssertEqual(RulerView.y(forMM: 29.69, height: layout.bandHeight, pointsPerMM: 6), tip, accuracy: 1e-9)
    }

    func testOneToOneHintsAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertEqual(en["Originalgrösse: nicht zoombar, damit die Masse stimmen."], "Real size: no zoom, so the measurements stay true.")
        XCTAssertNotNil(en["1:1 – Zoomen ist abgeschaltet, damit die Grösse stimmt."])
    }
}
