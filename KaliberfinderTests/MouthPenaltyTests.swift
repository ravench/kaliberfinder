import XCTest
@testable import Kaliberfinder

/// Where the photo's colours show the case mouth (`CaseMouth`), matching counts the case's share of
/// the length and, with LiDAR, the case's length in mm (`Matcher.mouthPenalty`), each capped.
final class MouthPenaltyTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// The mouth of `c`, as a fraction of the length from the tip.
    private func mouth(_ c: Cartridge) -> Double { 1 - c.dimensions.caseLength / c.dimensions.overallLength }

    /// 9x19 mm and 9x21 mm look alike from the side (same length and width); only the 9x21's case is
    /// 2 mm longer, its bullet seated that much deeper. The mouth moves each the cap's way, no more.
    func testCaseLengthMovesNineParaAndNineByTwentyOne() throws {
        let para = try cartridge("9x19 mm"), imi = try cartridge("9x21 mm IMI")
        let nine = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        func distance(_ id: String, mouth: Double?) throws -> Double {
            try XCTUnwrap(Matcher.rank(shape: nine, mouth: mouth, mode: .cartridge, cartridges: [para, imi], limit: .max)
                .first { $0.cartridge.id == id }?.shapeDistance)
        }
        XCTAssertEqual(try distance(para.id, mouth: mouth(para)), try distance(para.id, mouth: nil), accuracy: 1e-12, "own mouth costs nothing")
        XCTAssertEqual(try distance(imi.id, mouth: mouth(imi)), try distance(imi.id, mouth: nil), accuracy: 1e-12)
        for (id, other) in [(imi.id, para), (para.id, imi)] {
            let added = try distance(id, mouth: mouth(other)) - distance(id, mouth: nil)
            XCTAssertGreaterThan(added, 0, id)
            XCTAssertLessThanOrEqual(added, Matcher.mouthCap, id)
        }
        // Both stay listed: the mouth only orders them.
        XCTAssertEqual(Matcher.rank(shape: nine, mouth: mouth(imi), mode: .cartridge, cartridges: [para, imi], limit: .max).count, 2)
    }

    /// Within the tolerance nothing, beyond it in proportion, up to the cap; with LiDAR the case's length too.
    func testMouthCountsBeyondItsToleranceUpToTheCap() throws {
        let para = try cartridge("9x19 mm")
        let share = para.dimensions.caseLength / para.dimensions.overallLength
        XCTAssertEqual(Matcher.mouthPenalty(1 - share, para, size: nil), 0)
        XCTAssertEqual(Matcher.mouthPenalty(1 - share - Matcher.shareTolerance, para, size: nil), 0, accuracy: 1e-12)
        XCTAssertEqual(Matcher.mouthPenalty(1 - share - Matcher.shareTolerance - 0.01, para, size: nil), Matcher.shareWeight * 0.01, accuracy: 1e-12)
        XCTAssertEqual(Matcher.mouthPenalty(0.1, para, size: nil), Matcher.mouthCap)
        // The right size with the right mouth costs nothing; a mouth at the wrong place at most twice the cap.
        let size = MeasuredSize(length: para.dimensions.overallLength / Matcher.lengthScaleWhole, diameter: para.dimensions.base,
                                lengthError: 0.3, diameterError: 0.2)
        XCTAssertEqual(Matcher.mouthPenalty(1 - share, para, size: size), 0, accuracy: 1e-9)
        XCTAssertEqual(Matcher.mouthPenalty(0.1, para, size: size), 2 * Matcher.mouthCap, accuracy: 1e-12)
    }

    /// A mouth read in the wrong place (a stain, a cannelure, a long silver bullet) costs every calibre at
    /// most the cap: the right one stays first and listed.
    func testAMouthInTheWrongPlaceKeepsTheRightCalibre() throws {
        for id in ["9x19 mm", "7.5x55 mm Swiss (GP 11)", ".45 ACP"] {
            let shape = try XCTUnwrap(ShapeMatcher.catalogue[id], id)
            let first = Matcher.grouped(Matcher.rank(shape: shape, mouth: 0.7, mode: .cartridge, limit: .max)).first
            XCTAssertTrue(first?.items.contains { $0.cartridge.id == id } == true, "\(id): \(first?.lead.cartridge.id ?? "nothing")")
        }
    }

    /// An empty case has no mouth to find: nothing is compared, whatever the photo carries.
    func testEmptyCaseIgnoresTheMouth() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let shape = try XCTUnwrap(ShapeMatcher.caseCatalogue[gp11.id])
        let plain = Matcher.rank(shape: shape, mode: .emptyCase, cartridges: [gp11], limit: 1).first?.shapeDistance
        XCTAssertEqual(Matcher.rank(shape: shape, mouth: 0.3, mode: .emptyCase, cartridges: [gp11], limit: 1).first?.shapeDistance, plain)
    }
}
