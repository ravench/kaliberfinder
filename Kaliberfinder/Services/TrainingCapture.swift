import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Training data for the photo detection (Raven, 2026-11-04): a series of photos of one known
/// calibre with everything the phone measured, saved as a package for the private training repo
/// (ravench/kaliberfinder-training), whose golden shots come back as KaliberfinderTests/Golden.
///
/// A hidden developer tool, switched on by tapping the copyright line five times. It can be removed
/// with TrainingCapture*.swift, TrainingRecorder.swift and its lines in SettingsView and LiDARCamera.
///
/// Package layout (format 1):
///
///     9x19-mm-20261105-143000/
///       package.json            CapturePackage: calibre, part, note, device
///       01/
///         shot.json             CaptureShot: calibration, depth size, gravity, the app's analysis
///         photo.heic|jpg        the photo exactly as the camera or library delivered it (with EXIF)
///         depth.f32             LiDAR depth, Float32 little-endian, metres, row by row
///         vision-instances.png  Vision's foreground instances, one 8-bit label per pixel (0 = none)
///       02/ …
enum TrainingCapture {
    /// UserDefaults key of the hidden switch.
    static let enabledKey = "trainingCaptureEnabled"
    static let format = 1
    static let packageFile = "package.json"
    static let shotFile = "shot.json"
    static let depthFile = "depth.f32"
    static let maskFile = "vision-instances.png"

    /// The parts a series can show: a loaded cartridge or an empty case (`ScanMode` raw values).
    static let parts: [ScanMode] = [.cartridge, .emptyCase]

    /// File name for the photo bytes, with the extension of their format.
    static func photoName(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8]) { return "photo.jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "photo.png" }
        if bytes.count >= 8, bytes[4...7].elementsEqual("ftyp".utf8) { return "photo.heic" }
        return "photo.bin"
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// A series of photos of one calibre: package.json.
struct CapturePackage: Codable, Equatable {
    var format = TrainingCapture.format
    /// Catalogue id of the calibre photographed, e.g. "9x19 mm".
    let calibre: String
    /// What lies in the photos: "cartridge" or "emptyCase" (`ScanMode`).
    let part: String
    /// Free text, e.g. the surface or the light.
    var note = ""
    let created: Date
    /// Model identifier (e.g. "iPhone16,1"), iOS version and app version of the phone that took it.
    var device = ""
    var system = ""
    var app = ""

    var scanMode: ScanMode { ScanMode(rawValue: part) ?? .auto }
}

/// One photo of a series: shot.json.
struct CaptureShot: Codable, Equatable {
    /// File name of the photo next to shot.json.
    let photo: String
    /// "lidarCamera" or "library".
    let source: String
    let captured: Date
    /// EXIF orientation of the photo's stored pixels (1 upright, 6 as the camera stores portrait photos).
    var orientation: Int?
    var depth: DepthMap?
    var calibration: Calibration?
    /// The values the app measured the size from (`DepthScale`).
    var scale: Scale?
    /// Gravity in device coordinates (Core Motion, units of g) and the tilt from lying flat, in degrees.
    var gravity: [Double]?
    var tilt: Double?
    var mask: Mask?
    /// What the app made of the photo when it was taken.
    var analysis: Analysis?

    /// The depth map, in the frame of the photo's stored pixels (not rotated by `orientation`).
    struct DepthMap: Codable, Equatable {
        var file = TrainingCapture.depthFile
        let width: Int
        let height: Int
        /// "absolute" or "relative".
        let accuracy: String
        /// "high" or "low".
        let quality: String
        let filtered: Bool
    }

    /// The camera's calibration, in the frame of the photo's stored pixels.
    struct Calibration: Codable, Equatable {
        /// 3×3 intrinsic matrix row by row (fx 0 cx / 0 fy cy / 0 0 1) for an image of the reference size.
        let intrinsics: [Double]
        let referenceWidth: Double
        let referenceHeight: Double
        /// 3×4 extrinsic matrix row by row (rotation | translation in mm).
        let extrinsics: [Double]
        /// Size of one sensor pixel in mm.
        let pixelSize: Double
        /// Lens distortion centre (pixels of the reference size) and the radial lookup tables.
        let distortionCenter: [Double]
        let distortion: [Double]
        let inverseDistortion: [Double]
    }

    struct Scale: Codable, Equatable {
        let tableDistance: Double
        let focalLength: Double
        let referenceLongSide: Double

        var depthScale: DepthScale {
            DepthScale(tableDistance: tableDistance, focalLength: focalLength, referenceLongSide: referenceLongSide)
        }
    }

    /// Vision's foreground instances, in the frame of the upright photo.
    struct Mask: Codable, Equatable {
        var file = TrainingCapture.maskFile
        let width: Int
        let height: Int
        let instances: Int
        /// Size of the upright photo as analysed (`PhotoAnalyzer.maxDimension`), which the mask
        /// covers; lets a shot be replayed without its photo (golden set).
        var imageWidth: Int?
        var imageHeight: Int?
    }

    struct Analysis: Codable, Equatable {
        var aspect: Double?
        /// `PhotoAnalysis.lengthPixels` and `imageLongSide`: after the second look the whole photo's
        /// long side at the scale of the part looked at, so mostly larger than the mask's `imageWidth`.
        var lengthPixels: Double?
        var imageLongSide: Double
        /// The measured silhouette's rotated box, fractions of the upright photo.
        var outline: [[Double]]?
        var isBrass: Bool
        /// Cartridges competing for the measurement (0 when at most one).
        var candidates: Int
        /// Length and diameter in mm, measured with LiDAR.
        var size: [Double]?
        /// Best matches, best first.
        var matches: [String]
    }
}

/// A package on disk with its shots.
struct SavedCapture: Identifiable, Hashable {
    let url: URL
    let package: CapturePackage
    /// Read with the list, so a list reloaded after new photos differs and SwiftUI redraws its row.
    var shotCount = 0
    var id: URL { url }

    static func == (a: SavedCapture, b: SavedCapture) -> Bool { a.url == b.url && a.shotCount == b.shotCount }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }

    var shots: [SavedShot] { CaptureStore.shots(in: url) }
}

/// A shot on disk: its folder and shot.json.
struct SavedShot: Identifiable {
    let url: URL
    let shot: CaptureShot
    var id: URL { url }
}

enum CaptureError: Error, Equatable {
    case wrongDepthSize
    case wrongMaskSize
    case noPhoto
}

/// Reads and writes capture packages under `root`.
struct CaptureStore {
    let root: URL

    /// Documents/TrainingCaptures on the phone.
    static var standard: CaptureStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return CaptureStore(root: documents.appendingPathComponent("TrainingCaptures", isDirectory: true))
    }

    /// Creates the folder of a new series and writes its package.json.
    func create(_ package: CapturePackage) throws -> URL {
        let url = root.appendingPathComponent(Self.folderName(package), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try TrainingCapture.encoder.encode(package).write(to: url.appendingPathComponent(TrainingCapture.packageFile))
        return url
    }

    /// The packages under `root`, newest first.
    func packages() -> [SavedCapture] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent(TrainingCapture.packageFile)),
                  let package = try? TrainingCapture.decoder.decode(CapturePackage.self, from: data) else { return nil }
            return SavedCapture(url: url, package: package, shotCount: Self.shots(in: url).count)
        }
        .sorted { ($0.package.created, $0.url.lastPathComponent) > ($1.package.created, $1.url.lastPathComponent) }
    }

    func delete(_ capture: SavedCapture) throws {
        try FileManager.default.removeItem(at: capture.url)
    }

    /// E.g. "9x19-mm-20261105-143000".
    static func folderName(_ package: CapturePackage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let slug = package.calibre.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return "\(slug)-\(formatter.string(from: package.created))"
    }

    /// The shots of a package, in the order they were taken.
    static func shots(in package: URL) -> [SavedShot] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent(TrainingCapture.shotFile)),
                  let shot = try? TrainingCapture.decoder.decode(CaptureShot.self, from: data) else { return nil }
            return SavedShot(url: url, shot: shot)
        }
        .sorted { (Int($0.url.lastPathComponent) ?? 0) < (Int($1.url.lastPathComponent) ?? 0) }
    }

    /// Writes a shot into the next numbered folder ("01", "02" …) of `package` and returns that folder.
    /// `depth` must have `shot.depth`'s size, `mask` `shot.mask`'s.
    @discardableResult
    static func save(_ shot: CaptureShot, photo: Data, depth: [Float]? = nil, mask: [UInt8]? = nil, in package: URL) throws -> URL {
        guard !photo.isEmpty else { throw CaptureError.noPhoto }
        if let info = shot.depth, depth?.count != info.width * info.height { throw CaptureError.wrongDepthSize }
        if let info = shot.mask, mask?.count != info.width * info.height { throw CaptureError.wrongMaskSize }
        let next = (shots(in: package).compactMap { Int($0.url.lastPathComponent) }.max() ?? 0) + 1
        let folder = package.appendingPathComponent(String(format: "%02d", next), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try photo.write(to: folder.appendingPathComponent(shot.photo))
        if let info = shot.depth, let depth {
            try depth.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: folder.appendingPathComponent(info.file))
        }
        if let info = shot.mask, let mask, let png = png(gray: mask, width: info.width, height: info.height) {
            try png.write(to: folder.appendingPathComponent(info.file))
        }
        try TrainingCapture.encoder.encode(shot).write(to: folder.appendingPathComponent(TrainingCapture.shotFile))
        return folder
    }

    /// The depth values of a shot (metres), nil without depth.
    static func depth(of shot: CaptureShot, at folder: URL) -> [Float]? {
        guard let info = shot.depth, let data = try? Data(contentsOf: folder.appendingPathComponent(info.file)),
              data.count == info.width * info.height * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// The instance labels of a shot's Vision mask, nil without one.
    static func mask(of shot: CaptureShot, at folder: URL) -> [UInt8]? {
        guard let info = shot.mask, let data = try? Data(contentsOf: folder.appendingPathComponent(info.file)) else { return nil }
        return gray(png: data, width: info.width, height: info.height)
    }

    /// A zip file of the package in the temporary folder, for the share sheet.
    static func zip(_ package: URL) throws -> URL {
        var coordinatorError: NSError?
        var result: Result<URL, Error> = .failure(CaptureError.noPhoto)
        NSFileCoordinator().coordinate(readingItemAt: package, options: .forUploading, error: &coordinatorError) { zipped in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(package.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: target)
            result = Result { try FileManager.default.copyItem(at: zipped, to: target); return target }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    // MARK: - 8-bit grey PNG

    static func png(gray: [UInt8], width: Int, height: Int) -> Data? {
        guard width > 0, height > 0, gray.count == width * height,
              let provider = CGDataProvider(data: Data(gray) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func gray(png: Data, width: Int, height: Int) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height, image.bitsPerPixel == 8,
              let bytes = image.dataProvider?.data as Data? else { return nil }
        let rowBytes = image.bytesPerRow
        return (0..<height).flatMap { y in bytes[(y * rowBytes)..<(y * rowBytes + width)] }
    }
}
