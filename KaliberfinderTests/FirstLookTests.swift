import CoreGraphics
import UIKit
import XCTest
@testable import Kaliberfinder

/// The first look's cascade: Vision on the whole photo, else on centre crops of the full-size photo
/// and a crop around the most salient object, else the colour cut-out.
final class FirstLookTests: XCTestCase {
    func testCentreCropsComeFirstAndAreCentred() throws {
        let regions = PhotoAnalyzer.cascadeRegions(of: try plain(width: 400, height: 300))
        XCTAssertEqual(Array(regions.prefix(3)), [CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                                                  CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                                                  CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25)])
        // A salient object, if Vision names one, adds a fourth region inside the photo.
        XCTAssertLessThanOrEqual(regions.count, 4)
        for r in regions { XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(r), "\(r)") }
    }

    /// On the simulator Vision finds nothing, so the look runs through every region of the cascade,
    /// cut from the full-size photo, and ends on the colour cut-out of the whole photo. Where Vision
    /// works (the Mac), the whole photo or a crop is enough and the cut-out is never taken.
    func testCascadeCutsEveryRegionBeforeTheColourCutOut() throws {
        let size = CGSize(width: 2400, height: 1800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1).setFill()
            context.fill(CGRect(x: 1050, y: 850, width: 300, height: 100))
        }
        let whole = try XCTUnwrap(image.cgImage)
        var cut: [CGRect] = []
        let analysis = PhotoAnalyzer.firstLook(whole: whole, photoSize: size) { region in
            cut.append(region)
            let pixels = CGRect(x: region.minX * size.width, y: region.minY * size.height,
                                width: region.width * size.width, height: region.height * size.height)
            return whole.cropping(to: pixels)
        }
        XCTAssertNotNil(analysis.shape, "the rod is found one way or another")
        if analysis.byColour {
            XCTAssertEqual(cut, PhotoAnalyzer.cascadeRegions(of: whole), "every region was tried first")
            XCTAssertFalse(analysis.byCrop)
        } else if analysis.byCrop {
            XCTAssertFalse(cut.isEmpty)
            XCTAssertEqual(analysis.imageLongSide, 2400 * (1600 / (cut.last!.width * 2400)), accuracy: 1,
                           "the part's pixels are scaled as a look at the whole photo")
        } else {
            XCTAssertTrue(cut.isEmpty, "Vision found the rod in the whole photo")
        }
    }

    private func plain(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
