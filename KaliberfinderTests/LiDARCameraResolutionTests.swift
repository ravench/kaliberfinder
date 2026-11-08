import AVFoundation
import XCTest
@testable import Kaliberfinder

/// The LiDAR camera asks for the largest photo its format can give (48 MP on the Pro phones since the
/// 14 Pro): the second look cuts the cartridge out of the full-size photo.
final class LiDARCameraResolutionTests: XCTestCase {
    func testTheLargestPhotoSizeIsTaken() {
        let sizes = [CMVideoDimensions(width: 4032, height: 3024), CMVideoDimensions(width: 8064, height: 6048),
                     CMVideoDimensions(width: 1920, height: 1440)]
        XCTAssertEqual(LiDARCamera.largest(sizes).width, 8064)
        XCTAssertEqual(LiDARCamera.largest([]).width, 0, "a format that names no photo size counts as the smallest")
    }

    func testTheSeriesSummaryShowsTheMegapixels() {
        let shot = CaptureShot(photo: "photo.heic", source: "lidarCamera", captured: Date())
        XCTAssertTrue(TrainingPackageView.summary("01", shot, pixels: (8064, 6048)).contains("49 MP"))
        XCTAssertTrue(TrainingPackageView.summary("01", shot, pixels: (4032, 3024)).contains("12 MP"))
        XCTAssertTrue(TrainingPackageView.summary("01", shot).contains("  –  "), "no photo to read")
    }

    func testThePhotoPixelsAreReadFromTheFile() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Captures", withExtension: nil))
        let example = root.appendingPathComponent("9x19-mm-example/01")
        let shot = try TrainingCapture.decoder.decode(CaptureShot.self, from: Data(contentsOf: example.appendingPathComponent("shot.json")))
        let pixels = try XCTUnwrap(CaptureStore.photoPixels(of: shot, at: example))
        XCTAssertGreaterThan(pixels.width, 0)
        XCTAssertGreaterThan(pixels.height, 0)
    }
}
