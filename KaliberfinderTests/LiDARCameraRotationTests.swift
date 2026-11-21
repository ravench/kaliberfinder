import AVFoundation
import XCTest
@testable import Kaliberfinder

/// The LiDAR camera's preview and photos turn with the screen, which an iPad does; a phone stays
/// in portrait, where the camera image is turned by 90°, as before. The scanner itself is not on the
/// simulator: only what runs without it is tested here.
@MainActor
final class LiDARCameraRotationTests: XCTestCase {
    func testPortraitUntilTheScreenSaysOtherwise() {
        XCTAssertEqual(LiDARCamera().rotationAngle, 90)
    }

    func testPreviewLayerShowsTheCamerasSession() {
        let camera = LiDARCamera()
        let layer = AVCaptureVideoPreviewLayer()
        camera.attach(previewLayer: layer)
        XCTAssertTrue(layer.session === camera.session)
        // Without a device (no scanner on the simulator) there is nothing to coordinate yet.
        XCTAssertEqual(camera.rotationAngle, 90)
    }

    func testGuidanceSpeaksOfTheDevice() {
        // The English «device» is checked in tools/test_translations.py.
        XCTAssertEqual(LiDARGuidance.tilted.title, "Gerät parallel zum Tisch halten")
    }
}
