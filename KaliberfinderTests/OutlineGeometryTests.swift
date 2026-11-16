import XCTest
@testable import Kaliberfinder

final class OutlineGeometryTests: XCTestCase {
    func testParsesClosedPolygons() {
        let polys = OutlineGeometry.parse("M0 0 L10 0 L10 5 Z M1 1 L2 1 L2 2 Z")
        XCTAssertEqual(polys.count, 2)
        XCTAssertEqual(polys[0], [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 5)])
        XCTAssertEqual(polys[1].count, 3)
    }

    func testParsesDecimalsAndNegatives() {
        let polys = OutlineGeometry.parse("M-1.50 2.25 L3.00 -4.75 L0 0 Z")
        XCTAssertEqual(polys.first?.first, Point(x: -1.5, y: 2.25))
        XCTAssertEqual(polys.first?[1], Point(x: 3, y: -4.75))
    }

    /// calibre-data exports a hollow point's cavity as its own closed triangle (its PR 191): the app decodes it and
    /// keeps it out of the silhouette.
    func testCavityDecodesButStaysOutOfTheSilhouette() throws {
        let json = #"{"width": 10, "height": 20, "case": "M0 20 L10 20 L10 8 L0 8 Z", "bullet": "M2 8 L8 8 L5 0 Z", "cavity": "M6 2 L5 4 L4 2 Z"}"#
        let outline = try JSONDecoder().decode(Cartridge.Outline.self, from: Data(json.utf8))
        XCTAssertEqual(OutlineGeometry.parse(try XCTUnwrap(outline.cavity)), [[Point(x: 6, y: 2), Point(x: 5, y: 4), Point(x: 4, y: 2)]])
        XCTAssertEqual(OutlineGeometry(outline).polygons.count, 2)
        XCTAssertEqual(OutlineGeometry(outline).width(at: 4), 3, accuracy: 0.01, "the nose, not the cavity")
        let plain = try JSONDecoder().decode(Cartridge.Outline.self, from: Data(#"{"width": 1, "height": 1}"#.utf8))
        XCTAssertNil(plain.cavity)
    }

    func testWidthOfStraightCase() throws {
        let nine = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let g = OutlineGeometry(nine.outline)
        // Halfway down the case the body is close to the base diameter.
        XCTAssertEqual(g.width(at: 22), nine.dimensions.base, accuracy: 0.4)
        // The tip is much narrower than the body.
        XCTAssertLessThan(g.width(at: 0.5), nine.dimensions.bullet * 0.7)
        XCTAssertEqual(g.width(at: -1), 0)
        XCTAssertEqual(g.width(at: nine.outline.height + 1), 0)
    }

    func testWidthOfBottleneckCase() throws {
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        let g = OutlineGeometry(gp11.outline)
        let h = gp11.outline.height
        let neckY = h - gp11.dimensions.caseLength + 2
        XCTAssertEqual(g.width(at: neckY), gp11.dimensions.neck, accuracy: 0.3)
        XCTAssertEqual(g.width(at: h - 10), gp11.dimensions.base, accuracy: 0.6)
    }

    func testContains() throws {
        let nine = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let g = OutlineGeometry(nine.outline)
        let mid = nine.outline.width / 2
        XCTAssertTrue(g.contains(Point(x: mid, y: 20)))
        XCTAssertTrue(g.contains(Point(x: mid, y: 2)))
        XCTAssertFalse(g.contains(Point(x: 0.1, y: 0.1)))
        XCTAssertFalse(g.contains(Point(x: mid, y: nine.outline.height + 1)))
    }

    func testEveryOutlineParses() {
        for c in CartridgeCatalog.all {
            let g = OutlineGeometry(c.outline)
            XCTAssertFalse(g.polygons.isEmpty, c.name)
            XCTAssertGreaterThan(g.width(at: c.outline.height * 0.6), 0, c.name)
        }
    }
}
