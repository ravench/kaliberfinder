import Foundation

/// What the LiDAR camera knew when the photo was taken: how far away the table was and the
/// camera's focal length. Kept in memory only, never stored.
struct DepthScale: Equatable {
    /// Distance from the camera to the surface the cartridge lies on, in mm.
    let tableDistance: Double
    /// Focal length in pixels, for an image whose long side is `referenceLongSide` pixels.
    let focalLength: Double
    let referenceLongSide: Double
}

/// Cartridge size measured from a photo with depth, in mm, with an uncertainty (also mm).
struct MeasuredSize: Equatable {
    let length: Double
    let diameter: Double
    let lengthError: Double
    let diameterError: Double
}

/// Why a photo with depth still couldn't be measured.
enum SizeFailure: Equatable {
    case noDepth
    case outOfRange
    case endView
}

/// Turns a silhouette's extent in pixels into millimetres using the LiDAR distance (LIDAR-03).
/// Pure functions, so they can be tested with recorded values (LIDAR-08).
enum SizeEstimator {
    /// Distances the result is trusted for, in mm. The guide asks for 20–30 cm.
    static let usableDistance = 120.0...450.0
    /// Depth error: 1 % of the distance plus 2 mm.
    static let depthRelativeError = 0.01
    static let depthAbsoluteError = 2.0
    /// Edge uncertainty of the cut-out silhouette, in image pixels per side.
    static let edgePixels = 2.0

    /// The surface distance from depth samples (metres, as the depth map stores them) around the
    /// centre of the frame: the median of the valid samples. The cartridge covers only a small part of
    /// the frame, so the median is the table. Nil when fewer than half of the samples are valid.
    static func tableDistance(samples: [Float]) -> Double? {
        let valid = samples.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !valid.isEmpty, valid.count * 2 >= samples.count else { return nil }
        return Double(valid[valid.count / 2]) * 1000
    }

    /// Size of the cartridge whose silhouette is `lengthPixels` long with length/width ratio `aspect`,
    /// in an image whose long side is `imageLongSide` pixels.
    ///
    /// The cartridge lies on the table, so its outline (the widest section, through its axis) is half a
    /// diameter closer to the camera than the table: with f the focal length, w the width in pixels and
    /// z the table distance, the diameter is d = w·z / (f + w/2) and the length l·(z − d/2) / f.
    static func estimate(lengthPixels: Double, aspect: Double, imageLongSide: Double,
                         depth: DepthScale?) -> Result<MeasuredSize, SizeFailure> {
        guard let depth, depth.focalLength > 0, depth.referenceLongSide > 0, imageLongSide > 0, lengthPixels > 0, aspect > 0
        else { return .failure(.noDepth) }
        guard usableDistance.contains(depth.tableDistance) else { return .failure(.outOfRange) }
        guard aspect >= 1.4 else { return .failure(.endView) }
        let f = depth.focalLength * imageLongSide / depth.referenceLongSide
        let z = depth.tableDistance
        let widthPixels = lengthPixels / aspect
        let diameter = widthPixels * z / (f + widthPixels / 2)
        let axis = z - diameter / 2
        let length = lengthPixels * axis / f
        let relative = depthRelativeError + depthAbsoluteError / z
        let pixel = 2 * edgePixels * axis / f
        return .success(MeasuredSize(length: length, diameter: diameter,
                                     lengthError: length * relative + pixel,
                                     diameterError: diameter * relative + pixel))
    }
}

/// What the camera screen tells the user while aiming (LIDAR-04).
enum LiDARGuidance: Equatable {
    case noDepth
    case tooClose
    case tooFar
    case tilted
    case ready

    /// The distance the guide asks for, in mm (20–30 cm, with a little slack).
    static let distance = 180.0...330.0
    /// How far the phone may lean from lying flat, in degrees.
    static let maxTilt = 8.0

    static func state(distance: Double?, tilt: Double?) -> LiDARGuidance {
        guard let distance else { return .noDepth }
        if distance < Self.distance.lowerBound { return .tooClose }
        if distance > Self.distance.upperBound { return .tooFar }
        if let tilt, tilt > maxTilt { return .tilted }
        return .ready
    }

    /// Angle between the camera's view and straight down, from the gravity vector (device
    /// coordinates, as Core Motion reports it). Flat, screen up: gravity (0, 0, −1), 0°.
    static func tilt(gravityX x: Double, y: Double, z: Double) -> Double {
        let length = (x * x + y * y + z * z).squareRoot()
        guard length > 0 else { return 90 }
        return acos(min(1, max(-1, -z / length))) * 180 / .pi
    }

    /// German text, used as localization key.
    var title: String {
        switch self {
        case .noDepth: "Keine Tiefe gemessen"
        case .tooClose: "Etwas weiter weg"
        case .tooFar: "Näher heran"
        case .tilted: "iPhone parallel zum Tisch halten"
        case .ready: "Abstand passt"
        }
    }
}
