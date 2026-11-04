import XCTest
@testable import Kaliberfinder

/// Choosing the cut-out that looks most like a cartridge (SCAN-05).
final class OutlineScoreTests: XCTestCase {
    private let w = 120, h = 60

    /// A flat grey image with a bright `width` × `height` bar, so its outline has sharp edges.
    private func edges(bar rect: (x: Int, y: Int, width: Int, height: Int)) -> GradientImage {
        var pixels = [Float](repeating: 100, count: w * h * 3)
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) { for c in 0..<3 { pixels[(y * w + x) * 3 + c] = 220 } }
        }
        return GradientImage(RGBImage(width: w, height: h, pixels: pixels))
    }

    private func mask(_ rects: [(x: Int, y: Int, width: Int, height: Int)]) -> [Bool] {
        var m = [Bool](repeating: false, count: w * h)
        for r in rects { for y in r.y..<(r.y + r.height) { for x in r.x..<(r.x + r.width) { m[y * w + x] = true } } }
        return m
    }

    func testAWholeBarOnItsEdgesScoresWell() throws {
        let bar = (x: 20, y: 20, width: 80, height: 20)
        let score = try XCTUnwrap(OutlineScore.score(mask: mask([bar]), width: w, height: h, edges: edges(bar: bar)))
        XCTAssertEqual(score.aspect, 4, accuracy: 0.1)
        XCTAssertEqual(score.symmetry, 1, accuracy: 0.05)
        XCTAssertEqual(score.solidity, 1, accuracy: 0.05)
        XCTAssertGreaterThan(score.edgeStrength, 3)
        XCTAssertEqual(score.size, 1600)
    }

    func testAShadowOnOneSideScoresLower() throws {
        let bar = (x: 20, y: 20, width: 80, height: 20)
        let image = edges(bar: bar)
        let whole = try XCTUnwrap(OutlineScore.score(mask: mask([bar]), width: w, height: h, edges: image))
        // A shadow below the front half: the silhouette is lopsided and part of its outline is soft.
        let shadowed = try XCTUnwrap(OutlineScore.score(mask: mask([bar, (x: 20, y: 40, width: 40, height: 10)]),
                                                        width: w, height: h, edges: image))
        XCTAssertLessThan(shadowed.symmetry, whole.symmetry)
        XCTAssertLessThan(shadowed.value, whole.value)
    }

    func testAPieceOfTheCartridgeScoresLowerThanTheWhole() throws {
        let bar = (x: 20, y: 20, width: 80, height: 20)
        let image = edges(bar: bar)
        let whole = try XCTUnwrap(OutlineScore.score(mask: mask([bar]), width: w, height: h, edges: image))
        let piece = try XCTUnwrap(OutlineScore.score(mask: mask([(x: 20, y: 20, width: 40, height: 20)]), width: w, height: h, edges: image))
        XCTAssertLessThan(piece.value, whole.value)
    }

    func testARoundBlobOrAThreadIsNotACartridge() {
        let image = edges(bar: (x: 20, y: 20, width: 80, height: 20))
        XCTAssertNil(OutlineScore.score(mask: mask([(x: 40, y: 15, width: 30, height: 30)]), width: w, height: h, edges: image))
        XCTAssertNil(OutlineScore.score(mask: mask([(x: 10, y: 30, width: 100, height: 2)]), width: w, height: h, edges: image))
    }

    func testPointsOnAGridScoreLikeTheMask() throws {
        let bar = (x: 20, y: 20, width: 80, height: 20)
        let image = edges(bar: bar)
        let points = stride(from: 20, to: 100, by: 2).flatMap { x in stride(from: 20, to: 40, by: 2).map { Point(x: Double(x), y: Double($0)) } }
        let score = try XCTUnwrap(OutlineScore.score(points: points, step: 2, edges: image))
        XCTAssertEqual(score.aspect, 4, accuracy: 0.1)
        XCTAssertEqual(score.size, 1600)
        XCTAssertGreaterThan(score.edgeStrength, 2)
    }

    func testOpeningRemovesThreadsAndKeepsSolids() {
        // A 5 × 5 square with a one-pixel thread running off to the right.
        let w = 12, h = 7
        var m = [Bool](repeating: false, count: w * h)
        for y in 1...5 { for x in 1...5 { m[y * w + x] = true } }
        for x in 6..<11 { m[3 * w + x] = true }
        let opened = ColorSegmenter.opened(m, width: w, height: h)
        XCTAssertFalse(opened[3 * w + 9])
        XCTAssertTrue(opened[3 * w + 3])
    }

    func testGradientMean() {
        let image = edges(bar: (x: 20, y: 20, width: 80, height: 20))
        XCTAssertEqual(image.mean(x0: 0, y0: 0, x1: 10, y1: 10), 0)
        XCTAssertGreaterThan(image.value(x: 20, y: 30), 100)
        XCTAssertEqual(image.value(x: 60, y: 30), 0)
    }
}
