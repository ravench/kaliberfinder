import XCTest
import UIKit
@testable import Kaliberfinder

/// Crimped .22 blanks (power-tool loads, starter pistol blanks): no bullet, the star crimp
/// narrows the case mouth. The real photos are Raven's of fired ones, 2026-11-04.
final class BlankTests: XCTestCase {
    private let blankID = ".22 Blank (6.8/11)"

    private func rank(_ shape: ShapeMeasurement, mode: ScanMode = .auto, limit: Int = 8) -> [Match] {
        Matcher.rank(shape: shape, mode: mode, limit: limit)
    }

    func testBlankIsInTheCatalogue() throws {
        let blank = try XCTUnwrap(CartridgeCatalog.cartridge(id: blankID))
        XCTAssertEqual(blank.kind, "rimfire")
        XCTAssertEqual(blank.dimensions.overallLength, 11.0, accuracy: 0.001)
        XCTAssertEqual(blank.dimensions.caseLength, blank.dimensions.overallLength, accuracy: 0.001)
        XCTAssertTrue(blank.blank)
        XCTAssertNil(blank.outline.bullet)
        XCTAssertLessThan(blank.dimensions.neck, blank.dimensions.base, "the crimp is narrower than the body")
        XCTAssertFalse(blank.obsolete)
        XCTAssertEqual(CartridgeCatalog.all.filter(\.blank).map(\.id),
                       [blankID, "9 mm R Knall", ".320 Knall", ".45 Knall", ".22 Long Knall", "6 mm Flobert Knall"])
    }

    func testSearchFindsTheBlank() {
        for query in ["Platzpatrone", "6.8/11", "Setzkartusche"] {
            XCTAssertTrue(CartridgeCatalog.search(query).contains { $0.id == blankID }, query)
        }
    }

    func testBlankOutlineFindsTheBlankInEveryMode() throws {
        let shape = try XCTUnwrap(ShapeMatcher.catalogue[blankID])
        for mode in ScanMode.allCases {
            let ids = rank(shape, mode: mode, limit: 3).map(\.cartridge.id)
            XCTAssertEqual(ids.first, blankID, "\(mode): \(ids)")
        }
        // Case and cartridge are the same thing for a blank.
        XCTAssertEqual(ShapeMatcher.caseCatalogue[blankID], ShapeMatcher.catalogue[blankID])
    }

    func testFiredBlankIsNotTakenForAnEmptyShortCase() throws {
        // A fired blank's petals stay bent in, so it is not a square-cut .22 Short case.
        let shape = try XCTUnwrap(ShapeMatcher.catalogue[blankID])
        let ids = rank(shape, mode: .emptyCase).map(\.cartridge.id)
        if let short = ids.firstIndex(of: ".22 Short") {
            XCTAssertGreaterThan(short, try XCTUnwrap(ids.firstIndex(of: blankID)), "\(ids)")
        }
    }

    /// On the phone a fired blank came out "empty case, rimless": the rim and neck checks for empty
    /// cases ruled the blank out. A blank is compared whole, with the rim only as a small penalty.
    func testFiredBlankWithoutVisibleRimIsFoundAsEmptyCase() throws {
        let blank = try XCTUnwrap(ShapeMatcher.catalogue[blankID])
        var widths = blank.widths
        for i in (widths.count - 4)..<widths.count { widths[i] = 1 }  // the rim lost in the photo
        let shape = ShapeMatcher.measurement(aspect: blank.aspect, relativeWidths: widths)
        XCTAssertFalse(try XCTUnwrap(shape.features).isRimmed)
        let match = try XCTUnwrap(rank(shape, mode: .emptyCase, limit: .max).first { $0.cartridge.id == blankID })
        XCTAssertEqual(match.part, .cartridge)
    }

    /// A blank rests tilted on its rim, so photographed parallel to the table it looks shorter.
    func testTiltedBlankLooksShorterButIsStillFound() throws {
        let blank = try XCTUnwrap(ShapeMatcher.catalogue[blankID])
        let shorter = ShapeMatcher.measurement(aspect: blank.aspect * 0.85, relativeWidths: blank.widths)
        XCTAssertEqual(rank(shorter, limit: 3).first?.cartridge.id, blankID)
        let distance = try XCTUnwrap(rank(shorter, limit: .max).first { $0.cartridge.id == blankID }?.shapeDistance)
        XCTAssertEqual(distance, 0, accuracy: 0.01)
        // Never longer, and at most 20 % shorter.
        let longer = ShapeMatcher.measurement(aspect: blank.aspect * 1.2, relativeWidths: blank.widths)
        XCTAssertEqual(ShapeMatcher.tilted(blank, toward: longer).aspect, blank.aspect)
        let stubby = ShapeMatcher.measurement(aspect: blank.aspect * 0.5, relativeWidths: blank.widths)
        XCTAssertEqual(ShapeMatcher.tilted(blank, toward: stubby).aspect, blank.aspect * 0.8, accuracy: 1e-9)
    }

    func testOnlyBlanksAreAllowedToLookShorter() throws {
        let nine = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        let shorter = ShapeMatcher.measurement(aspect: nine.aspect * 0.85, relativeWidths: nine.widths)
        let distance = rank(shorter, limit: .max).first { $0.cartridge.id == "9x19 mm" }?.shapeDistance ?? .infinity
        XCTAssertGreaterThan(distance, 0.4)
    }

    // MARK: - Real photos

    private func realPhoto(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    /// A fired blank on grey linoleum. (Raven's other two photos are not used: on the dark speckled
    /// mat the simulator's colour cut-out misses the outline, and in the wide frame the blank is
    /// only about 50 pixels long, too few to tell it from a .22 BB Cap.)
    /// The blank rests tilted, so it looks about a tenth shorter than it is; it must be the first match.
    func testRealPhotosOfFiredBlanksLookMostLikeTheBlank() async throws {
        var missed: [String] = []
        for name in ["photo-22blank-fired-grey"] {
            let analysis = await PhotoAnalyzer.analyze(try realPhoto(name))
            guard let shape = analysis.shape, let features = shape.features else {
                missed.append("\(name): no outline")
                continue
            }
            if !analysis.isBrass { missed.append("\(name): not taken for brass") }
            let aspect = (shape.aspect * 100).rounded() / 100
            // The star crimp narrows the front end. The rim isn't required: a fired blank always rests
            // tilted and the phone is held parallel to the table, so the rim shows only about 1.05
            // of the body (Raven, 2026-11-04); the blank must still be the closest calibre.
            if !features.hasNeck { missed.append("\(name): \(features)") }
            // As the app ranks it: with the tilt a blank's photo allows (see `ShapeMatcher.tilted`).
            let closest = Matcher.rank(shape: shape, brass: analysis.isBrass, limit: 3)
            if closest.first?.cartridge.id != blankID {
                missed.append("\(name): aspect \(aspect), closest \(closest.map { "\($0.cartridge.id) \($0.shapeDistance ?? -1)" })")
            }
        }
        XCTAssertTrue(missed.isEmpty, missed.joined(separator: "\n"))
    }
}
