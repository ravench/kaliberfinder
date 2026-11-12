import UIKit
import XCTest
@testable import Kaliberfinder

/// The second look: the cartridge the first look found, cut out of the full-size photo and
/// analysed again, so Vision's mask (or the colour cut-out) covers it at a finer scale.
final class SecondLookTests: XCTestCase {
    private let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// A measured analysis whose frame is the box `frame` (fractions of the photo).
    private func analysis(frame: CGRect, longSide: Double = 1600, candidates: [CGRect] = []) throws -> PhotoAnalysis {
        let shape = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
        return PhotoAnalysis(shape: shape, lengthPixels: 300, imageLongSide: longSide, candidates: candidates, outline: corners)
    }

    func testTheRegionIsTheFrameWithTheFocusMargin() throws {
        let first = try analysis(frame: CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.05))
        let region = try XCTUnwrap(PhotoAnalyzer.secondLookRegion(of: first))
        XCTAssertEqual(region.minX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(region.minY, 0.35, accuracy: 1e-9)
        XCTAssertEqual(region.width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(region.height, 0.25, accuracy: 1e-9)
    }

    func testNoSecondLookWithoutACartridgeOrWhenItFillsThePhoto() throws {
        XCTAssertNil(PhotoAnalyzer.secondLookRegion(of: PhotoAnalysis(shape: nil)))
        var unframed = try analysis(frame: CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.05))
        unframed.outline = nil
        XCTAssertNil(PhotoAnalyzer.secondLookRegion(of: unframed))
        XCTAssertNil(PhotoAnalyzer.secondLookRegion(of: try analysis(frame: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))),
                     "the region would be the whole photo")
        XCTAssertNotNil(PhotoAnalyzer.secondLookRegion(of: try analysis(frame: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.05))),
                        "a long cartridge across the photo still gains in the other direction")
    }

    /// A 4032 × 3024 photo whose left upper quarter was analysed at 1600 px: frames go back into the
    /// whole photo, and sizes compare with the whole photo's long side at 1600 / 2016 of full size.
    func testThePartIsMeasuredInTheWholePhoto() throws {
        let region = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        var part = try analysis(frame: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), candidates: [unit])
        part.contour = ShapeContour(points: [CGPoint(x: 0.5, y: 0.5)], parts: [.end])
        let whole = PhotoAnalyzer.inPhoto(part, region: region, photoSize: CGSize(width: 4032, height: 3024))
        XCTAssertEqual(whole.imageLongSide, 4032 * 1600 / 2016, accuracy: 1e-6)
        XCTAssertEqual(whole.lengthPixels, 300, "pixels of the part as analysed")
        XCTAssertEqual(whole.outline?.first?.x ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(whole.outline?.last?.y ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(whole.contour?.points, [CGPoint(x: 0.25, y: 0.25)])
        XCTAssertTrue(whole.candidates.isEmpty)
    }

    func testTheSecondLookReplacesTheFirstOnTheSameCartridge() throws {
        let competitors = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1)]
        let first = try analysis(frame: CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.05), candidates: competitors)
        var second = try analysis(frame: CGRect(x: 0.42, y: 0.46, width: 0.16, height: 0.03), longSide: 3200)
        second.isBrass = true
        let looked = PhotoAnalyzer.secondLook(first, then: second)
        XCTAssertEqual(looked.outline, second.outline)
        XCTAssertEqual(looked.imageLongSide, 3200)
        XCTAssertTrue(looked.isBrass)
        XCTAssertEqual(looked.candidates, competitors, "the cartridges to pick from stay the first look's")
    }

    func testTheFirstLookStaysWhenTheSecondFindsNothingOrSomethingElse() throws {
        let first = try analysis(frame: CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.05))
        XCTAssertEqual(PhotoAnalyzer.secondLook(first, then: PhotoAnalysis(shape: nil)).outline, first.outline)
        let beside = try analysis(frame: CGRect(x: 0.62, y: 0.45, width: 0.1, height: 0.05))
        XCTAssertEqual(PhotoAnalyzer.secondLook(first, then: beside).outline, first.outline, "another object in the margin")
        var cutOut = try analysis(frame: CGRect(x: 0.42, y: 0.46, width: 0.16, height: 0.03))
        cutOut.byColour = true
        XCTAssertEqual(PhotoAnalyzer.secondLook(first, then: cutOut).outline, first.outline, "the colour cut-out never replaces Vision")
        var firstByColour = first
        firstByColour.byColour = true
        XCTAssertEqual(PhotoAnalyzer.secondLook(firstByColour, then: cutOut).outline, firstByColour.outline,
                       "nor a cut-out: it can pick a piece of the cartridge")
        let vision = try analysis(frame: CGRect(x: 0.42, y: 0.46, width: 0.16, height: 0.03))
        XCTAssertEqual(PhotoAnalyzer.secondLook(firstByColour, then: vision).outline, vision.outline, "Vision improves a cut-out")
    }

    func testNoSecondLookWhileSeveralCartridgesCompete() throws {
        let competitors = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1)]
        XCTAssertNil(PhotoAnalyzer.secondLookRegion(of: try analysis(frame: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
                                                                     candidates: competitors)))
    }

    func testAFrameContainsItsInsideOnly() {
        let turned = [CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.1, y: 0.5)]
        XCTAssertTrue(PhotoAnalyzer.contains(turned, CGPoint(x: 0.5, y: 0.5)))
        XCTAssertTrue(PhotoAnalyzer.contains(Array(turned.reversed()), CGPoint(x: 0.5, y: 0.5)), "either way round")
        XCTAssertFalse(PhotoAnalyzer.contains(turned, CGPoint(x: 0.15, y: 0.15)))
    }

    /// A 4000 × 3000 photo of a small brass-coloured rod, looked at in the part around it (the second
    /// look's crop, also the pick of one of several cartridges): it is analysed at full size, so sizes
    /// compare with the whole photo at full size (the whole photo is analysed at 1600 px), and its frame
    /// lies on the rod in the whole photo. On the simulator the cut-out stands in for Vision.
    func testALargePhotoIsLookedAtInThePartAtFullSize() async throws {
        let size = CGSize(width: 2400, height: 1800)
        let rod = CGRect(x: 1080, y: 840, width: 180, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.45, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1).setFill()
            context.fill(rod)
        }
        let whole = await PhotoAnalyzer.analyze(image)
        XCTAssertEqual(whole.imageLongSide, 1600, accuracy: 1, "a cut-out takes no second look")
        let rodBox = CGRect(x: rod.minX / size.width, y: rod.minY / size.height, width: rod.width / size.width, height: rod.height / size.height)
        let region = try XCTUnwrap(PhotoAnalyzer.focusRegion(around: whole.outline ?? []))
        XCTAssertTrue(region.contains(rodBox), "the second look's part holds the rod")
        let analysis = await PhotoAnalyzer.analyze(image, focusingOn: rodBox)
        XCTAssertEqual(analysis.imageLongSide, size.width, accuracy: 1, "measured in the full-size part")
        XCTAssertEqual(try XCTUnwrap(analysis.lengthPixels), rod.width, accuracy: 8)
        XCTAssertEqual(try XCTUnwrap(analysis.shape?.aspect), 3, accuracy: 0.2)
        let outline = try XCTUnwrap(analysis.outline)
        let centre = CGPoint(x: outline.map(\.x).reduce(0, +) / 4 * size.width, y: outline.map(\.y).reduce(0, +) / 4 * size.height)
        XCTAssertEqual(centre.x, rod.midX, accuracy: 6)
        XCTAssertEqual(centre.y, rod.midY, accuracy: 6)
    }

    /// The real .45 ACP photo goes through both looks: the frame still lies on the cartridge and
    /// sizes still refer to the whole photo (1200 px, analysed unscaled).
    func testARealPhotoGetsTheSecondLook() async throws {
        let analysis = try await RealPhotos.analysis("photo-45acp-wood")
        let shape = try XCTUnwrap(analysis.shape)
        XCTAssertEqual(shape.aspect, 2.7, accuracy: 0.3)
        XCTAssertEqual(analysis.imageLongSide, 1200, accuracy: 1)
        let outline = try XCTUnwrap(analysis.outline)
        XCTAssertTrue(outline.allSatisfy { unit.insetBy(dx: -0.01, dy: -0.01).contains($0) }, "\(outline)")
        XCTAssertTrue(Matcher.rank(shape: shape).map(\.cartridge.id).contains(".45 ACP"))
    }
}
