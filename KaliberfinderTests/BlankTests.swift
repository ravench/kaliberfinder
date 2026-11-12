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
}
