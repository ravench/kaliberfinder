import XCTest
@testable import Kaliberfinder

/// Where the photo's colours show the case mouth (`CaseMouth`), matching counts the case's share of
/// the length (Raven 2026-11-07: "we know the case length, use that to improve photo matching").
final class CaseShareTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    private func share(_ c: Cartridge) -> Double { c.dimensions.caseLength / c.outline.height }

    /// The 9x19 mm's outline with the case's share of the length `caseShare`.
    private func nine(caseShare: Double?) throws -> ShapeMeasurement {
        var shape = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        shape.caseShare = caseShare
        return shape
    }

    /// 9x19 mm and 9x21 mm look alike from the side (same length and width); only the 9x21's case is
    /// 2 mm longer, its bullet seated that much deeper.
    func testCaseLengthTellsNineParaFromNineByTwentyOne() throws {
        let para = try cartridge("9x19 mm"), imi = try cartridge("9x21 mm IMI")
        func first(_ caseShare: Double?) throws -> String? {
            Matcher.rank(shape: try nine(caseShare: caseShare), mode: .cartridge, cartridges: [para, imi], limit: .max).first?.cartridge.id
        }
        XCTAssertEqual(try first(nil), para.id, "the outline alone")
        XCTAssertEqual(try first(share(para)), para.id)
        XCTAssertEqual(try first(share(imi)), imi.id)
        // Both stay listed: the case's share only orders them.
        XCTAssertEqual(Matcher.rank(shape: try nine(caseShare: share(imi)), mode: .cartridge, cartridges: [para, imi], limit: .max).count, 2)
    }

    /// Within the tolerance nothing, beyond it in proportion, up to the cap. A round seated shorter than
    /// the catalogue's length shows a larger share: up to `caseShareSeating` more costs nothing either.
    func testCaseShareCountsBeyondItsToleranceUpToTheCap() throws {
        let ratio = 0.65, tolerance = ShapeMatcher.caseShareTolerance, longer = tolerance + ShapeMatcher.caseShareSeating
        func added(_ measured: Double?) throws -> Double {
            ShapeMatcher.caseShareDistance(try nine(caseShare: measured), caseRatio: ratio)
        }
        XCTAssertEqual(try added(nil), 0, "no mouth in the photo")
        XCTAssertEqual(ShapeMatcher.caseShareDistance(try nine(caseShare: 0.7), caseRatio: nil), 0, "no case")
        XCTAssertEqual(try added(ratio - tolerance), 0, accuracy: 1e-12)
        XCTAssertEqual(try added(ratio + longer), 0, accuracy: 1e-12)
        XCTAssertEqual(try added(ratio - tolerance - 0.01), ShapeMatcher.caseShareWeight * 0.01, accuracy: 1e-12)
        XCTAssertEqual(try added(ratio + longer + 0.01), ShapeMatcher.caseShareWeight * 0.01, accuracy: 1e-12)
        XCTAssertEqual(try added(0.2), ShapeMatcher.maxCaseSharePenalty)
        XCTAssertEqual(try added(1), ShapeMatcher.maxCaseSharePenalty)
    }

    /// A mouth read in the wrong place (a stain, a cannelure) costs every calibre about the same: the
    /// right one stays first and listed.
    func testAMouthInTheWrongPlaceKeepsTheRightCalibre() throws {
        for id in ["9x19 mm", "7.5x55 mm Swiss (GP 11)", ".45 ACP"] {
            var shape = try XCTUnwrap(ShapeMatcher.catalogue[id], id)
            shape.caseShare = 0.3
            let first = Matcher.grouped(Matcher.rank(shape: shape, mode: .cartridge, limit: .max)).first
            XCTAssertTrue(first?.items.contains { $0.cartridge.id == id } == true, "\(id): \(first?.lead.cartridge.id ?? "nothing")")
        }
    }

    /// An empty case has no mouth to find: its share is not compared, whatever the shape carries.
    func testEmptyCaseIgnoresTheCaseShare() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        var shape = try XCTUnwrap(ShapeMatcher.caseCatalogue[gp11.id])
        let expected = shape
        let plain = ShapeMatcher.distance(shape, to: expected, part: .emptyCase, caseRatio: share(gp11))
        shape.caseShare = 0.3
        XCTAssertEqual(ShapeMatcher.distance(shape, to: expected, part: .emptyCase, caseRatio: share(gp11)), plain)
    }

    /// The matching's shape takes the case's share from the outline's mouth (a fraction of the length from the tip).
    func testShapeAtAxisCarriesTheMouth() throws {
        let shape = try nine(caseShare: nil)
        let mouth = ShapeContour(points: [], parts: [], mouth: 0.35)
        XCTAssertEqual(try XCTUnwrap(PhotoAnalysis(shape: shape, contour: mouth).shapeAtAxis(depth: nil)?.caseShare), 0.65, accuracy: 1e-12)
        XCTAssertNil(PhotoAnalysis(shape: shape, contour: ShapeContour(points: [], parts: [])).shapeAtAxis(depth: nil)?.caseShare)
        XCTAssertNil(PhotoAnalysis(shape: shape).shapeAtAxis(depth: nil)?.caseShare)
    }
}
