import Foundation

/// Converts millimetres to screen points so cartridges can be drawn at real size.
///
/// iOS doesn't report the display's pixel density, so the app knows the density
/// (pixels per inch) of each iPhone and iPad model, and lets the user calibrate against a
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
        // iPads that run iPadOS 17 (Apple's published densities: 264 ppi, iPad mini 326 ppi).
        // iPad Pro 12.9" (2nd gen), 10.5", iPad 6, iPad 7
        "iPad7,1": 264, "iPad7,2": 264, "iPad7,3": 264, "iPad7,4": 264, "iPad7,5": 264, "iPad7,6": 264, "iPad7,11": 264, "iPad7,12": 264,
        // iPad Pro 11" (1st/2nd gen), 12.9" (3rd/4th gen)
        "iPad8,1": 264, "iPad8,2": 264, "iPad8,3": 264, "iPad8,4": 264, "iPad8,5": 264, "iPad8,6": 264, "iPad8,7": 264, "iPad8,8": 264,
        "iPad8,9": 264, "iPad8,10": 264, "iPad8,11": 264, "iPad8,12": 264,
        // iPad mini 5, iPad Air 3, iPad 8, iPad 9
        "iPad11,1": 326, "iPad11,2": 326, "iPad11,3": 264, "iPad11,4": 264, "iPad11,6": 264, "iPad11,7": 264, "iPad12,1": 264, "iPad12,2": 264,
        // iPad Air 4, iPad Pro 11" (3rd gen), 12.9" (5th gen), iPad Air 5, iPad 10
        "iPad13,1": 264, "iPad13,2": 264, "iPad13,4": 264, "iPad13,5": 264, "iPad13,6": 264, "iPad13,7": 264,
        "iPad13,8": 264, "iPad13,9": 264, "iPad13,10": 264, "iPad13,11": 264, "iPad13,16": 264, "iPad13,17": 264, "iPad13,18": 264, "iPad13,19": 264,
        // iPad mini 6, iPad Pro 11" (4th gen), 12.9" (6th gen), iPad Air 11" and 13" (M2)
        "iPad14,1": 326, "iPad14,2": 326, "iPad14,3": 264, "iPad14,4": 264, "iPad14,5": 264, "iPad14,6": 264,
        "iPad14,8": 264, "iPad14,9": 264, "iPad14,10": 264, "iPad14,11": 264,
        // iPad Air 11" and 13" (M3), iPad (A16)
        "iPad15,3": 264, "iPad15,4": 264, "iPad15,5": 264, "iPad15,6": 264, "iPad15,7": 264, "iPad15,8": 264,
        // iPad mini (A17 Pro), iPad Pro 11" and 13" (M4), iPad Air 11" and 13" (M4)
        "iPad16,1": 326, "iPad16,2": 326, "iPad16,3": 264, "iPad16,4": 264, "iPad16,5": 264, "iPad16,6": 264,
        "iPad16,8": 264, "iPad16,9": 264, "iPad16,10": 264, "iPad16,11": 264,
        // iPad Pro 11" and 13" (M5), iPad mini (A20 Pro)
        "iPad17,1": 264, "iPad17,2": 264, "iPad17,3": 264, "iPad17,4": 264, "iPad19,1": 326, "iPad19,2": 326,
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
        let ppi = estimatedPPI(model: model, nativeScale: scale)
        return Resolution(pointsPerMM: pointsPerMM(ppi: ppi, nativeScale: scale), source: .estimate)
    }

    /// A guess for a model not in the table. Every iPad but the mini is 264 ppi, and the minis are
    /// 326; recent iPhones are 460 ppi at 3x, older 2x models 326: both about 153–163 ppi per point.
    static func estimatedPPI(model: String, nativeScale: Double) -> Double {
        if model.hasPrefix("iPad") { return 264 }
        return nativeScale >= 2.5 ? 460 : 326
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
        let bytes = withUnsafeBytes(of: &info.machine) { raw in Array(raw.prefix { $0 != 0 }) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }
}
