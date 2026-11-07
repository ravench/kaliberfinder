import CoreGraphics
import UIKit
import XCTest
@testable import Kaliberfinder

/// The outline's bullet ends at the case mouth, where the photo's colour changes from the bullet's to
/// the case's (Raven 2026-11-07: "Detect the border between case and bullet").
final class CaseMouthTests: XCTestCase {
    private let ppm = 6.0
    private let copper: [Float] = [190, 110, 70]
    private let brass: [Float] = [200, 160, 60]
    private let lead: [Float] = [120, 122, 125]

    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// A 1000 × 1000 px photo of the cartridge (or only its case) lying at `angle` on a grey table, its
    /// bullet (and the case's first `caseFront` mm) in `bullet`'s colour, the rest brass; the pixels it
    /// covers; and where its case mouth is, as a fraction of its length from the tip.
    private func photo(_ c: Cartridge, bullet: [Float], caseOnly: Bool = false, caseFront: Double = 0, angle: Double = 0.7)
        -> (image: RGBImage, points: [Point], mouth: Double) {
        let size = 1000
        let g = OutlineGeometry(c.outline, includeBullet: !caseOnly)
        let bulletEnd = c.outline.height - c.dimensions.caseLength
        var pixels = [Float](repeating: 0, count: size * size * 3)
        for i in 0..<(size * size) { pixels[i * 3] = 128; pixels[i * 3 + 1] = 126; pixels[i * 3 + 2] = 122 }
        var points: [Point] = []
        let cosine = cos(angle), sine = sin(angle)
        for y in 0..<size {
            for x in 0..<size {
                // Back to the outline's millimetres (x across, y from the tip), turned by -angle.
                let dx = (Double(x) + 0.5 - 500) / ppm, dy = (Double(y) + 0.5 - 500) / ppm
                let u = dx * cosine + dy * sine, v = -dx * sine + dy * cosine
                guard u > -1, v > -1, u < c.outline.width + 1, v < c.outline.height + 1, g.contains(Point(x: u, y: v)) else { continue }
                // Lit from one side: darker across the cartridge, the colour itself unchanged.
                let light = Float(0.75 + 0.25 * u / c.outline.width)
                let colour = v < bulletEnd + caseFront ? bullet : brass
                for k in 0..<3 { pixels[(y * size + x) * 3 + k] = colour[k] * light }
                points.append(Point(x: Double(x), y: Double(y)))
            }
        }
        return (RGBImage(width: size, height: size, pixels: pixels), points, bulletEnd / c.outline.height)
    }

    /// The outline of the photo's cartridge, with and without its colours.
    private func outlines(_ photo: (image: RGBImage, points: [Point], mouth: Double), _ name: String) throws
        -> (coloured: ShapeContour, plain: ShapeContour) {
        let box = try XCTUnwrap(ShapeMatcher.orientedBox(photo.points, pixelSize: 1), name)
        let shape = try XCTUnwrap(ShapeMatcher.measure(photo.points, pixelSize: 1), name)
        let coloured = try XCTUnwrap(ShapeContour.polygon(photo.points, pixelSize: 1, shape: shape, box: box, photo: photo.image), name)
        let plain = try XCTUnwrap(ShapeContour.polygon(photo.points, pixelSize: 1, shape: shape, box: box), name)
        return (coloured, plain)
    }

    private func width(_ c: ShapeContour, at corner: Int) -> Double {
        let p = c.points[corner], q = c.points[c.points.count - 1 - corner]
        return hypot(p.x - q.x, p.y - q.y)
    }

    func testBulletEndsWhereItsColourMeetsTheCase() throws {
        let rounds: [(String, Double, ShapeContour.Part)] = [("9x19 mm", 0.7, .body), (".45 ACP", 2.0, .body),
                                                             ("7.5x55 mm Swiss (GP 11)", 0.7, .neck), ("7.5x55 mm Swiss (GP 11)", 0.7 + .pi, .neck)]
        for (id, angle, part) in rounds {
            let name = "\(id) at \(angle)"
            let shot = photo(try cartridge(id), bullet: copper, angle: angle)
            let (outline, plain) = try outlines(shot, name)
            XCTAssertEqual(outline.mouth ?? -1, shot.mouth, accuracy: 0.015, name)
            XCTAssertNil(plain.mouth, "without the photo: \(name)")
            XCTAssertNotNil(outline.nose, name)
            // Each side: the bullet (nose and straight part), the step out at the mouth, then the case.
            let n = outline.points.count, b = outline.parts.prefix(while: { $0 == .bullet }).count
            XCTAssertEqual(outline.parts.count, n, name)
            XCTAssertGreaterThanOrEqual(b, NoseCurve.segments, name)
            XCTAssertEqual(outline.parts[b], .end, name)
            XCTAssertEqual(outline.parts[b + 1], part, name)
            XCTAssertEqual(outline.parts.filter { $0 == .bullet }.count, 2 * b, name)
            XCTAssertEqual(outline.parts.filter { $0 == .end }.count, 4, "tip, head and the mouth on each side: \(name)")
            // The bullet's corner at the mouth and the case's lie across from each other, the bullet no wider.
            let bulletCorner = outline.points[b], caseCorner = outline.points[b + 1]
            XCTAssertLessThan(hypot(bulletCorner.x - caseCorner.x, bulletCorner.y - caseCorner.y), 0.1 * width(outline, at: b + 1), name)
            XCTAssertLessThanOrEqual(width(outline, at: b), width(outline, at: b + 1) + 1e-9, name)
            // The line across at the mouth, from the case's corner there on one side to the other's.
            XCTAssertEqual(try XCTUnwrap(outline.mouthLine, name), [outline.points[b + 1], outline.points[n - 2 - b]], name)
            XCTAssertNil(plain.mouthLine, name)
            // The mouth lies on the silhouette: no corner far off it.
            for corner in outline.points {
                let nearest = shot.points.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? .infinity
                XCTAssertLessThan(nearest / ppm, 1, name)
            }
        }
    }

    /// A round nose still narrowing at the mouth (Raven's 9 mm on the simulator, 2026-11-07) runs on under
    /// the case: the outline follows it up to the mouth, not a slimmer pointed curve cut flat at the tip.
    /// Its bullet may be as wide as the case, or narrower.
    func testRoundNoseRunsOnUnderTheCase() throws {
        let mouth = 0.36, bins = ShapeMatcher.bins
        for (length, base, caseHalf) in [(0.475, 0.477, 0.48), (0.5, 0.465, 0.5)] {
            let curve = NoseCurve(kind: .round, cut: 1, length: length, base: base), name = "\(curve)"
            let w = (0..<bins).map { (Double($0) + 0.5) / Double(bins) < mouth ? 2 * curve.half(at: Double($0 + 1) / Double(bins)) : 2 * caseHalf }
            let (nose, corners) = ShapeContour.bullet(upTo: mouth, widths: w, caseHalf: caseHalf)
            XCTAssertEqual(nose?.kind, .round, name)
            XCTAssertGreaterThan(try XCTUnwrap(nose, name).length, mouth, name)
            // Each corner on the bullet's curve: the nose's, then the last at the mouth, where the step out starts.
            XCTAssertEqual(corners.map { $0.part }, Array(repeating: ShapeContour.Part.bullet, count: NoseCurve.segments) + [.end], name)
            XCTAssertEqual(corners.last?.f, mouth, name)
            for corner in corners {
                XCTAssertEqual(corner.half, curve.half(at: corner.f), accuracy: 0.01, "\(name): \(corner)")
            }
        }
    }

    func testLeadBulletMeetsTheCaseToo() throws {
        let shot = photo(try cartridge("9x19 mm"), bullet: lead)
        XCTAssertEqual(try outlines(shot, "lead").coloured.mouth ?? -1, shot.mouth, accuracy: 0.015)
    }

    func testNoMouthWhereTheColourDoesNotChange() throws {
        let shot = photo(try cartridge("9x19 mm"), bullet: brass)
        let (outline, plain) = try outlines(shot, "brass bullet")
        XCTAssertNil(outline.mouth)
        XCTAssertEqual(outline, plain)
    }

    func testEmptyCaseLooksForNoMouth() throws {
        // A reddish neck (annealed, or lacquered) is no bullet: an empty case shows none in front of its
        // neck, so no mouth is looked for.
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let shot = photo(gp11, bullet: copper, caseOnly: true, caseFront: gp11.dimensions.caseLength / 4)
        let (outline, plain) = try outlines(shot, "empty GP 11")
        XCTAssertNil(outline.nose)
        XCTAssertNil(outline.mouth)
        XCTAssertEqual(outline, plain)
    }

    func testEmptyCaseOutlineDropsTheMouthStep() throws {
        let shot = photo(try cartridge("9x19 mm"), bullet: copper)
        let outline = try outlines(shot, "9 mm").coloured
        let empty = outline.withoutBullet()
        XCTAssertEqual(empty.parts, [.body, .end, .body, .end])
        XCTAssertNil(empty.nose)
        XCTAssertNil(empty.mouth)
        XCTAssertNil(empty.mouthLine)
        // The flat mouth sits where the tip was, as wide as the case at its mouth.
        func middle(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
        let n = outline.points.count, tip = middle(outline.points[0], outline.points[n - 1])
        let mouth = middle(empty.points[0], empty.points[3])
        XCTAssertEqual(mouth.x, tip.x, accuracy: 1e-6)
        XCTAssertEqual(mouth.y, tip.y, accuracy: 1e-6)
        let b = outline.parts.prefix(while: { $0 == .bullet }).count + 1
        XCTAssertEqual(width(empty, at: 0), width(outline, at: b), accuracy: 1e-6)
    }

    /// With the developer switch the Matches photo draws a line across at the mouth: on a cartridge only,
    /// not on an empty case or while the user picks one of several (Raven 2026-11-07).
    func testMatchesDrawTheMouthLineOnACartridgeOnly() throws {
        let shot = photo(try cartridge("9x19 mm"), bullet: copper)
        let outline = try outlines(shot, "9 mm").coloured
        let line = try XCTUnwrap(outline.mouthLine)
        let analysis = PhotoAnalysis(shape: ShapeMatcher.catalogue["9x19 mm"], contour: outline)
        XCTAssertEqual(MatchesView.mouthLine(measured: analysis, picking: false), line)
        XCTAssertNil(MatchesView.mouthLine(measured: analysis, picking: false, mode: .emptyCase))
        XCTAssertNil(MatchesView.mouthLine(measured: analysis, picking: true))
        // In fractions of the photo, as the outline.
        let fraction = outline.map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) }
        XCTAssertEqual(fraction.mouthLine, line.map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) })
    }

    /// The phone's path with Vision's object: the outline is drawn again with the photo's colours.
    func testVisionsOutlineEndsTheBulletAtTheMouth() throws {
        let shot = photo(try cartridge("9x19 mm"), bullet: copper)
        let vision = try XCTUnwrap(PhotoAnalyzer.visionResult((points: shot.points, step: 1, boxes: []), width: 1000, height: 1000))
        XCTAssertNil(vision.contour?.mouth, "without the photo")
        let analysis = PhotoAnalyzer.analysis(of: try cgImage(shot.image), vision: vision)
        let contour = try XCTUnwrap(analysis.contour)
        XCTAssertEqual(contour.mouth ?? -1, shot.mouth, accuracy: 0.015)
        // In fractions of the photo, on the cartridge.
        XCTAssertTrue(contour.points.allSatisfy { (0.3...0.95).contains($0.x) && (0.3...0.95).contains($0.y) }, "\(contour.points)")
    }

    /// Raven's 9 mm on wood (the colour cut-out on the simulator): the copper bullet ends about a third
    /// of the way from the tip (19.15 mm case in a 29.7 mm round).
    func testMouthOnRavensPhoto() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "photo-9x19-wood", withExtension: "jpg"))
        let analysis = await PhotoAnalyzer.analyze(try XCTUnwrap(UIImage(contentsOfFile: url.path)))
        let contour = try XCTUnwrap(analysis.contour)
        let mouth = try XCTUnwrap(contour.mouth, "\(contour.parts)")
        XCTAssertEqual(mouth, 1 - 19.15 / 29.7, accuracy: 0.08)
        // Matching counts the case's share of the length (`shapeAtAxis`): it puts the 9 mm no lower than the
        // outline alone (as testRealPhotosShowOneHandgunCartridge ranks it).
        let outlineOnly = try XCTUnwrap(analysis.shape)
        var withCase = outlineOnly
        withCase.caseShare = try XCTUnwrap(analysis.shapeAtAxis(depth: nil)?.caseShare)
        XCTAssertEqual(try XCTUnwrap(withCase.caseShare), 1 - mouth, accuracy: 1e-12)
        func row(_ s: ShapeMeasurement) -> Int? { Matcher.rank(shape: s, limit: .max).firstIndex { $0.cartridge.id == "9x19 mm" } }
        let plain = try XCTUnwrap(row(outlineOnly), "outline alone")
        XCTAssertLessThanOrEqual(try XCTUnwrap(row(withCase), "case \(1 - mouth)"), plain, "case \(1 - mouth)")
        let b = contour.parts.prefix(while: { $0 == .bullet }).count
        XCTAssertEqual(contour.parts[b], .end)
        XCTAssertEqual(contour.parts[b + 1], .body)
        // The bullet's curve follows the cut-out's slices in front of the mouth.
        let nose = try XCTUnwrap(contour.nose), w = try XCTUnwrap(analysis.shape).widths
        let bins = Double(w.count)
        for i in w.indices where (Double(i) + 0.5) / bins < min(nose.length, mouth) {
            let half = nose.half(at: min(Double(i + 1) / bins, nose.length))
            XCTAssertEqual(half, w[i] / 2, accuracy: 0.035, "slice \(i) of \(w), \(nose)")
        }
    }

    private func cgImage(_ rgb: RGBImage) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: rgb.width * rgb.height * 4)
        for i in 0..<(rgb.width * rgb.height) {
            for c in 0..<3 { bytes[i * 4 + c] = UInt8(max(0, min(255, rgb.pixels[i * 3 + c]))) }
        }
        let context = try XCTUnwrap(CGContext(data: &bytes, width: rgb.width, height: rgb.height, bitsPerComponent: 8,
                                              bytesPerRow: rgb.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
