import CoreGraphics
import XCTest
@testable import Kaliberfinder

/// Vision's silhouette often leaves out a cartridge's dark side, the strip of brass that mirrors
/// something dark (training shots 9x19-mm-20261106-223004, night-time photos on light oak): `DarkSide`
/// gives it back where the photo shows no edge there and the side ends nearer the bullet tip's axis.
final class DarkSideTests: XCTestCase {
    private let table: [Float] = [200, 175, 140]
    private let brass: [Float] = [200, 160, 60]
    private let copper: [Float] = [190, 110, 70]
    private let black: [Float] = [12, 9, 5]

    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// A 600 × 600 px photo of `c` (or only its case, `ppm` pixels per millimetre) lying in the middle at
    /// `angle` on a light table. The metal more
    /// than `darkFrom` of the case's half width off the axis on one side is nearly black; next to that side the
    /// table lies in a shadow `shadow` mm wide, at `shadowLevel` of its brightness. With the pixels the
    /// cartridge covers (`whole`) and the ones Vision keeps when it stops in the black strip, `cutFrom`
    /// of the half width off the axis, along the case (`cut`; along the bullet too with `cutBullet`).
    private func photo(_ c: Cartridge, darkFrom: Double = 0.3, cutFrom: Double = 0.5, shadow: Double = 0, shadowLevel: Float = 0.3,
                       caseOnly: Bool = false, cutBullet: Bool = false, darkMetal: Bool = true,
                       angle: Double = 0.7, ppm: Double = 6) -> (image: RGBImage, whole: [Point], cut: [Point]) {
        let size = 600
        let g = OutlineGeometry(c.outline, includeBullet: !caseOnly)
        let axis = c.outline.width / 2
        // The half width at each tenth of a millimetre along the outline.
        let half = stride(from: 0.05, to: c.outline.height, by: 0.1).map { v -> Double in
            var inside = 0.0, outside = axis + 1
            for _ in 0..<20 {
                let u = (inside + outside) / 2
                if g.contains(Point(x: axis + u, y: v)) { inside = u } else { outside = u }
            }
            return inside
        }
        let bulletEnd = c.outline.height - c.dimensions.caseLength
        var pixels = [Float](repeating: 0, count: size * size * 3)
        var whole: [Point] = [], cut: [Point] = []
        let cosine = cos(angle), sine = sin(angle)
        for y in 0..<size {
            for x in 0..<size {
                // Back to the outline's millimetres (u across, v from the tip), turned by -angle about its middle.
                let dx = (Double(x) + 0.5 - 300) / ppm, dy = (Double(y) + 0.5 - 300) / ppm
                let u = axis + dx * cosine + dy * sine, v = c.outline.height / 2 - dx * sine + dy * cosine
                let inside = u > -1 && v > -1 && u < c.outline.width + 1 && v < c.outline.height + 1 && g.contains(Point(x: u, y: v))
                var colour = table
                if inside {
                    // Along the bullet, the strip goes on as at the case mouth (in photos it doesn't reach the tip).
                    let isBullet = !caseOnly && v < bulletEnd, radius = half[max(Int(bulletEnd * 10), min(half.count - 1, Int(v * 10)))]
                    colour = darkMetal && u - axis > darkFrom * radius ? black : isBullet ? copper : brass
                    whole.append(Point(x: Double(x), y: Double(y)))
                    if u - axis <= cutFrom * radius || (isBullet && !cutBullet) { cut.append(Point(x: Double(x), y: Double(y))) }
                } else if shadow > 0, u > axis, v > 0, v < c.outline.height, u - axis < half[min(half.count - 1, Int(v * 10))] + shadow {
                    colour = table.map { $0 * shadowLevel }
                }
                for k in 0..<3 { pixels[(y * size + x) * 3 + k] = colour[k] }
            }
        }
        return (RGBImage(width: size, height: size, pixels: pixels), whole, cut)
    }

    private func aspect(_ points: [Point]) throws -> Double {
        try XCTUnwrap(ShapeMatcher.measure(points)).aspect
    }

    func testGivesBackTheCutDarkSide() throws {
        for (id, angle) in [("9x19 mm", 0.7), ("9x19 mm", 2.5), (".45 ACP", 4.0), ("7.5x55 mm Swiss (GP 11)", 0.2)] {
            let name = "\(id) at \(angle)"
            let shot = photo(try cartridge(id), angle: angle)
            let truth = try aspect(shot.whole)
            XCTAssertGreaterThan(try aspect(shot.cut) / truth, 1.15, "Vision's cut makes it look thinner: \(name)")
            let restored = try XCTUnwrap(DarkSide.restored(shot.cut, step: 1, photo: shot.image), name)
            XCTAssertEqual(try aspect(restored) / truth, 1, accuracy: 0.03, name)
        }
    }

    func testAlsoWhenTheBulletIsCut() throws {
        let shot = photo(try cartridge("9x19 mm"), cutBullet: true)
        let restored = try XCTUnwrap(DarkSide.restored(shot.cut, step: 1, photo: shot.image))
        XCTAssertEqual(try aspect(restored) / aspect(shot.whole), 1, accuracy: 0.03)
    }

    /// The black strip runs into the cartridge's shadow: the photo can't say where the metal ends, the
    /// mirror image of the lit side can.
    func testNotIntoTheShadowBesideTheDarkSide() throws {
        let shot = photo(try cartridge("9x19 mm"), shadow: 2)
        let restored = try XCTUnwrap(DarkSide.restored(shot.cut, step: 1, photo: shot.image))
        XCTAssertEqual(try aspect(restored) / aspect(shot.whole), 1, accuracy: 0.03)
    }

    /// The table's brightness halfway back beyond the cut edge bounds the side: a shadow lighter than half
    /// the table counts as table.
    func testNotPastWhereTheTableShows() throws {
        let shot = photo(try cartridge("9x19 mm"), shadow: 2, shadowLevel: 0.6)
        let restored = try XCTUnwrap(DarkSide.restored(shot.cut, step: 1, photo: shot.image))
        XCTAssertEqual(try aspect(restored) / aspect(shot.whole), 1, accuracy: 0.03)
    }

    func testLeavesAWholeSilhouetteAlone() throws {
        let shot = photo(try cartridge("9x19 mm"))
        XCTAssertNil(DarkSide.restored(shot.whole, step: 1, photo: shot.image))
    }

    /// Where the photo shows the table (or a lit case) right beyond the edge, the edge is real.
    func testLeavesAnEdgeAloneThatThePhotoShows() throws {
        let lit = photo(try cartridge("9x19 mm"), darkMetal: false)
        let narrower = photo(try cartridge("9x19 mm"))
        XCTAssertNil(DarkSide.restored(narrower.cut, step: 1, photo: lit.image), "brass beyond the edge, brighter than the strip")
        // A shadow beside a lit edge: the case is brighter than the shadow, so the edge is real.
        let shaded = photo(try cartridge("9x19 mm"), darkFrom: 0.97, cutFrom: 1, shadow: 2)
        XCTAssertNil(DarkSide.restored(shaded.whole, step: 1, photo: shaded.image))
    }

    /// An empty case has no bullet tip on its axis to mirror about.
    func testLeavesAnEmptyCaseAlone() throws {
        let shot = photo(try cartridge("9x19 mm"), caseOnly: true)
        XCTAssertGreaterThan(try aspect(shot.cut) / aspect(shot.whole), 1.1)
        XCTAssertNil(DarkSide.restored(shot.cut, step: 1, photo: shot.image))
    }

    /// Points every few pixels, as Vision's mask is sampled for a large cartridge.
    func testSampledSilhouette() throws {
        let shot = photo(try cartridge("9x19 mm"), ppm: 10)
        let sampled = shot.cut.filter { Int($0.x) % 2 == 0 && Int($0.y) % 2 == 0 }
        let restored = try XCTUnwrap(DarkSide.restored(sampled, step: 2, photo: shot.image))
        XCTAssertTrue(restored.allSatisfy { Int($0.x) % 2 == 0 && Int($0.y) % 2 == 0 }, "on the same grid")
        XCTAssertEqual(try XCTUnwrap(ShapeMatcher.measure(restored, pixelSize: 2)).aspect / aspect(shot.whole), 1, accuracy: 0.03)
    }

    /// Fewer than 30 points across: the mirror image would be less exact than the silhouette.
    func testLeavesASmallSilhouetteAlone() throws {
        let shot = photo(try cartridge("9x19 mm"))
        let sampled = shot.cut.filter { Int($0.x) % 2 == 0 && Int($0.y) % 2 == 0 }
        XCTAssertNotNil(DarkSide.restored(shot.cut, step: 1, photo: shot.image))
        XCTAssertNil(DarkSide.restored(sampled, step: 2, photo: shot.image))
    }

    /// The analysis measures Vision's silhouette with its dark side given back.
    func testTheAnalysisMeasuresTheRestoredSilhouette() throws {
        let shot = photo(try cartridge("9x19 mm"))
        let vision = try XCTUnwrap(PhotoAnalyzer.visionResult((shot.cut, 1, []), width: 600, height: 600))
        XCTAssertGreaterThan(vision.shape.aspect / aspect(shot.whole), 1.1)
        let analysis = PhotoAnalyzer.analysis(of: try cgImage(shot.image), vision: vision)
        XCTAssertEqual(try XCTUnwrap(analysis.shape).aspect / aspect(shot.whole), 1, accuracy: 0.03)
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
