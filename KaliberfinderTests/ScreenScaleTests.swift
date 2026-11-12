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

    @MainActor func testIPadMiniAtItsOwnNativeScale() {
        // iPad mini (A17 Pro): 326 ppi at 2x. TestFlight 1158 drew it at two thirds: the model had taken the
        // iPhones' 3 for want of a connected scene, and `ScaleModel` now asks the main screen instead.
        let r = ScreenScale.resolve(model: "iPad16,1", nativeScale: 2, calibrated: nil)
        XCTAssertEqual(r.pointsPerMM, 326 / 25.4 / 2, accuracy: 0.0001)
        XCTAssertEqual(r.pointsPerMM * 90, 577.6, accuracy: 0.1, "9 cm of ruler")
        let wrong = ScreenScale.resolve(model: "iPad16,1", nativeScale: 3, calibrated: nil)
        XCTAssertEqual(wrong.pointsPerMM / r.pointsPerMM, 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(ScaleModel(model: "iPad16,1").pointsPerMM, ScreenScale.resolve(model: "iPad16,1", nativeScale: Double(UIScreen.main.nativeScale), calibrated: nil).pointsPerMM, accuracy: 0.0001, "the screen's scale, not 3")
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
            if model.hasPrefix("iPhone") {
                XCTAssertTrue((300...500).contains(ppi), model)
            } else {
                // Apple's iPads are all 264 ppi, the minis 326.
                XCTAssertTrue(model.hasPrefix("iPad"), model)
                XCTAssertTrue(ppi == 264 || ppi == 326, model)
            }
        }
        XCTAssertGreaterThan(ScreenScale.ppiByModel.keys.filter { $0.hasPrefix("iPad") }.count, 60)
    }

    func testIPadModelsUseTheirDensity() {
        // iPad Pro 11" (M5), the simulator this was checked on: 264 ppi at 2x, so 5.2 pt/mm.
        let pro = ScreenScale.resolve(model: "iPad17,2", nativeScale: 2, calibrated: nil)
        XCTAssertEqual(pro.source, .model)
        XCTAssertEqual(pro.pointsPerMM, 264 / 25.4 / 2, accuracy: 0.0001)
        // An 85.6 mm card is about 445 pt tall there.
        XCTAssertEqual(85.6 * pro.pointsPerMM, 444.9, accuracy: 0.2)
        // iPad mini (A17 Pro): 326 ppi.
        let mini = ScreenScale.resolve(model: "iPad16,1", nativeScale: 2, calibrated: nil)
        XCTAssertEqual(mini.source, .model)
        XCTAssertEqual(mini.pointsPerMM, 326 / 25.4 / 2, accuracy: 0.0001)
        // iPad Display Zoom «Larger Text» renders at a smaller native scale: the drawing stays real size.
        let zoomed = ScreenScale.resolve(model: "iPad17,2", nativeScale: 2.3, calibrated: nil)
        XCTAssertLessThan(zoomed.pointsPerMM, pro.pointsPerMM)
    }

    func testUnknownIPadIsEstimatedAsAnIPad() {
        // A future iPad: 264 ppi, not the 326 of a 2x iPhone, which would draw a quarter too large.
        let r = ScreenScale.resolve(model: "iPad99,9", nativeScale: 2, calibrated: nil)
        XCTAssertEqual(r.source, .estimate)
        XCTAssertEqual(r.pointsPerMM, 264 / 25.4 / 2, accuracy: 0.0001)
        XCTAssertEqual(ScreenScale.estimatedPPI(model: "iPad99,9", nativeScale: 2), 264)
        XCTAssertEqual(ScreenScale.estimatedPPI(model: "iPhone99,9", nativeScale: 2), 326)
        XCTAssertEqual(ScreenScale.estimatedPPI(model: "iPhone99,9", nativeScale: 3), 460)
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
