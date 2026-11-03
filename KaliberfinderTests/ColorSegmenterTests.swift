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

    // MARK: - Several cartridges in one photo

    func testOneCartridgeCountsAsOne() throws {
        let nine = try cartridge("9x19 mm")
        XCTAssertEqual(ColorSegmenter.objectCount(photo(nine)), 1)
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        XCTAssertEqual(ColorSegmenter.objectCount(photo(gp11, angle: 1.2, pixelsPerMM: 5)), 1)
    }

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
    func testRealPhotosShowOneCartridge() throws {
        for name in ["photo-9x19-wood", "photo-45acp-wood", "photo-9x19-diagonal"] {
            let rgb = try XCTUnwrap(PhotoAnalyzer.rgbImage(XCTUnwrap(realPhoto(name).cgImage)), name)
            XCTAssertEqual(ColorSegmenter.objectCount(rgb), 1, name)
        }
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

    func testRealPhotosWithASecondCartridgeShowTwo() throws {
        for name in ["photo-9x19-wood", "photo-45acp-wood"] {
            let rgb = try XCTUnwrap(PhotoAnalyzer.rgbImage(XCTUnwrap(realPhoto(name).cgImage)), name)
            XCTAssertEqual(ColorSegmenter.objectCount(withSecondCopy(rgb)), 2, name)
        }
    }

    func testAnalyzerReportsOneCartridgeInARealPhoto() async throws {
        let analysis = await PhotoAnalyzer.analyze(try realPhoto("photo-9x19-wood"))
        XCTAssertNotNil(analysis.shape)
        XCTAssertEqual(analysis.objectCount, 1)
        XCTAssertFalse(analysis.hasSeveralObjects)
        let diagonal = await PhotoAnalyzer.analyze(try realPhoto("photo-9x19-diagonal"))
        XCTAssertFalse(diagonal.hasSeveralObjects, "\(diagonal.objectCount)")
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
        var analysis = PhotoAnalysis(shape: nil, texts: [])
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
            let top = Matcher.rank(shape: shape, hits: [], limit: 8).map(\.cartridge.id)
            XCTAssertTrue(top.contains(".45 ACP"), "\(top)")
        }
    }

    func testASingleCartridgeIsOutlinedToo() async throws {
        let analysis = await PhotoAnalyzer.analyze(try realPhoto("photo-9x19-wood"))
        XCTAssertFalse(analysis.hasSeveralObjects)
        let subject = try XCTUnwrap(analysis.subject)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(subject), "\(subject)")
        // A cartridge, not the board: a small part of the photo.
        XCTAssertLessThan(subject.width * subject.height, 0.2, "\(subject)")
        XCTAssertGreaterThan(subject.width * subject.height, 0.001, "\(subject)")
        let outlines = MatchesView.outlines(for: analysis, chosen: nil)
        XCTAssertEqual(outlines.frames, [subject])
        XCTAssertEqual(outlines.selected, 0)
    }

    func testOutlinesForSeveralOrNoCartridges() {
        XCTAssertTrue(MatchesView.outlines(for: nil, chosen: nil).frames.isEmpty)
        // Nothing measured: no frame, even with a stray box.
        let nothing = PhotoAnalysis(shape: nil, texts: [], subject: CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1))
        XCTAssertTrue(MatchesView.outlines(for: nothing, chosen: nil).frames.isEmpty)
        // Several: all of them while picking, then the picked one highlighted.
        let boxes = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1)]
        let several = PhotoAnalysis(shape: nil, texts: [], candidates: boxes, subject: boxes[0])
        XCTAssertEqual(MatchesView.outlines(for: several, chosen: nil).frames, boxes)
        XCTAssertNil(MatchesView.outlines(for: several, chosen: nil).selected)
        XCTAssertEqual(MatchesView.outlines(for: several, chosen: 1).selected, 1)
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
}
