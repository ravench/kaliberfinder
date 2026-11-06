import XCTest
import UIKit
@testable import Kaliberfinder

/// Finding the cartridge when Vision takes the table, a box or the paper as the subject (SCAN-05).
final class ColorSegmenterTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// A cartridge drawn into a synthetic photo, centred at fractions of the width and height.
    private struct Placed {
        let cartridge: Cartridge
        let angle: Double
        let pixelsPerMM: Double
        let centre: (Double, Double)

        init(_ cartridge: Cartridge, angle: Double, pixelsPerMM: Double, at centre: (Double, Double)) {
            self.cartridge = cartridge
            self.angle = angle
            self.pixelsPerMM = pixelsPerMM
            self.centre = centre
        }
    }

    /// A synthetic photo: wood-like stripes, a shadow over the lower half, a dark box cut off by the
    /// top edge, and a brass cartridge with a copper bullet lying at `angle`, `pixelsPerMM` px/mm,
    /// once at each of `centres` (fractions of the width and height), plus the `also` cartridges.
    private func photo(_ c: Cartridge, angle: Double = 0.3, pixelsPerMM: Double = 6,
                       width: Int = 600, height: Int = 800, centres: [(Double, Double)] = [(0.5, 0.5)],
                       also: [Placed] = []) -> RGBImage {
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
        for item in centres.map({ Placed(c, angle: angle, pixelsPerMM: pixelsPerMM, at: $0) }) + also {
            let c = item.cartridge, angle = item.angle, pixelsPerMM = item.pixelsPerMM
            let g = OutlineGeometry(c.outline)
            let bulletEnd = c.outline.height - c.dimensions.caseLength
            let half = max(c.outline.height, c.outline.width) * pixelsPerMM
            let cx = Double(width) * item.centre.0, cy = Double(height) * item.centre.1
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
        }
        return RGBImage(width: width, height: height, pixels: p)
    }

    func testFindsTheCartridgeOnWoodWithShadowAndABox() throws {
        let nine = try cartridge("9x19 mm")
        let image = photo(nine)
        let points = try XCTUnwrap(ColorSegmenter.best(image)?.points)
        let measured = try XCTUnwrap(ShapeMatcher.measureWithLength(points))
        XCTAssertEqual(measured.shape.aspect, nine.dimensions.overallLength / nine.dimensions.base, accuracy: 0.3)
        // Length in pixels: 29.7 mm at 6 px/mm.
        XCTAssertEqual(measured.length, 29.7 * 6, accuracy: 12)
        let ids = Matcher.rank(shape: measured.shape, limit: 5).map(\.cartridge.id)
        XCTAssertTrue(ids.contains(nine.id), "\(ids)")
        XCTAssertEqual(ColorSegmenter.objectCount(image), 1)
    }

    func testFindsARifleCartridge() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let image = photo(gp11, angle: 1.2, pixelsPerMM: 5)
        let points = try XCTUnwrap(ColorSegmenter.best(image)?.points)
        let shape = try XCTUnwrap(ShapeMatcher.measure(points))
        XCTAssertEqual(shape.aspect, gp11.dimensions.overallLength / gp11.dimensions.base, accuracy: 0.5)
        XCTAssertEqual(ColorSegmenter.objectCount(image), 1)
    }

    func testPlainImageHasNoCartridge() {
        let plain = RGBImage(width: 200, height: 300, pixels: [Float](repeating: 180, count: 200 * 300 * 3))
        XCTAssertNil(ColorSegmenter.best(plain))
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

    /// Raven's photos from 2026-11-03: a 9 mm and a .45 ACP on wood, where Vision took the board as
    /// the subject, and a 9 mm lying diagonally next to a dark chair and a table edge. Real photos
    /// through the phone's own path (Vision's mask) are the golden set's job (GoldenSetTests).
    private func realPhoto(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    /// The 9 mm photo through the analysis (the colour cut-out on the simulator): one cartridge,
    /// handgun calibres as the matches, and the frame exactly around the measured silhouette.
    /// (The .45 ACP photo is checked the same way in testAnalyzerOffersBothCartridgesAndMeasuresThePickedOne.)
    func testRealPhotosShowOneHandgunCartridge() async throws {
        for (name, id) in [("photo-9x19-wood", "9x19 mm")] {
            let analysis = await PhotoAnalyzer.analyze(try realPhoto(name))
            XCTAssertFalse(analysis.hasSeveralObjects, "\(name): \(analysis.candidates)")
            let shape = try XCTUnwrap(analysis.shape, name)
            XCTAssertFalse(shape.isEndView, name)
            XCTAssertNotNil(analysis.lengthPixels, name)
            XCTAssertEqual(shape.aspect, 2.85, accuracy: 0.35, name)
            let top = Matcher.rank(shape: shape)
            XCTAssertTrue(top.contains { $0.cartridge.id == id }, "\(name): \(top.map(\.cartridge.id))")
            let handgun = CartridgeCatalog.Category.handgun.rawValue
            XCTAssertTrue(top.prefix(5).allSatisfy { $0.cartridge.category == handgun }, "\(name): \(top.map(\.cartridge.id))")
            // The frame: four corners inside the photo, around a small part of it (a cartridge, not the board).
            let outline = try XCTUnwrap(analysis.outline, name)
            XCTAssertEqual(outline.count, 4, name)
            let unit = CGRect(x: -0.01, y: -0.01, width: 1.02, height: 1.02)
            XCTAssertTrue(outline.allSatisfy { unit.contains($0) }, "\(name): \(outline)")
            let box = try XCTUnwrap(MatchesView.detectedBoxes(analysis).first, name)
            XCTAssertLessThan(box.width * box.height, 0.2, "\(name): \(box)")
            XCTAssertGreaterThan(box.width * box.height, 0.001, "\(name): \(box)")
            // The frame is exactly what was measured.
            let frames = MatchesView.frames(overview: analysis, measured: analysis, picking: false)
            XCTAssertTrue(frames.candidates.isEmpty, name)
            XCTAssertEqual(frames.measured, outline, name)
        }
    }

    func testThinningKeepsAtMostMaxPoints() {
        let points = (0..<200).flatMap { y in (0..<400).map { x in Point(x: Double(x), y: Double(y)) } }
        let (thin, step) = PhotoAnalyzer.thinned(points)
        XCTAssertGreaterThan(step, 1)
        XCTAssertLessThanOrEqual(thin.count, PhotoAnalyzer.maxPoints)
        XCTAssertEqual(PhotoAnalyzer.thinned(Array(points.prefix(100))).step, 1)
    }

    // MARK: - Several cartridges in one photo

    func testTwoCartridgesAreCounted() throws {
        let nine = try cartridge("9x19 mm")
        XCTAssertEqual(ColorSegmenter.objectCount(photo(nine, centres: [(0.3, 0.45), (0.7, 0.6)])), 2)
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        XCTAssertEqual(ColorSegmenter.objectCount(photo(gp11, angle: 1.2, pixelsPerMM: 5, centres: [(0.5, 0.35), (0.5, 0.65)])), 2)
    }

    func testACartridgeOffInACornerIsIgnored() throws {
        // Clearly not the subject: measure the one in the middle, no error.
        let nine = try cartridge("9x19 mm")
        XCTAssertEqual(ColorSegmenter.objectCount(photo(nine, centres: [(0.5, 0.5), (0.2, 0.85)])), 1)
    }

    func testDifferentCalibresSideBySideAreCounted() throws {
        // A 9 mm and a GP 11 in the middle: both look like cartridges, so it is unclear which to measure.
        let nine = try cartridge("9x19 mm")
        let gp11 = Placed(try cartridge("7.5x55 mm Swiss (GP 11)"), angle: 1.2, pixelsPerMM: 5, at: (0.5, 0.68))
        XCTAssertEqual(ColorSegmenter.objectCount(photo(nine, centres: [(0.5, 0.3)], also: [gp11])), 2)
    }

    func testPlainImageCountsNothing() {
        let plain = RGBImage(width: 200, height: 300, pixels: [Float](repeating: 180, count: 200 * 300 * 3))
        XCTAssertEqual(ColorSegmenter.objectCount(plain), 0)
    }

    /// Raven's photo from 2026-11-03 (taken from the app screen): one 9 mm lying diagonally, a dark
    /// chair and a table edge on the left, things cut off at the top. It was reported as several cartridges.
    func testDiagonalCartridgeNextToAChairIsOne() throws {
        let rgb = try XCTUnwrap(PhotoAnalyzer.rgbImage(XCTUnwrap(realPhoto("photo-9x19-diagonal").cgImage)))
        XCTAssertEqual(ColorSegmenter.objectCount(rgb), 1)
    }

    /// The middle of the photo copied a quarter of the width to the right, next to the original.
    private func withSecondCopy(_ image: RGBImage) -> RGBImage {
        var p = image.pixels
        let w = image.width, h = image.height, shift = w * 28 / 100
        for y in (h * 3 / 10)..<(h * 7 / 10) {
            for x in (w * 3 / 10)..<(w * 7 / 10) where x + shift < w {
                for c in 0..<3 { p[(y * w + x + shift) * 3 + c] = image.pixels[(y * w + x) * 3 + c] }
            }
        }
        return RGBImage(width: w, height: h, pixels: p)
    }

    func testVisionInstancesCountCartridgesOnly() {
        let w = 100, h = 100
        var labels = [Int](repeating: 0, count: w * h)
        // 1: the board, touching the edges; 2 and 3: two cartridges; 4: a speck of dust;
        // 5: a long thin table edge as big as a cartridge.
        for y in 0..<h { for x in 0..<50 { labels[y * w + x] = 1 } }
        for y in 20..<26 { for x in 60..<80 { labels[y * w + x] = 2 } }
        for y in 60..<65 { for x in 62..<80 { labels[y * w + x] = 3 } }
        labels[90 * w + 90] = 4
        for y in 10..<65 { for x in 52..<54 { labels[y * w + x] = 5 } }
        let instances = SubjectPicker.instances(labels: labels, width: w)
        XCTAssertEqual(SubjectPicker.objectCount(instances, width: w, height: h), 2)
        XCTAssertEqual(SubjectPicker.objectCount(instances.filter { $0.label != 3 }, width: w, height: h), 1)
        XCTAssertEqual(SubjectPicker.objectCount(instances.filter { $0.label == 1 }, width: w, height: h), 0)
    }

    private func rectangle(_ width: Int, _ height: Int, colour: [Float]? = nil) -> Blob {
        var blob = Blob()
        for y in 0..<height { for x in 0..<width { blob.add(x: x, y: y) } }
        blob.colour = colour
        return blob
    }

    func testBlobAspect() {
        XCTAssertEqual(rectangle(10, 10).aspect, 1, accuracy: 0.01)
        XCTAssertEqual(rectangle(30, 10).aspect, 3, accuracy: 0.05)
        XCTAssertEqual(rectangle(10, 30).aspect, 3, accuracy: 0.05)
        XCTAssertEqual(Blob().aspect, 1)
    }

    func testBlobsResembleOnlyWhenSizeShapeAndColourMatch() {
        let brass: [Float] = [110, 70, 25]
        let cartridge = rectangle(30, 10, colour: brass)
        XCTAssertTrue(cartridge.resembles(rectangle(10, 30, colour: brass)))
        XCTAssertTrue(cartridge.resembles(rectangle(36, 12, colour: [105, 75, 30])))
        // Too small, too big, a thin edge, another colour.
        XCTAssertFalse(cartridge.resembles(rectangle(15, 5, colour: brass)))
        XCTAssertFalse(cartridge.resembles(rectangle(60, 20, colour: brass)))
        XCTAssertFalse(cartridge.resembles(rectangle(100, 3, colour: brass)))
        XCTAssertFalse(cartridge.resembles(rectangle(30, 10, colour: [48, 36, 30])))
        // Without colour (Vision instances) only size and shape count.
        XCTAssertTrue(rectangle(30, 10).resembles(rectangle(30, 10, colour: [48, 36, 30])))
    }

    func testOnlyProminentLookalikesCompete() {
        // Three cartridge-like rectangles in a 200 × 200 image: centre, beside it, far corner.
        func placed(_ x0: Int, _ y0: Int) -> Blob {
            var blob = Blob()
            for y in y0..<(y0 + 10) { for x in x0..<(x0 + 30) { blob.add(x: x, y: y) } }
            return blob
        }
        let centre = placed(85, 95), beside = placed(85, 125), corner = placed(5, 185), edge = rectangle(100, 3)
        XCTAssertTrue(centre.competes(beside, width: 200, height: 200))
        XCTAssertFalse(centre.competes(corner, width: 200, height: 200))
        XCTAssertFalse(centre.competes(edge, width: 200, height: 200))
        XCTAssertEqual(Blob.count(competingWith: 0, in: [centre, beside, corner, edge], width: 200, height: 200), 2)
    }

    func testAnalysisWithSeveralObjects() {
        var analysis = PhotoAnalysis(shape: nil)
        XCTAssertFalse(analysis.hasSeveralObjects)
        XCTAssertEqual(analysis.objectCount, 1)
        analysis.candidates = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1)]
        XCTAssertTrue(analysis.hasSeveralObjects)
        XCTAssertEqual(analysis.objectCount, 2)
        XCTAssertFalse(MatchesView.severalObjectsText.isEmpty)
        XCTAssertFalse(MatchesView.severalObjectsHint.isEmpty)
    }

    // MARK: - Picking one of several cartridges

    private func uiImage(_ rgb: RGBImage) throws -> UIImage {
        var bytes = [UInt8](repeating: 255, count: rgb.width * rgb.height * 4)
        for i in 0..<(rgb.width * rgb.height) {
            for c in 0..<3 { bytes[i * 4 + c] = UInt8(max(0, min(255, rgb.pixels[i * 3 + c]))) }
        }
        let context = try XCTUnwrap(CGContext(data: &bytes, width: rgb.width, height: rgb.height, bitsPerComponent: 8,
                                              bytesPerRow: rgb.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return UIImage(cgImage: try XCTUnwrap(context.makeImage()))
    }

    func testCompetitorsComeWithTheMainCartridgeFirst() throws {
        let nine = try cartridge("9x19 mm")
        // The one nearer the centre is measured first.
        let boxes = ColorSegmenter.competitors(photo(nine, centres: [(0.3, 0.45), (0.55, 0.55)]))
        XCTAssertEqual(boxes.count, 2)
        let first = try XCTUnwrap(boxes.first), second = try XCTUnwrap(boxes.last)
        XCTAssertGreaterThan(first.x0 + first.x1, second.x0 + second.x1)
    }

    /// The .45 ACP photo with a copy of its middle beside it: both cartridges are offered, and the
    /// picked one is measured on its own, with its frame placed in the whole photo.
    func testAnalyzerOffersBothCartridgesAndMeasuresThePickedOne() async throws {
        let rgb = try XCTUnwrap(PhotoAnalyzer.rgbImage(XCTUnwrap(realPhoto("photo-45acp-wood").cgImage)))
        let image = try uiImage(withSecondCopy(rgb))
        let overview = await PhotoAnalyzer.analyze(image)
        XCTAssertTrue(overview.hasSeveralObjects)
        XCTAssertEqual(overview.candidates.count, 2)
        for candidate in overview.candidates {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(candidate), "\(candidate)")
            let picked = await PhotoAnalyzer.analyze(image, focusingOn: candidate)
            XCTAssertFalse(picked.hasSeveralObjects)
            let shape = try XCTUnwrap(picked.shape, "\(candidate)")
            XCTAssertFalse(shape.isEndView)
            XCTAssertEqual(shape.aspect, 2.85, accuracy: 0.5, "\(candidate)")
            // Sizes still refer to the whole photo (1200 px long side, analysed unscaled).
            XCTAssertEqual(picked.imageLongSide, 1200, accuracy: 1)
            let top = Matcher.rank(shape: shape).map(\.cartridge.id)
            XCTAssertTrue(top.contains(".45 ACP"), "\(top)")
            // The frame lies on the picked cartridge, not somewhere in the crop's own coordinates.
            let outline = try XCTUnwrap(picked.outline, "\(candidate)")
            let centre = CGPoint(x: outline.reduce(0) { $0 + $1.x } / 4, y: outline.reduce(0) { $0 + $1.y } / 4)
            XCTAssertTrue(candidate.insetBy(dx: -0.02, dy: -0.02).contains(centre), "\(centre) \(candidate)")
        }
    }

    func testTheFrameTurnsWithADiagonalCartridge() async throws {
        // A brass-coloured 150 × 45 px "cartridge" turned by 35° on a grey board.
        let size = CGSize(width: 450, height: 350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 225, y: 175)
            context.cgContext.rotate(by: 35 * .pi / 180)
            UIColor(red: 0.8, green: 0.62, blue: 0.25, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: -75, y: -22.5, width: 150, height: 45), cornerRadius: 10).fill()
        }
        let analysis = await PhotoAnalyzer.analyze(image)
        XCTAssertNotNil(analysis.shape)
        let outline = try XCTUnwrap(analysis.outline)
        let pixels = outline.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let side = hypot(pixels[1].x - pixels[0].x, pixels[1].y - pixels[0].y)
        let other = hypot(pixels[2].x - pixels[1].x, pixels[2].y - pixels[1].y)
        // Turned with the cartridge: about 150 × 45, not an upright box around a diagonal.
        XCTAssertEqual(max(side, other), 150, accuracy: 10)
        XCTAssertEqual(min(side, other), 45, accuracy: 8)
        let edge = side >= other ? (pixels[1].x - pixels[0].x, pixels[1].y - pixels[0].y)
                                 : (pixels[2].x - pixels[1].x, pixels[2].y - pixels[1].y)
        var degrees = atan2(edge.1, edge.0) * 180 / .pi
        if degrees < 0 { degrees += 180 }
        XCTAssertEqual(degrees, 35, accuracy: 3)
    }

    func testOrientedBoxOfARotatedRectangle() throws {
        // A 40 × 10 grid of points turned by 30°, around (100, 50).
        let angle = 30.0 * .pi / 180
        var points: [Point] = []
        for i in 0..<40 {
            for j in 0..<10 {
                let u = Double(i) - 19.5, v = Double(j) - 4.5
                points.append(Point(x: 100 + u * cos(angle) - v * sin(angle), y: 50 + u * sin(angle) + v * cos(angle)))
            }
        }
        let box = try XCTUnwrap(ShapeMatcher.orientedBox(points))
        XCTAssertEqual(box.count, 4)
        let sides = (0..<4).map { k in hypot(box[(k + 1) % 4].x - box[k].x, box[(k + 1) % 4].y - box[k].y) }
        XCTAssertEqual(max(sides[0], sides[1]), 40, accuracy: 1e-6)
        XCTAssertEqual(min(sides[0], sides[1]), 10, accuracy: 1e-6)
        XCTAssertEqual(sides[0], sides[2], accuracy: 1e-6)
        let long = sides[0] > sides[1] ? (box[1].x - box[0].x, box[1].y - box[0].y) : (box[2].x - box[1].x, box[2].y - box[1].y)
        var degrees = atan2(long.1, long.0) * 180 / .pi
        if degrees < 0 { degrees += 180 }
        XCTAssertEqual(degrees, 30, accuracy: 1e-6)
        let cx = box.reduce(0) { $0 + $1.x } / 4, cy = box.reduce(0) { $0 + $1.y } / 4
        XCTAssertEqual(cx, 100, accuracy: 1e-6)
        XCTAssertEqual(cy, 50, accuracy: 1e-6)
        XCTAssertNil(ShapeMatcher.orientedBox(Array(points.prefix(49))))
    }

    func testFramesWhilePickingAndAfterwards() {
        XCTAssertTrue(MatchesView.frames(overview: nil, measured: nil, picking: false).candidates.isEmpty)
        XCTAssertNil(MatchesView.frames(overview: nil, measured: nil, picking: false).measured)
        let corners = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.35, y: 0.2), CGPoint(x: 0.15, y: 0.3)]
        // Nothing measured: no frame, even with a stray outline.
        let nothing = PhotoAnalysis(shape: nil, outline: corners)
        XCTAssertNil(MatchesView.frames(overview: nothing, measured: nothing, picking: false).measured)
        XCTAssertTrue(MatchesView.detectedBoxes(nothing).isEmpty)
        // Several: all of them while picking, then only what was measured.
        let boxes = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1)]
        let several = PhotoAnalysis(shape: nil, candidates: boxes)
        let picking = MatchesView.frames(overview: several, measured: nil, picking: true)
        XCTAssertEqual(picking.candidates, boxes)
        XCTAssertNil(picking.measured)
        XCTAssertEqual(MatchesView.detectedBoxes(several), boxes)
        let shape = ShapeMeasurement(aspect: 3, profile: ShapeMatcher.fractions.map { _ in 1 })
        let picked = PhotoAnalysis(shape: shape, outline: corners)
        let after = MatchesView.frames(overview: several, measured: picked, picking: false)
        XCTAssertTrue(after.candidates.isEmpty)
        XCTAssertEqual(after.measured, corners)
        // One cartridge: the preview crops around the outline's bounds.
        let bounds = try? XCTUnwrap(MatchesView.detectedBoxes(picked).first)
        XCTAssertEqual(bounds?.minX ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(bounds?.minY ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(bounds?.maxX ?? 0, 0.35, accuracy: 1e-9)
        XCTAssertEqual(bounds?.maxY ?? 0, 0.3, accuracy: 1e-9)
    }

    func testPointsFollowTheCroppedPreview() {
        let region = CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        let p = CandidatePhotoView.point(CGPoint(x: 0.45, y: 0.5), in: region, size: CGSize(width: 200, height: 100))
        XCTAssertEqual(p.x, 100, accuracy: 1e-9)
        XCTAssertEqual(p.y, 50, accuracy: 1e-9)
        let whole = CandidatePhotoView.point(CGPoint(x: 0.25, y: 0.5), in: CGRect(x: 0, y: 0, width: 1, height: 1),
                                             size: CGSize(width: 400, height: 300))
        XCTAssertEqual(whole.x, 100, accuracy: 1e-9)
        XCTAssertEqual(whole.y, 150, accuracy: 1e-9)
    }

    func testPreviewIsCroppedToAllCartridgesWithAMargin() throws {
        let size = CGSize(width: 1000, height: 2000)
        XCTAssertNil(MatchesView.previewRegion(around: [], imageSize: size))
        // One cartridge, 100 × 200 px: a margin of 200 px (the larger of half its height and a tenth of 2000 px).
        let one = try XCTUnwrap(MatchesView.previewRegion(around: [CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)], imageSize: size))
        XCTAssertEqual(one.minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(one.maxX, 0.7, accuracy: 1e-9)
        XCTAssertEqual(one.minY, 0.3, accuracy: 1e-9)
        XCTAssertEqual(one.maxY, 0.6, accuracy: 1e-9)
        // Two cartridges far apart: both inside, and the crop stays inside the photo.
        let boxes = [CGRect(x: 0.05, y: 0.1, width: 0.1, height: 0.1), CGRect(x: 0.7, y: 0.5, width: 0.1, height: 0.1)]
        let both = try XCTUnwrap(MatchesView.previewRegion(around: boxes, imageSize: size))
        XCTAssertTrue(boxes.allSatisfy { both.contains($0) }, "\(both)")
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(both), "\(both)")
        XCTAssertEqual(both.minX, 0, accuracy: 1e-9)
    }

    func testOutlinesFollowTheCroppedPreview() {
        let region = CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        let box = CandidatePhotoView.relative(CGRect(x: 0.45, y: 0.5, width: 0.1, height: 0.1), to: region)
        XCTAssertEqual(box.minX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(box.minY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(box.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(box.height, 0.25, accuracy: 1e-9)
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertEqual(CandidatePhotoView.relative(region, to: whole), region)
    }

    func testCroppedImageHasTheRegionsSize() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let cropped = PhotoAnalyzer.cropped(image, to: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(cropped.size.width * cropped.scale, 200, accuracy: 1)
        XCTAssertEqual(cropped.size.height * cropped.scale, 150, accuracy: 1)
    }

    func testFocusRegionAddsAMarginInsideThePhoto() {
        let region = PhotoAnalyzer.focusRegion(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1))
        XCTAssertEqual(region.minX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(region.minY, 0.3, accuracy: 1e-9)
        XCTAssertEqual(region.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(region.height, 0.3, accuracy: 1e-9)
        let corner = PhotoAnalyzer.focusRegion(CGRect(x: 0.9, y: 0, width: 0.1, height: 0.1))
        XCTAssertEqual(corner.minX, 0.85, accuracy: 1e-9)
        XCTAssertEqual(corner.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(corner.maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(corner.height, 0.15, accuracy: 1e-9)
    }

    func testNormalizedBoxes() {
        let rect = PhotoAnalyzer.normalized(ColorSegmenter.Box(x0: 10, y0: 20, x1: 29, y1: 59), width: 100, height: 200)
        XCTAssertEqual(rect.minX, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.2, accuracy: 1e-9)
    }

    func testCandidateOutlineScalesToTheView() {
        let frame = CandidatePhotoView.frame(of: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), in: CGSize(width: 200, height: 400))
        XCTAssertEqual(frame, CGRect(x: 44, y: 194, width: 112, height: 112))
    }

    /// Vision's mask is sampled by the object's size: a handgun cartridge of about 20 000 pixels
    /// keeps every pixel. From the whole 1600 × 1200 photo the step was 7, leaving it 8 or 9
    /// points wide (build 1042).
    func testVisionMaskStepFollowsTheObjectNotThePhoto() {
        XCTAssertEqual(PhotoAnalyzer.maskStep(objectPixels: 20_000), 1)
        XCTAssertEqual(PhotoAnalyzer.maskStep(objectPixels: 160_000), 2)
        XCTAssertEqual(PhotoAnalyzer.maskStep(objectPixels: 1600 * 1200), 7)
    }

    /// The colour cut-out tells a grey patch from a brass one, also under warm light (shelf photo:
    /// the stone 118/103/86, a 9 mm case 92/66/29).
    func testColourCutOutTellsGreyFromBrass() {
        let image = RGBImage(width: 3, height: 1, pixels: [118, 103, 86, 92, 66, 29, 200, 200, 205])
        let box = ColorSegmenter.Box(x0: 0, y0: 0, x1: 3, y1: 1)
        XCTAssertTrue(ColorSegmenter.isGrey(image, [true, false, false], box), "stone")
        XCTAssertFalse(ColorSegmenter.isGrey(image, [false, true, false], box), "brass")
        XCTAssertTrue(ColorSegmenter.isGrey(image, [false, false, true], box), "nickel")
    }
}
