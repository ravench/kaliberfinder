import XCTest
import UIKit
@testable import Kaliberfinder

/// Crimped .22 blanks (power-tool loads, starter pistol blanks): no bullet, the star crimp
/// narrows the case mouth. The real photos are Raven's of fired ones, 2026-11-04.
final class BlankTests: XCTestCase {
    private let blankID = ".22 Blank (6.8/11)"

    private func rank(_ shape: ShapeMeasurement, mode: ScanMode = .auto, limit: Int = 8) -> [Match] {
        Matcher.rank(shape: shape, hits: [], mode: mode, limit: limit)
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
        XCTAssertEqual(CartridgeCatalog.all.filter(\.blank).map(\.id), [blankID])
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

    // MARK: - Real photos

    private func realPhoto(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    /// Fired blanks on grey linoleum, the second one small in a wide frame. (Raven's third photo, on a
    /// dark speckled mat, is not cut out correctly by the colour fallback the simulator uses.)
    func testRealPhotosOfFiredBlanksFindTheBlank() async throws {
        var missed: [String] = []
        for name in ["photo-22blank-fired-grey", "photo-22blank-fired-grey-far"] {
            let analysis = await PhotoAnalyzer.analyze(try realPhoto(name))
            guard let shape = analysis.shape else {
                missed.append("\(name): no outline")
                continue
            }
            let ids = rank(shape, limit: 5).map(\.cartridge.id)
            if !ids.contains(blankID) {
                let aspect = (shape.aspect * 100).rounded() / 100
                missed.append("\(name): aspect \(aspect), \(ids), \(String(describing: shape.features))")
            }
        }
        XCTAssertTrue(missed.isEmpty, missed.joined(separator: "\n"))
    }
}
