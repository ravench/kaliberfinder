import Foundation

/// Why a photo makes a lying cartridge look longer than it is. Its axis lies half a body diameter
/// above the table, and that is where the outline's width is measured. Its ends stand higher: the
/// top of the case head (of the rim, where that is wider) a whole diameter up, a case mouth half its
/// own diameter above the axis; only a bullet's tip lies on the axis. Seen from above, a point higher
/// up is nearer the camera and looks further out, so both ends of an empty case lie further apart in
/// the photo than at the axis's height: about 3 % for a .45 ACP case 20 cm away, half that for a
/// loaded round, whose tip lies on the axis. The length over the width, and with LiDAR the length,
/// came out that much too large (2026-11-06: on the training shots LiDAR lengths were 5 % long, half
/// of it from this).
enum EndRise {
    /// Focal length over the photo's long side where the photo carries none: the phone's 1× camera,
    /// 26 mm full-frame equivalent (2961 px at 4032 on an iPhone 17 Pro). The LiDAR camera is the same.
    static let focalOverLongSide = 0.734
    /// The widest a body can look against its distance through the 1× camera: 15 mm across at its
    /// closest focus, about 12 cm. A photo without depth that shows more was cropped or zoomed, so its
    /// focal length isn't known, and it gets no correction.
    static let maxPerspectiveWithoutDepth = 0.125

    /// How much longer the outline `shape` looks than the cartridge at its axis's height when its body
    /// is `perspective` times as wide as its axis's distance from the camera (body pixels over the focal
    /// length in pixels). The front is a case mouth where `mode` sees an empty case (the user's choice,
    /// or automatic mode's), else a bullet's tip; the head is as wide as the rim. Assumes the cartridge
    /// lies about in the middle of the photo, with both ends turned away from the camera's axis. 1 when
    /// nothing is known, or when the shape at the axis would be an end view.
    static func factor(_ shape: ShapeMeasurement, perspective p: Double, mode: ScanMode = .auto) -> Double {
        guard !shape.isEndView, let features = shape.features, p > 0, p < 0.5 else { return 1 }
        let front = mode.part(for: shape) == .emptyCase ? features.mouth / 2 : 0
        let back = features.rim / 2
        let rise = (1 / (1 - front * p) + 1 / (1 - back * p)) / 2
        return ShapeMeasurement(aspect: shape.aspect / rise, profile: shape.profile).isEndView ? 1 : rise
    }
}

extension PhotoAnalysis {
    /// The measured body's width over its axis's distance from the camera: its width in pixels over the
    /// focal length in pixels, from the LiDAR camera's calibration or else the phone's 1× camera (nil
    /// beyond what that camera can show, `EndRise.maxPerspectiveWithoutDepth`).
    func perspective(depth: DepthScale?) -> Double? {
        guard let shape, let lengthPixels, shape.aspect > 0, imageLongSide > 0 else { return nil }
        let focal = depth.map { $0.focalLength * imageLongSide / $0.referenceLongSide } ?? EndRise.focalOverLongSide * imageLongSide
        guard focal > 0 else { return nil }
        let p = lengthPixels / shape.aspect / focal
        return depth != nil || p <= EndRise.maxPerspectiveWithoutDepth ? p : nil
    }

    /// How much longer the outline looks than the cartridge at its axis's height (`EndRise`), for the
    /// part `mode` sees.
    func endRise(depth: DepthScale?, mode: ScanMode = .auto) -> Double {
        guard let shape, let p = perspective(depth: depth) else { return 1 }
        return EndRise.factor(shape, perspective: p, mode: mode)
    }
}
