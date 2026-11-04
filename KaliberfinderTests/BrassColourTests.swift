import XCTest
@testable import Kaliberfinder

/// The outline's colour tells brass from lead (Raven, 2026-11-04): a brass object is never a lead
/// ball, Minié bullet or air gun pellet. And a piece Vision cuts off an object is joined back to it.
final class BrassColourTests: XCTestCase {
    private func image(_ rgb: (Float, Float, Float), width w: Int = 20, height h: Int = 10) -> RGBImage {
        RGBImage(width: w, height: h, pixels: (0..<(w * h)).flatMap { _ in [rgb.0, rgb.1, rgb.2] })
    }

    private let everyPixel = (0..<10).flatMap { y in (0..<20).map { x in Point(x: Double(x), y: Double(y)) } }

    func testBrassIsYellowLeadAndNickelAreGreyCopperIsRed() {
        XCTAssertTrue(PhotoAnalyzer.isBrass(image((180, 155, 95)), points: everyPixel), "polished brass")
        XCTAssertTrue(PhotoAnalyzer.isBrass(image((92, 84, 62)), points: everyPixel), "brass in shade")
        XCTAssertFalse(PhotoAnalyzer.isBrass(image((120, 122, 125)), points: everyPixel), "lead")
        XCTAssertFalse(PhotoAnalyzer.isBrass(image((200, 200, 205)), points: everyPixel), "nickel")
        XCTAssertFalse(PhotoAnalyzer.isBrass(image((170, 95, 80)), points: everyPixel), "copper")
        XCTAssertFalse(PhotoAnalyzer.isBrass(image((180, 155, 95)), points: []), "nothing measured")
    }

    func testOnlyTheOutlineCounts() {
        var pixels = image((120, 122, 125)).pixels
        for y in 0..<10 { for x in 0..<5 { let i = (y * 20 + x) * 3; pixels[i] = 180; pixels[i + 1] = 155; pixels[i + 2] = 95 } }
        let picture = RGBImage(width: 20, height: 10, pixels: pixels)
        XCTAssertTrue(PhotoAnalyzer.isBrass(picture, points: everyPixel.filter { $0.x < 5 }))
        XCTAssertFalse(PhotoAnalyzer.isBrass(picture, points: everyPixel.filter { $0.x >= 5 }))
    }

    func testBrassLeavesOutLeadBallsAndPellets() throws {
        let ball = try XCTUnwrap(ShapeMatcher.catalogue[".36 Rundkugel (.375)"])
        let lead = Matcher.rank(shape: ball, limit: .max)
        XCTAssertTrue(lead.contains { !$0.cartridge.hasCase }, "a grey ball is compared with the balls")
        let brass = Matcher.rank(shape: ball, brass: true, limit: .max)
        XCTAssertTrue(brass.allSatisfy(\.cartridge.hasCase), brass.map(\.cartridge.id).joined(separator: ", "))
        // Cartridges with a case are unaffected.
        let nine = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        XCTAssertEqual(Matcher.rank(shape: nine, brass: true).map(\.cartridge.id), Matcher.rank(shape: nine).map(\.cartridge.id))
    }

    // MARK: - Pieces of one object

    func testPieceTouchingTheCartridgeIsJoinedToIt() throws {
        let w = 100, h = 100
        var labels = [Int](repeating: 0, count: w * h)
        // 1: the case body; 2: the star crimp, cut off by Vision, touching it.
        for y in 40..<60 { for x in 30..<50 { labels[y * w + x] = 1 } }
        for y in 42..<58 { for x in 50..<62 { labels[y * w + x] = 2 } }
        let pieces = SubjectPicker.instances(labels: labels, width: w)
        XCTAssertEqual(SubjectPicker.objectCount(pieces, width: w, height: h), 2, "before: two cartridges")
        let joined = SubjectPicker.joiningParts(pieces, labels: labels, width: w, height: h)
        XCTAssertEqual(joined.count, 1)
        let picked = try XCTUnwrap(SubjectPicker.pickInstance(joined, width: w, height: h))
        XCTAssertEqual(picked.labels, IndexSet([1, 2]))
        XCTAssertEqual(picked.count, 400 + 192)
        XCTAssertEqual(picked.bounds, ColorSegmenter.Box(x0: 30, y0: 40, x1: 61, y1: 59))
        XCTAssertEqual(SubjectPicker.objectCount(joined, width: w, height: h), 1)
    }

    func testTwoCartridgesTouchingStaySeparate() {
        let w = 100, h = 100
        var labels = [Int](repeating: 0, count: w * h)
        for y in 20..<26 { for x in 30..<60 { labels[y * w + x] = 1 } }
        for y in 26..<32 { for x in 32..<60 { labels[y * w + x] = 2 } }
        let joined = SubjectPicker.joiningParts(SubjectPicker.instances(labels: labels, width: w), labels: labels, width: w, height: h)
        XCTAssertEqual(joined.map(\.label), [1, 2])
        XCTAssertEqual(SubjectPicker.objectCount(joined, width: w, height: h), 2)
    }

    func testTheBoardIsNotJoinedToTheCartridge() {
        let w = 100, h = 100
        var labels = [Int](repeating: 0, count: w * h)
        // The board touches the frame, so it is no candidate; the cartridge lies on it.
        for y in 0..<h { for x in 0..<50 { labels[y * w + x] = 1 } }
        for y in 40..<46 { for x in 50..<70 { labels[y * w + x] = 2 } }
        let joined = SubjectPicker.joiningParts(SubjectPicker.instances(labels: labels, width: w), labels: labels, width: w, height: h)
        XCTAssertEqual(joined.map(\.labels), [IndexSet([1]), IndexSet([2])])
        XCTAssertEqual(SubjectPicker.pick(joined, width: w, height: h), 2)
    }
}
