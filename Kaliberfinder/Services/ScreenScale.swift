import Foundation

/// Converts millimetres to screen points so cartridges can be drawn at real size.
///
/// iOS doesn't report the display's pixel density, so the app knows the density
/// (pixels per inch) of each iPhone model, and lets the user calibrate against a
/// bank card when the model is unknown or the result is off by a little.
enum ScreenScale {
    enum Source: Equatable {
        /// Measured by the user with a card.
        case calibrated
        /// From the table of known models.
        case model
        /// Unknown model: guessed from the screen's pixel scale. Should be calibrated.
        case estimate
    }

    struct Resolution: Equatable {
        let pointsPerMM: Double
        let source: Source
    }

    /// Width and height of an ID-1 card (bank card, ID card, driving licence) in millimetres.
    static let cardSize = (width: 85.60, height: 53.98)

    /// Pixels per inch by model identifier (Apple's published values).
    static let ppiByModel: [String: Double] = [
        // iPhone SE (2nd/3rd gen), 11, XR
        "iPhone12,8": 326, "iPhone14,6": 326, "iPhone12,1": 326, "iPhone11,8": 326,
        // XS, XS Max, 11 Pro, 11 Pro Max
        "iPhone11,2": 458, "iPhone11,4": 458, "iPhone11,6": 458, "iPhone12,3": 458, "iPhone12,5": 458,
        // 12 mini, 12, 12 Pro, 12 Pro Max
        "iPhone13,1": 476, "iPhone13,2": 460, "iPhone13,3": 460, "iPhone13,4": 458,
        // 13 mini, 13, 13 Pro, 13 Pro Max
        "iPhone14,4": 476, "iPhone14,5": 460, "iPhone14,2": 460, "iPhone14,3": 458,
        // 14, 14 Plus, 14 Pro, 14 Pro Max
        "iPhone14,7": 460, "iPhone14,8": 458, "iPhone15,2": 460, "iPhone15,3": 460,
        // 15, 15 Plus, 15 Pro, 15 Pro Max
        "iPhone15,4": 460, "iPhone15,5": 460, "iPhone16,1": 460, "iPhone16,2": 460,
        // 16, 16 Plus, 16 Pro, 16 Pro Max, 16e
        "iPhone17,3": 460, "iPhone17,4": 460, "iPhone17,1": 460, "iPhone17,2": 460, "iPhone17,5": 460,
        // 17 Pro, 17 Pro Max, 17, Air
        "iPhone18,1": 460, "iPhone18,2": 460, "iPhone18,3": 460, "iPhone18,4": 460,
    ]

    /// Points per millimetre for a display of `ppi` pixels per inch at `nativeScale`
    /// physical pixels per point (UIScreen.nativeScale, which also covers Display Zoom).
    static func pointsPerMM(ppi: Double, nativeScale: Double) -> Double {
        ppi / 25.4 / nativeScale
    }

    /// The best available resolution: calibration first, then the model table, then a guess.
    static func resolve(model: String, nativeScale: Double, calibrated: Double?) -> Resolution {
        if let calibrated, calibrated > 0 { return Resolution(pointsPerMM: calibrated, source: .calibrated) }
        let scale = nativeScale > 0 ? nativeScale : 3
        if let ppi = ppiByModel[model] {
            return Resolution(pointsPerMM: pointsPerMM(ppi: ppi, nativeScale: scale), source: .model)
        }
        // Recent iPhones are 460 ppi at 3x, older 2x models 326 ppi: both about 153–163 ppi per point.
        let ppi = scale >= 2.5 ? 460.0 : 326.0
        return Resolution(pointsPerMM: pointsPerMM(ppi: ppi, nativeScale: scale), source: .estimate)
    }

    /// Calibration result: the user stretched a card outline of `points` to match a real card of `millimetres`.
    static func calibrated(points: Double, millimetres: Double) -> Double? {
        guard points > 0, millimetres > 0 else { return nil }
        let value = points / millimetres
        // Reject nonsense: real iPhones are around 5–7 pt/mm, iPads around 5.
        return (3...9).contains(value) ? value : nil
    }

    /// The device's model identifier, e.g. "iPhone18,1". On the simulator, the simulated model's.
    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
