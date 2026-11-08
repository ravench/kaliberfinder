import XCTest
@testable import Kaliberfinder

/// A shotshell has no bullet, so its outline alone reads as an empty case: Raven's crimped 12/70 came out
/// «Leere Hülse» (TestFlight, 2026-11-08). With LiDAR its length tells the parts apart: a crimped shell is a
/// loaded cartridge, a hull whose crimp opened when it was fired is an empty case (`Matcher.shotshellPart`).
final class ShotshellPartTests: XCTestCase {
    private func catalogue(_ id: String = "12/70") throws -> (cartridge: Cartridge, shape: ShapeMeasurement) {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
        return (c, try XCTUnwrap(ShapeMatcher.catalogue[id], id))
    }

    /// A LiDAR size that the matcher reads as `length` mm (`Matcher.lengthScaleWhole`), without perspective.
    private func size(_ length: Double) -> MeasuredSize {
        MeasuredSize(length: length / Matcher.lengthScaleWhole, diameter: 20.6 / Matcher.diameterScale, lengthError: 1, diameterError: 0.3)
    }

    func testACrimpedShellIsALoadedCartridge() throws {
        let (shell, shape) = try catalogue()
        XCTAssertEqual(ScanMode.auto.part(for: shape), .emptyCase, "the outline alone: a flat end, no bullet")
        // Raven's folded-crimp B&P and Clever shells, and the roll-crimped Remington (PR 127).
        for length in [57.8, 58.2, 65.5] {
            let photo = Matcher.Photo(shape: shape, size: size(length))
            XCTAssertEqual(Matcher.shotshellPart(photo, shell), .cartridge, "\(length)")
            XCTAssertEqual(ScanMode.detected(in: shape, size: size(length), first: shell), .cartridge, "\(length)")
        }
    }

    func testAnOpenHullIsAnEmptyCase() throws {
        let (shell, shape) = try catalogue()
        // A fired 12/70 hull opens back to about 70 mm; the border lies 2 mm past the longest crimp (65.9 mm).
        for length in [70.0, 68.0] {
            XCTAssertEqual(Matcher.shotshellPart(Matcher.Photo(shape: shape, size: size(length)), shell), .emptyCase, "\(length)")
            XCTAssertEqual(ScanMode.detected(in: shape, size: size(length), first: shell), .emptyCase, "\(length)")
        }
        XCTAssertEqual(Matcher.shotshellPart(Matcher.Photo(shape: shape, size: size(67.5)), shell), .cartridge)
        XCTAssertEqual(shell.overallLengths.upperBound + Matcher.lengthTolerance, 67.92, accuracy: 0.001)
    }

    func testTheEndRiseIsTakenOutOfTheLength() throws {
        let (shell, shape) = try catalogue()
        // Seen from 20 cm the shell's ends stand up and the outline is a few per cent longer than the shell: a raw
        // 70.5 mm would be an open hull, but at that perspective it is a loaded shell under 67.9 mm.
        let raw = size(70.5)
        XCTAssertEqual(Matcher.shotshellPart(Matcher.Photo(shape: shape, size: raw), shell), .emptyCase)
        let near = Matcher.Photo(shape: shape, size: raw, perspective: 0.1)
        let expected = Matcher.wholeExpected(shell, shape, hasBullet: false)
        let rise = (1 / (1 - expected.front * 0.1) + 1 / (1 - expected.back * 0.1)) / 2
        XCTAssertGreaterThan(rise, 1.02)
        let length = try XCTUnwrap(Matcher.measuredLength(near, expected))
        XCTAssertEqual(length, 70.5 / rise, accuracy: 0.01)
        XCTAssertLessThan(length, shell.overallLengths.upperBound + Matcher.lengthTolerance)
        XCTAssertEqual(Matcher.shotshellPart(near, shell), .cartridge)
    }

    func testWithoutASizeOrAShotshellTheOutlineDecides() throws {
        let (shell, shape) = try catalogue()
        XCTAssertNil(Matcher.shotshellPart(Matcher.Photo(shape: shape), shell))
        XCTAssertEqual(ScanMode.detected(in: shape, first: shell), .emptyCase, "no LiDAR: as the outline reads")
        XCTAssertEqual(ScanMode.detected(in: shape, size: size(58)), .emptyCase, "nothing in the list yet")
        let para = try catalogue("9x19 mm")
        XCTAssertNil(Matcher.shotshellPart(Matcher.Photo(shape: para.shape, size: size(58)), para.cartridge), "a bullet, not a crimp")
        XCTAssertEqual(ScanMode.detected(in: para.shape, size: size(58), first: para.cartridge), ScanMode.detected(in: para.shape))
        let ball = try catalogue(".36 Rundkugel (.375)")
        XCTAssertNil(Matcher.shotshellPart(Matcher.Photo(shape: ball.shape, size: size(11)), ball.cartridge), "an end view")
    }

    /// The detection labels the photo; both parts compare a shotshell as the whole shell, so the list is the same.
    func testTheMatchingDoesNotChangeWithThePart() throws {
        let (shell, shape) = try catalogue()
        for length in [58.0, 70.0] {
            let matches = Matcher.rank(shape: shape, size: size(length), limit: .max)
            let twelve = try XCTUnwrap(matches.first { $0.cartridge.id == shell.id }, "\(length)")
            XCTAssertEqual(twelve.part, .cartridge, "\(length)")
            XCTAssertEqual(matches.map(\.cartridge.id), Matcher.rank(shape: shape, size: size(length), mode: .emptyCase, limit: .max).map(\.cartridge.id), "\(length)")
        }
    }
}
