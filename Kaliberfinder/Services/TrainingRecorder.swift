import AVFoundation
import ImageIO
import UIKit
import Vision

/// Turns a photo from the LiDAR camera or the library into a training shot (see `TrainingCapture`):
/// depth, calibration, Vision's instance mask and the app's own analysis.
enum TrainingRecorder {
    /// Saves a photo from the LiDAR camera with everything it carries.
    @discardableResult
    static func save(_ photo: AVCapturePhoto, gravity: [Double]?, tilt: Double?, mode: ScanMode, in package: URL) async throws -> URL {
        guard let data = photo.fileDataRepresentation() else { throw CaptureError.noPhoto }
        var shot = CaptureShot(photo: TrainingCapture.photoName(for: data), source: "lidarCamera", captured: Date())
        shot.orientation = photo.metadata[kCGImagePropertyOrientation as String] as? Int
        shot.gravity = gravity
        shot.tilt = tilt
        var depthValues: [Float]?
        if let depthData = photo.depthData {
            if let map = LiDARCamera.depthValues(depthData) {
                depthValues = map.values
                shot.depth = .init(width: map.width, height: map.height,
                                   accuracy: depthData.depthDataAccuracy == .absolute ? "absolute" : "relative",
                                   quality: depthData.depthDataQuality == .high ? "high" : "low",
                                   filtered: depthData.isDepthDataFiltered)
            }
            shot.calibration = depthData.cameraCalibrationData.map(calibration)
            shot.scale = LiDARCamera.depthScale(depthData).map {
                CaptureShot.Scale(tableDistance: $0.tableDistance, focalLength: $0.focalLength, referenceLongSide: $0.referenceLongSide)
            }
        }
        return try await finish(shot, data: data, depth: depthValues, mode: mode, in: package)
    }

    /// Saves a photo picked from the library, as is (no depth).
    @discardableResult
    static func save(libraryPhoto data: Data, mode: ScanMode, in package: URL) async throws -> URL {
        var shot = CaptureShot(photo: TrainingCapture.photoName(for: data), source: "library", captured: Date())
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            shot.orientation = properties[kCGImagePropertyOrientation as String] as? Int
        }
        return try await finish(shot, data: data, depth: nil, mode: mode, in: package)
    }

    private static func finish(_ shot: CaptureShot, data: Data, depth: [Float]?, mode: ScanMode, in package: URL) async throws -> URL {
        guard let image = UIImage(data: data) else { throw CaptureError.noPhoto }
        var shot = shot
        let scale = shot.scale?.depthScale
        let (analysis, mask) = await Task.detached(priority: .userInitiated) {
            (analyse(image, scale: scale, mode: mode), instanceMask(image))
        }.value
        shot.analysis = analysis
        if let mask { shot.mask = .init(width: mask.width, height: mask.height, instances: mask.instances) }
        return try CaptureStore.save(shot, photo: data, depth: depth, mask: mask?.labels, in: package)
    }

    /// What the app finds in the photo now, kept to compare later versions with.
    static func analyse(_ image: UIImage, scale: DepthScale?, mode: ScanMode) -> CaptureShot.Analysis {
        let analysis = PhotoAnalyzer.analyzeNow(image)
        let size = try? analysis.size(depth: scale).get()
        let matches = Matcher.rank(shape: analysis.shape, size: size, mode: mode, brass: analysis.isBrass, limit: 5)
        return .init(aspect: analysis.shape?.aspect, lengthPixels: analysis.lengthPixels, imageLongSide: analysis.imageLongSide,
                     outline: analysis.outline?.map { [Double($0.x), Double($0.y)] }, isBrass: analysis.isBrass,
                     candidates: analysis.candidates.count, size: size.map { [$0.length, $0.diameter] },
                     matches: matches.map(\.cartridge.id))
    }

    /// Vision's foreground instance labels for the upright photo, at the size the app analyses
    /// (`PhotoAnalyzer.maxDimension`). Nil where Vision can't run it (the simulator).
    static func instanceMask(_ image: UIImage) -> (labels: [UInt8], width: Int, height: Int, instances: Int)? {
        guard let cgImage = upright(image, maxSide: PhotoAnalyzer.maxDimension) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else { return nil }
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var labels: [UInt8] = []
        labels.reserveCapacity(width * height)
        for y in 0..<height {
            labels.append(contentsOf: UnsafeBufferPointer(start: base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self), count: width))
        }
        return (labels, width, height, observation.allInstances.count)
    }

    /// The image with its orientation applied, at most `maxSide` pixels long.
    private static func upright(_ image: UIImage, maxSide: CGFloat) -> CGImage? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return nil }
        let factor = min(1, maxSide / longSide)
        let size = CGSize(width: (image.size.width * factor).rounded(), height: (image.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    static func calibration(_ c: AVCameraCalibrationData) -> CaptureShot.Calibration {
        .init(intrinsics: rows(c.intrinsicMatrix), referenceWidth: Double(c.intrinsicMatrixReferenceDimensions.width),
              referenceHeight: Double(c.intrinsicMatrixReferenceDimensions.height), extrinsics: rows(c.extrinsicMatrix),
              pixelSize: Double(c.pixelSize),
              distortionCenter: [Double(c.lensDistortionCenter.x), Double(c.lensDistortionCenter.y)],
              distortion: floats(c.lensDistortionLookupTable), inverseDistortion: floats(c.inverseLensDistortionLookupTable))
    }

    /// A 3×3 matrix row by row (simd stores columns).
    static func rows(_ m: simd_float3x3) -> [Double] {
        (0..<3).flatMap { r in [m.columns.0[r], m.columns.1[r], m.columns.2[r]].map(Double.init) }
    }

    /// A 3-row, 4-column matrix row by row.
    static func rows(_ m: simd_float4x3) -> [Double] {
        (0..<3).flatMap { r in [m.columns.0[r], m.columns.1[r], m.columns.2[r], m.columns.3[r]].map(Double.init) }
    }

    private static func floats(_ data: Data?) -> [Double] {
        guard let data else { return [] }
        return data.withUnsafeBytes { $0.bindMemory(to: Float.self).map(Double.init) }
    }

    /// Model identifier such as "iPhone16,1" (the simulator reports its own).
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return Mirror(reflecting: info.machine).children.reduce(into: "") { text, child in
            guard let byte = child.value as? CChar, byte != 0 else { return }
            text.append(Character(UnicodeScalar(UInt8(bitPattern: byte))))
        }
    }

    /// A new package with this phone's details.
    static func package(calibre: String, mode: ScanMode, note: String) -> CapturePackage {
        let bundle = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(bundle["CFBundleShortVersionString"] ?? "?") (\(bundle["CFBundleVersion"] ?? "?"))"
        return CapturePackage(calibre: calibre, part: mode.rawValue, note: note, created: Date(), device: deviceModel,
                              system: "iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", app: version)
    }
}
