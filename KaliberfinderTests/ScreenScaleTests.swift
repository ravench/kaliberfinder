import XCTest
@testable import Kaliberfinder

final class ScreenScaleTests: XCTestCase {
    func testKnownModelUsesPublishedDensity() {
        // iPhone 17 Pro: 460 ppi at 3x.
        let r = ScreenScale.resolve(model: "iPhone18,1", nativeScale: 3, calibrated: nil)
        XCTAssertEqual(r.source, .model)
        XCTAssertEqual(r.pointsPerMM, 460 / 25.4 / 3, accuracy: 0.0001)
        // 85.6 mm card is about 517 pt tall on that screen.
        XCTAssertEqual(85.6 * r.pointsPerMM, 516.8, accuracy: 0.2)
    }

    func testMiniUsesNativeScale() {
        // iPhone 13 mini: 476 ppi, rendered at 3x but nativeScale 2.88.
        let r = ScreenScale.resolve(model: "iPhone14,4", nativeScale: 2.88, calibrated: nil)
        XCTAssertEqual(r.pointsPerMM, 476 / 25.4 / 2.88, accuracy: 0.0001)
    }

    func testDisplayZoomChangesPointsPerMM() {
        let standard = ScreenScale.resolve(model: "iPhone16,1", nativeScale: 3, calibrated: nil)
        let zoomed = ScreenScale.resolve(model: "iPhone16,1", nativeScale: 3.5, calibrated: nil)
        XCTAssertLessThan(zoomed.pointsPerMM, standard.pointsPerMM)
    }

    func testCalibrationWins() {
        let r = ScreenScale.resolve(model: "iPhone18,1", nativeScale: 3, calibrated: 6.1)
        XCTAssertEqual(r, ScreenScale.Resolution(pointsPerMM: 6.1, source: .calibrated))
    }

    func testUnknownModelIsAnEstimate() {
        let r = ScreenScale.resolve(model: "iPhone99,9", nativeScale: 3, calibrated: nil)
        XCTAssertEqual(r.source, .estimate)
        XCTAssertEqual(r.pointsPerMM, 460 / 25.4 / 3, accuracy: 0.0001)
        let old = ScreenScale.resolve(model: "iPhone99,9", nativeScale: 2, calibrated: nil)
        XCTAssertEqual(old.pointsPerMM, 326 / 25.4 / 2, accuracy: 0.0001)
        let zero = ScreenScale.resolve(model: "x", nativeScale: 0, calibrated: 0)
        XCTAssertEqual(zero.source, .estimate)
    }

    func testCalibratedRejectsNonsense() {
        XCTAssertEqual(ScreenScale.calibrated(points: 517, millimetres: 85.6) ?? 0, 6.04, accuracy: 0.01)
        XCTAssertNil(ScreenScale.calibrated(points: 0, millimetres: 85.6))
        XCTAssertNil(ScreenScale.calibrated(points: 10_000, millimetres: 85.6))
    }

    func testAllTableEntriesArePlausible() {
        for (model, ppi) in ScreenScale.ppiByModel {
            XCTAssertTrue(model.hasPrefix("iPhone"), model)
            XCTAssertTrue((300...500).contains(ppi), model)
        }
    }

    func testModelIdentifierIsNotEmpty() {
        XCTAssertFalse(ScreenScale.modelIdentifier().isEmpty)
    }

    @MainActor
    func testScaleModelStoresAndResetsCalibration() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ScreenScaleTests"))
        defaults.removePersistentDomain(forName: "ScreenScaleTests")
        let model = ScaleModel(defaults: defaults, model: "iPhone18,1", nativeScale: 3)
        XCTAssertEqual(model.resolution.source, .model)
        model.calibrate(pointsPerMM: 6.2)
        XCTAssertEqual(model.pointsPerMM, 6.2)
        XCTAssertEqual(ScaleModel(defaults: defaults, model: "iPhone18,1", nativeScale: 3).pointsPerMM, 6.2)
        model.resetCalibration()
        XCTAssertEqual(model.resolution.source, .model)
        XCTAssertEqual(defaults.double(forKey: ScaleModel.calibrationKey), 0)
    }
}
