import UIKit
import XCTest
@testable import Kaliberfinder

/// Reading the headstamp from a base photo, and a wrongly seen rim on a loaded cartridge.
final class HeadstampImageTests: XCTestCase {
    private let wood: (Float, Float, Float) = (205, 182, 150)
    private let brass: (Float, Float, Float) = (200, 160, 60)

    /// Raven's base photo from 2026-11-03: a .45 ACP ("TBC .45 AUTO") in a tray, small and turned.
    private func basePhoto() throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "base-45acp-tray", withExtension: "jpg"))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path))
    }

    /// A wooden background with a brass disc and, if given, a dark dot.
    private func disc(width: Int = 400, height: Int = 300, cx: Double, cy: Double, radius: Double,
                      dot: (x: Double, y: Double)? = nil) -> RGBImage {
        var p = [Float](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                var c = hypot(px - cx, py - cy) <= radius ? brass : wood
                if let dot, hypot(px - dot.x, py - dot.y) <= 4 { c = (20, 15, 10) }
                let i = (y * width + x) * 3
                p[i] = c.0; p[i + 1] = c.1; p[i + 2] = c.2
            }
        }
        return RGBImage(width: width, height: height, pixels: p)
    }

    func testBrassColours() {
        XCTAssertTrue(HeadstampImage.isBrass(r: brass.0, g: brass.1, b: brass.2))
        XCTAssertTrue(HeadstampImage.isBrass(r: 230, g: 190, b: 90))
        XCTAssertFalse(HeadstampImage.isBrass(r: wood.0, g: wood.1, b: wood.2), "light wood")
        XCTAssertFalse(HeadstampImage.isBrass(r: 128, g: 128, b: 128), "grey")
        XCTAssertFalse(HeadstampImage.isBrass(r: 25, g: 25, b: 25), "black tray")
        XCTAssertFalse(HeadstampImage.isBrass(r: 240, g: 240, b: 235), "paper")
    }

    func testFindsABrassDisc() throws {
        let found = try XCTUnwrap(HeadstampImage.locate(disc(cx: 260, cy: 120, radius: 50)))
        XCTAssertEqual(found.cx, 260, accuracy: 2)
        XCTAssertEqual(found.cy, 120, accuracy: 2)
        XCTAssertEqual(found.radius, 50, accuracy: 2)
    }

    func testPlainWoodHasNoCaseHead() {
        let plain = RGBImage(width: 200, height: 150, pixels: (0..<(200 * 150)).flatMap { _ in [wood.0, wood.1, wood.2] })
        XCTAssertNil(HeadstampImage.locate(plain))
    }

    func testFindsTheCaseHeadInRavensPhoto() throws {
        let cg = try XCTUnwrap(basePhoto().cgImage)
        let rgb = try XCTUnwrap(PhotoAnalyzer.rgbImage(cg))
        let found = try XCTUnwrap(HeadstampImage.locate(rgb))
        // Measured by hand on the 900 × 1200 fixture.
        XCTAssertEqual(found.cx, 418, accuracy: 15)
        XCTAssertEqual(found.cy, 571, accuracy: 15)
        XCTAssertEqual(found.radius, 91, accuracy: 12)
    }

    func testUnwrapPutsTheOuterEdgeOnTopAndGoesClockwise() throws {
        let cx = 200.0, cy = 150.0, radius = 100.0
        // A dark dot straight below the centre (a quarter turn clockwise from the right), at 0.7 of the radius.
        let image = disc(cx: cx, cy: cy, radius: radius, dot: (cx, cy + 0.7 * radius))
        let strip = HeadstampImage.unwrap(image, disc: .init(cx: cx, cy: cy, radius: radius))
        XCTAssertGreaterThanOrEqual(Double(strip.height), HeadstampImage.minStripHeight - 1)
        // The strip runs on past one turn; look in the first turn only.
        let firstTurn = Int(Double(strip.width) / HeadstampImage.turns)
        let darkest = try XCTUnwrap(strip.pixels.indices.filter { $0 % strip.width < firstTurn }
            .min { strip.pixels[$0] < strip.pixels[$1] })
        let column = Double(darkest % strip.width), row = Double(darkest / strip.width)
        let expectedColumn = 0.25 / HeadstampImage.turns * Double(strip.width)
        XCTAssertEqual(column, expectedColumn, accuracy: Double(strip.width) * 0.02)
        let ring = HeadstampImage.outerRadius - HeadstampImage.innerRadius
        let expectedRow = (HeadstampImage.outerRadius - 0.7) / ring * Double(strip.height)
        XCTAssertEqual(row, expectedRow, accuracy: Double(strip.height) * 0.08)
        // Stretched to the full range.
        XCTAssertEqual(strip.pixels.min(), 0)
        XCTAssertEqual(strip.pixels.max(), 255)
    }

    func testHalfTurn() {
        let image = GrayImage(width: 3, height: 2, pixels: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(image.rotatedHalfTurn().pixels, [6, 5, 4, 3, 2, 1])
        XCTAssertEqual(image.rotatedHalfTurn().rotatedHalfTurn(), image)
        XCTAssertNotNil(PhotoAnalyzer.grayCGImage(image))
    }

    func testReadsTheHeadstampInRavensPhoto() throws {
        let result = PhotoAnalyzer.analyzeNow(try basePhoto(), kind: .base)
        let hits = HeadstampReader.hits(in: result.texts)
        XCTAssertTrue(hits.contains { $0.cartridgeID == ".45 ACP" }, "read: \(result.texts)")
    }

    // MARK: - Rim on a loaded cartridge

    /// The .45 ACP as the catalogue expects it, but with a rim where the photo's shadow made one.
    private func acpWithFalseRim() throws -> (photo: ShapeMeasurement, expected: ShapeMeasurement) {
        let expected = try XCTUnwrap(ShapeMatcher.catalogue[".45 ACP"])
        var widths = expected.widths
        widths[widths.count - 1] = 1.15
        widths[widths.count - 2] = 1.12
        let photo = ShapeMatcher.measurement(aspect: expected.aspect, relativeWidths: widths)
        XCTAssertTrue(try XCTUnwrap(photo.features).isRimmed)
        return (photo, expected)
    }

    func testFalseRimOnACartridgeOnlyCostsAPenalty() throws {
        let (photo, expected) = try acpWithFalseRim()
        let plain = ShapeMatcher.distance(photo, expected)
        let withRim = try XCTUnwrap(ShapeMatcher.distance(photo, to: expected, part: .cartridge))
        XCTAssertEqual(withRim, plain + ShapeMatcher.rimPenalty, accuracy: 1e-9)
        // An empty case is still ruled out by a rim that doesn't fit.
        let rimmedCase = try XCTUnwrap(ShapeMatcher.caseCatalogue[".38 Special"])
        let rimlessCase = try XCTUnwrap(ShapeMatcher.caseCatalogue["9x19 mm"])
        XCTAssertNil(ShapeMatcher.distance(rimmedCase, to: rimlessCase, part: .emptyCase))
    }

    /// Raven's screenshot from 2026-11-03: "rimmed", L ≈ 33.5 mm, Ø ≈ 12 mm and no matches at all.
    func testFalseRimStillFindsTheAcp() throws {
        let (photo, _) = try acpWithFalseRim()
        let size = MeasuredSize(length: 33.5, diameter: 12, lengthError: 0.8, diameterError: 0.4)
        let matches = Matcher.rank(shape: photo, hits: [], size: size, mode: .auto)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.prefix(3).contains { $0.cartridge.id == ".45 ACP" }, "\(matches.map(\.cartridge.id))")
    }
}
