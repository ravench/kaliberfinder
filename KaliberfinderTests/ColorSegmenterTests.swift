import XCTest
import UIKit
@testable import Kaliberfinder

/// Finding the cartridge when Vision takes the table, a box or the paper as the subject (SCAN-05).
final class ColorSegmenterTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// A synthetic photo: wood-like stripes, a shadow over the lower half, a dark box cut off by the
    /// top edge, and a brass cartridge with a copper bullet lying at `angle`, `pixelsPerMM` px/mm.
    private func photo(_ c: Cartridge, angle: Double = 0.3, pixelsPerMM: Double = 6,
                       width: Int = 600, height: Int = 800) -> RGBImage {
        var p = [Float](repeating: 0, count: width * height * 3)
        var seed: UInt64 = 42
        func noise() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        let stripes = (0..<width).map { _ in noise() * 40 }
        for y in 0..<height {
            for x in 0..<width {
                let shade: Float = y > height * 7 / 10 && x > width / 4 ? 0.6 : 1
                let grain = stripes[x] + noise() * 10
                var rgb: [Float] = [205 + grain, 185 + grain, 155 + grain].map { $0 * shade }
                if y < 60, x > width / 3, x < width * 5 / 6 { rgb = [30, 30, 28] }
                for c in 0..<3 { p[(y * width + x) * 3 + c] = rgb[c] }
            }
        }
        let g = OutlineGeometry(c.outline)
        let bulletEnd = c.outline.height - c.dimensions.caseLength
        let cx = Double(width) / 2, cy = Double(height) / 2
        let half = max(c.outline.height, c.outline.width) * pixelsPerMM
        for y in Int(cy - half)...Int(cy + half) {
            for x in Int(cx - half)...Int(cx + half) {
                // Back to cartridge millimetres: rotate by -angle around the centre.
                let dx = Double(x) - cx, dy = Double(y) - cy
                let u = (dx * cos(angle) + dy * sin(angle)) / pixelsPerMM + c.outline.width / 2
                let v = (-dx * sin(angle) + dy * cos(angle)) / pixelsPerMM + c.outline.height / 2
                guard x >= 0, y >= 0, x < width, y < height, g.contains(Point(x: u, y: v)) else { continue }
                let rgb: [Float] = v < bulletEnd ? [190, 110, 70] : [200, 160, 60]
                let light = Float(0.8 + 0.4 * abs(u / c.outline.width - 0.5))
                for k in 0..<3 { p[(y * width + x) * 3 + k] = min(255, rgb[k] * light) }
            }
        }
        return RGBImage(width: width, height: height, pixels: p)
    }

    func testFindsTheCartridgeOnWoodWithShadowAndABox() throws {
        let nine = try cartridge("9x19 mm")
        let points = try XCTUnwrap(ColorSegmenter.segment(photo(nine)))
        let measured = try XCTUnwrap(ShapeMatcher.measureWithLength(points))
        XCTAssertEqual(measured.shape.aspect, nine.dimensions.overallLength / nine.dimensions.base, accuracy: 0.3)
        // Length in pixels: 29.7 mm at 6 px/mm.
        XCTAssertEqual(measured.length, 29.7 * 6, accuracy: 12)
        let ids = Matcher.rank(shape: measured.shape, hits: [], limit: 5).map(\.cartridge.id)
        XCTAssertTrue(ids.contains(nine.id), "\(ids)")
    }

    func testFindsARifleCartridge() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let points = try XCTUnwrap(ColorSegmenter.segment(photo(gp11, angle: 1.2, pixelsPerMM: 5)))
        let shape = try XCTUnwrap(ShapeMatcher.measure(points))
        XCTAssertEqual(shape.aspect, gp11.dimensions.overallLength / gp11.dimensions.base, accuracy: 0.5)
    }

    func testPlainImageHasNoCartridge() {
        let plain = RGBImage(width: 200, height: 300, pixels: [Float](repeating: 180, count: 200 * 300 * 3))
        XCTAssertNil(ColorSegmenter.segment(plain))
    }

    func testHolesAreFilled() {
        // A 5×5 ring with a hole in the middle.
        var mask = [Bool](repeating: false, count: 49)
        for y in 1...5 { for x in 1...5 where x == 1 || x == 5 || y == 1 || y == 5 { mask[y * 7 + x] = true } }
        let filled = ColorSegmenter.fillHoles(mask, width: 7, height: 7)
        XCTAssertTrue(filled[3 * 7 + 3])
        XCTAssertFalse(filled[0])
        XCTAssertEqual(filled.filter { $0 }.count, 25)
    }

    func testOtsuSplitsTwoGroups() {
        let values = [Float](repeating: 10, count: 100) + [Float](repeating: 90, count: 30)
        let t = ColorSegmenter.otsu(values)
        XCTAssertGreaterThanOrEqual(t, 10)
        XCTAssertLessThan(t, 90)
    }

    // MARK: - Vision instances

    func testPickerSkipsTableBoxAndPaper() {
        let w = 100, h = 100
        var labels = [Int](repeating: 0, count: w * h)
        // 1: the board, filling most of the frame and touching the edges.
        for y in 0..<h { for x in 0..<80 { labels[y * w + x] = 1 } }
        // 2: a box cut off by the top edge.
        for y in 0..<10 { for x in 85..<99 { labels[y * w + x] = 2 } }
        // 3: the cartridge, inside the frame.
        for y in 40..<46 { for x in 85..<95 { labels[y * w + x] = 3 } }
        let instances = SubjectPicker.instances(labels: labels, width: w)
        XCTAssertEqual(instances.map(\.label), [1, 2, 3])
        XCTAssertEqual(instances.last?.count, 60)
        XCTAssertEqual(instances.last?.bounds, ColorSegmenter.Box(x0: 85, y0: 40, x1: 94, y1: 45))
        XCTAssertEqual(SubjectPicker.pick(instances, width: w, height: h), 3)
        XCTAssertNil(SubjectPicker.pick(Array(instances.prefix(2)), width: w, height: h))
    }

    func testPickerSkipsAHugeInstanceInsideTheFrame() {
        let w = 10, h = 10
        var labels = [Int](repeating: 0, count: w * h)
        for y in 1..<9 { for x in 1..<9 { labels[y * w + x] = 1 } }
        XCTAssertNil(SubjectPicker.pick(SubjectPicker.instances(labels: labels, width: w), width: w, height: h))
    }

    // MARK: - Real photos

    /// Raven's photos from 2026-11-03: Vision took the board as the subject, so no cartridge was found.
    private func realPhoto(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    func testRealPhotosFindHandgunCalibres() throws {
        for (name, id) in [("photo-9x19-wood", "9x19 mm"), ("photo-45acp-wood", ".45 ACP")] {
            let image = try realPhoto(name)
            let rgb = try XCTUnwrap(PhotoAnalyzer.rgbImage(XCTUnwrap(image.cgImage)), name)
            let points = try XCTUnwrap(ColorSegmenter.segment(rgb), name)
            let (sampled, step) = PhotoAnalyzer.thinned(points)
            let shape = try XCTUnwrap(ShapeMatcher.measure(sampled, pixelSize: Double(step)), name)
            XCTAssertFalse(shape.isEndView, name)
            XCTAssertEqual(shape.aspect, 2.85, accuracy: 0.35, name)
            let top = Matcher.rank(shape: shape, hits: [], limit: 8)
            XCTAssertTrue(top.contains { $0.cartridge.id == id }, "\(name): \(top.map(\.cartridge.id))")
            let handgun = CartridgeCatalog.Category.handgun.rawValue
            XCTAssertTrue(top.prefix(5).allSatisfy { $0.cartridge.category == handgun }, "\(name): \(top.map(\.cartridge.id))")
        }
    }

    func testAnalyzerFindsTheCartridgeInARealPhoto() async throws {
        let analysis = await PhotoAnalyzer.analyze(try realPhoto("photo-45acp-wood"))
        let shape = try XCTUnwrap(analysis.shape)
        XCTAssertFalse(shape.isEndView)
        XCTAssertNotNil(analysis.lengthPixels)
    }

    func testThinningKeepsAtMostMaxPoints() {
        let points = (0..<200).flatMap { y in (0..<400).map { x in Point(x: Double(x), y: Double(y)) } }
        let (thin, step) = PhotoAnalyzer.thinned(points)
        XCTAssertGreaterThan(step, 1)
        XCTAssertLessThanOrEqual(thin.count, PhotoAnalyzer.maxPoints)
        XCTAssertEqual(PhotoAnalyzer.thinned(Array(points.prefix(100))).step, 1)
    }
}
