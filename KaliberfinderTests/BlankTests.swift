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

    /// A blank closed inside the case (9 mm P.A.K., 8 mm and .315 Knall) has no bullet either. It is flagged
    /// like the crimped ones (review 2026-11-13: it was not, so its page listed a bullet diameter and a photo
    /// was compared with its «empty case»), and compared whole in every mode.
    func testBlanksClosedInsideTheCaseAreComparedWhole() throws {
        for id in ["9 mm P.A.K.", "8 mm Knall", ".315 Knall"] {
            XCTAssertEqual(CartridgeCatalog.cartridge(id: id)?.blank, true, id)
            let shape = try XCTUnwrap(ShapeMatcher.catalogue[id])
            for mode in ScanMode.allCases {
                let match = try XCTUnwrap(rank(shape, mode: mode, limit: .max).first { $0.cartridge.id == id }, "\(id), \(mode)")
                XCTAssertEqual(match.part, .cartridge, "\(id), \(mode)")
            }
        }
    }

    /// «Masse eingeben»: a typed bullet diameter was measured on a bullet, so no blank is listed. A blank's
    /// `dimensions.bullet` only repeats its case's diameter, which the 8 mm Knall used to fit exactly.
    func testATypedBulletDiameterLeavesTheBlanksOut() throws {
        let d = try XCTUnwrap(CartridgeCatalog.cartridge(id: "8 mm Knall")).dimensions
        let byCase = DimensionMatcher.rank(MeasuredDimensions(caseLength: d.caseLength, rim: d.rim), cartridges: CartridgeCatalog.all, limit: .max)
        XCTAssertEqual(byCase.first { $0.cartridge.id == "8 mm Knall" }?.fit, .good)
        let withBullet = DimensionMatcher.rank(MeasuredDimensions(caseLength: d.caseLength, rim: d.rim, bullet: d.bullet),
                                               cartridges: CartridgeCatalog.all, limit: .max)
        XCTAssertFalse(withBullet.isEmpty)
        XCTAssertFalse(withBullet.contains { $0.cartridge.blank })
    }
}
