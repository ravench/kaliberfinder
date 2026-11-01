import SwiftUI
import UIKit

/// Holds the current mm-to-points conversion and the user's calibration.
@MainActor
final class ScaleModel: ObservableObject {
    static let calibrationKey = "calibratedPointsPerMM"

    @Published private(set) var resolution: ScreenScale.Resolution
    private let defaults: UserDefaults
    private let model: String
    private let nativeScale: Double

    init(defaults: UserDefaults = .standard, model: String = ScreenScale.modelIdentifier(), nativeScale: Double? = nil) {
        self.defaults = defaults
        self.model = model
        self.nativeScale = nativeScale ?? Self.currentNativeScale()
        let stored = defaults.double(forKey: Self.calibrationKey)
        resolution = ScreenScale.resolve(model: model, nativeScale: self.nativeScale, calibrated: stored > 0 ? stored : nil)
    }

    var pointsPerMM: Double { resolution.pointsPerMM }

    /// The value without calibration, used as the calibration screen's starting point.
    var uncalibrated: ScreenScale.Resolution {
        ScreenScale.resolve(model: model, nativeScale: nativeScale, calibrated: nil)
    }

    func calibrate(pointsPerMM value: Double) {
        defaults.set(value, forKey: Self.calibrationKey)
        resolution = ScreenScale.resolve(model: model, nativeScale: nativeScale, calibrated: value)
    }

    func resetCalibration() {
        defaults.removeObject(forKey: Self.calibrationKey)
        resolution = uncalibrated
    }

    private static func currentNativeScale() -> Double {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return Double(scene?.screen.nativeScale ?? 3)
    }
}
