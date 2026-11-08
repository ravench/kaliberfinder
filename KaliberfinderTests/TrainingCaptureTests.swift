import simd
import UIKit
import XCTest
@testable import Kaliberfinder

/// The training capture packages (`TrainingCapture`): writing, reading back, zipping.
final class TrainingCaptureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("captures-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var store: CaptureStore { CaptureStore(root: root) }

    private func package(_ calibre: String = "9x19 mm", created: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> CapturePackage {
        CapturePackage(calibre: calibre, part: ScanMode.cartridge.rawValue, note: "Holztisch", created: created,
                       device: "iPhone16,1", system: "iOS 26.1", app: "0.1.0 (1)")
    }

    private func jpeg() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    /// A 16 × 12 depth map: table at 25 cm, a cartridge 1 cm higher in the middle.
    private let depth: [Float] = (0..<12).flatMap { y in (0..<16).map { x -> Float in (6...9).contains(x) && (5...6).contains(y) ? 0.24 : 0.25 } }

    private func shot() -> CaptureShot {
        var shot = CaptureShot(photo: "photo.jpg", source: "lidarCamera", captured: Date(timeIntervalSince1970: 1_800_000_100))
        shot.orientation = 6
        shot.depth = .init(width: 16, height: 12, accuracy: "absolute", quality: "high", filtered: true)
        shot.scale = .init(tableDistance: 250, focalLength: 2794, referenceLongSide: 4032)
        shot.gravity = [0.01, -0.02, -0.99]
        shot.tilt = 1.3
        shot.focus = .init(minimumDistance: 150, lensPosition: 0.62)
        shot.mask = .init(width: 4, height: 3, instances: 2, imageWidth: 1600, imageHeight: 1200)
        shot.analysis = .init(aspect: 3.0, lengthPixels: 300, imageLongSide: 1600, outline: [[0.1, 0.2], [0.3, 0.2], [0.3, 0.3], [0.1, 0.3]],
                              isBrass: true, candidates: 0, size: [29.7, 9.9], matches: ["9x19 mm"])
        return shot
    }

    func testShotRoundTrip() throws {
        let url = try store.create(package())
        XCTAssertEqual(url.lastPathComponent, "9x19-mm-20270115-080000")
        let mask: [UInt8] = [0, 0, 1, 1, 0, 2, 2, 1, 0, 0, 0, 0]
        let photo = try jpeg()
        let folder = try CaptureStore.save(shot(), photo: photo, depth: depth, mask: mask, in: url)
        XCTAssertEqual(folder.lastPathComponent, "01")

        let saved = try XCTUnwrap(store.packages().first)
        XCTAssertEqual(saved.package, package())
        let shots = saved.shots
        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(shots[0].shot, shot())
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("photo.jpg")), photo)
        XCTAssertEqual(CaptureStore.depth(of: shots[0].shot, at: shots[0].url), depth)
        XCTAssertEqual(CaptureStore.mask(of: shots[0].shot, at: shots[0].url), mask)
        XCTAssertEqual(saved.package.scanMode, .cartridge)
    }

    func testShotsAreNumberedInOrder() throws {
        let url = try store.create(package())
        for _ in 0..<11 {
            try CaptureStore.save(CaptureShot(photo: "photo.jpg", source: "library", captured: Date()), photo: try jpeg(), in: url)
        }
        let names = CaptureStore.shots(in: url).map(\.url.lastPathComponent)
        XCTAssertEqual(names, (1...11).map { String(format: "%02d", $0) })
        XCTAssertNil(CaptureStore.depth(of: CaptureStore.shots(in: url)[0].shot, at: CaptureStore.shots(in: url)[0].url))
    }

    func testRejectsMismatchedData() throws {
        let url = try store.create(package())
        XCTAssertThrowsError(try CaptureStore.save(shot(), photo: try jpeg(), depth: [0.25], mask: [UInt8](repeating: 0, count: 12), in: url)) {
            XCTAssertEqual($0 as? CaptureError, .wrongDepthSize)
        }
        XCTAssertThrowsError(try CaptureStore.save(shot(), photo: try jpeg(), depth: depth, mask: [0], in: url)) {
            XCTAssertEqual($0 as? CaptureError, .wrongMaskSize)
        }
        XCTAssertThrowsError(try CaptureStore.save(shot(), photo: Data(), depth: depth, in: url)) {
            XCTAssertEqual($0 as? CaptureError, .noPhoto)
        }
        XCTAssertTrue(CaptureStore.shots(in: url).isEmpty, "nothing half-written")
    }

    func testPackagesNewestFirstAndDelete() throws {
        try store.create(package("9x19 mm", created: Date(timeIntervalSince1970: 1_800_000_000)))
        try store.create(package(".45 ACP", created: Date(timeIntervalSince1970: 1_800_000_500)))
        XCTAssertEqual(store.packages().map(\.package.calibre), [".45 ACP", "9x19 mm"])
        try store.delete(store.packages()[0])
        XCTAssertEqual(store.packages().map(\.package.calibre), ["9x19 mm"])
    }

    func testListedPackageChangesWhenAShotIsAdded() throws {
        let url = try store.create(package())
        let before = try XCTUnwrap(store.packages().first)
        XCTAssertEqual(before.shotCount, 0)
        try CaptureStore.save(CaptureShot(photo: "photo.jpg", source: "library", captured: Date()), photo: try jpeg(), in: url)
        let after = try XCTUnwrap(store.packages().first)
        XCTAssertEqual(after.shotCount, 1)
        XCTAssertGreaterThan(after.bytes, before.bytes, "the photo and its shot.json count")
        XCTAssertEqual(after.bytes, CaptureStore.bytes(in: url))
        XCTAssertNotEqual(before, after, "an equal value would keep SwiftUI showing «0 Fotos»")
    }

    /// The PR screens tour opens the example package (`-screenTourCaptures`) instead of the phone's series.
    func testTourPointsTheStoreAtItsFolder() {
        XCTAssertEqual(CaptureStore.standard.root.lastPathComponent, "TrainingCaptures")
        UserDefaults.standard.set(root.path, forKey: CaptureStore.tourKey)
        defer { UserDefaults.standard.removeObject(forKey: CaptureStore.tourKey) }
        XCTAssertEqual(CaptureStore.standard.root.path, root.path)
    }

    func testFolderNameIsASlugOfTheCalibre() {
        XCTAssertEqual(CaptureStore.folderName(package("7.5x55 mm Swiss (GP 11)")), "7-5x55-mm-swiss-gp-11-20270115-080000")
    }

    func testPhotoNameFollowsTheFormat() throws {
        XCTAssertEqual(TrainingCapture.photoName(for: try jpeg()), "photo.jpg")
        XCTAssertEqual(TrainingCapture.photoName(for: Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))), "photo.heic")
        XCTAssertEqual(TrainingCapture.photoName(for: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), "photo.png")
        XCTAssertEqual(TrainingCapture.photoName(for: Data([1, 2, 3])), "photo.bin")
    }

    func testZipHoldsThePackage() throws {
        let url = try store.create(package())
        try CaptureStore.save(shot(), photo: try jpeg(), depth: depth, mask: [UInt8](repeating: 1, count: 12), in: url)
        let zip = try CaptureStore.zip(url)
        defer { try? FileManager.default.removeItem(at: zip) }
        let data = try Data(contentsOf: zip)
        XCTAssertEqual(Array(data.prefix(2)), Array("PK".utf8))
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(zip.lastPathComponent, "9x19-mm-20270115-080000.zip")
    }

    /// The stored depth map gives the same table distance the app measured from (central half, median).
    func testStoredDepthGivesTheTableDistance() throws {
        XCTAssertEqual(try XCTUnwrap(SizeEstimator.tableDistance(depth: depth, width: 16, height: 12)), 250, accuracy: 0.001)
        XCTAssertNil(SizeEstimator.tableDistance(depth: depth, width: 15, height: 12))
        XCTAssertNil(SizeEstimator.tableDistance(depth: [Float](repeating: .nan, count: 16 * 12), width: 16, height: 12))
    }

    func testMatricesAreStoredRowByRow() {
        // fx 0 cx / 0 fy cy / 0 0 1, which simd keeps as columns.
        let intrinsics = simd_float3x3(columns: (SIMD3<Float>(2794, 0, 0), SIMD3<Float>(0, 2794, 0), SIMD3<Float>(2016, 1512, 1)))
        XCTAssertEqual(TrainingRecorder.rows(intrinsics), [2794, 0, 2016, 0, 2794, 1512, 0, 0, 1])
        let extrinsics = simd_float4x3(columns: (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(5, 6, 7)))
        XCTAssertEqual(TrainingRecorder.rows(extrinsics), [1, 0, 0, 5, 0, 1, 0, 6, 0, 0, 1, 7])
    }

    func testNewPackageCarriesThePhoneDetails() {
        let p = TrainingRecorder.package(calibre: "9x19 mm", mode: .emptyCase, note: "Tuch")
        XCTAssertEqual(p.scanMode, .emptyCase)
        XCTAssertEqual(p.format, TrainingCapture.format)
        XCTAssertFalse(p.device.isEmpty)
        XCTAssertTrue(p.system.hasPrefix("iOS "))
    }

    /// A round the catalogue lacks: its name instead of a catalogue id, marked as unlisted.
    func testUnlistedRoundKeepsItsName() throws {
        let p = TrainingRecorder.package(calibre: "  11 mm Gras court ", unlisted: true, mode: .cartridge, note: "")
        XCTAssertEqual(p.calibre, "11 mm Gras court")
        XCTAssertTrue(p.isUnlisted)
        XCTAssertEqual(p.calibreName, "11 mm Gras court")
        let url = try store.create(p)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("11-mm-gras-court-"))
        let saved = try XCTUnwrap(store.packages().first)
        XCTAssertEqual(saved.package.calibre, "11 mm Gras court")
        XCTAssertTrue(saved.package.isUnlisted)
        // A name that happens to be a catalogue id still stays unlisted.
        XCTAssertTrue(TrainingRecorder.package(calibre: "9x19 mm", unlisted: true, mode: .cartridge, note: "").isUnlisted)
        XCTAssertEqual(CaptureStore.folderName(package("???")), "unlisted-20270115-080000")
    }

    /// Catalogue calibres are written as before: package.json without «unlisted», and older packages read fine.
    func testListedPackagesHaveNoUnlistedKey() throws {
        let p = TrainingRecorder.package(calibre: "7.5x55 mm Swiss (GP 11)", mode: .cartridge, note: "")
        XCTAssertFalse(p.isUnlisted)
        XCTAssertEqual(p.calibreName, "7.5x55 mm Swiss (GP 11)")
        let json = try XCTUnwrap(String(data: TrainingCapture.encoder.encode(p), encoding: .utf8))
        XCTAssertFalse(json.contains("unlisted"))
        let old = Data(#"""
            {"format": 1, "calibre": "9x19 mm", "part": "cartridge", "note": "", "created": "2026-11-04T23:30:00Z",
             "device": "", "system": "", "app": ""}
            """#.utf8)
        XCTAssertFalse(try TrainingCapture.decoder.decode(CapturePackage.self, from: old).isUnlisted)
    }

    func testFocusAsTheCameraReportsIt() {
        XCTAssertEqual(CaptureShot.Focus(minimumFocusDistance: 150, lensPosition: 0.62), .init(minimumDistance: 150, lensPosition: 0.62))
        XCTAssertNil(CaptureShot.Focus(minimumFocusDistance: -1, lensPosition: 0.5).minimumDistance, "-1: the camera doesn't say")
    }

    /// Shots from before the focus was recorded (the example package's) still read, without it.
    func testOlderShotsHaveNoFocus() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Captures", withExtension: nil))
        let saved = try XCTUnwrap(CaptureStore(root: root).packages().first { $0.url.lastPathComponent == "9x19-mm-example" })
        let shot = try XCTUnwrap(saved.shots.first).shot
        XCTAssertNil(shot.focus)
        XCTAssertEqual(shot.photo, "photo.jpg")
    }

    /// The analysis stored with a shot is what the results screen shows: the example package's
    /// photo (a 9 mm from the library, no depth) gives its shape, frame and matches.
    func testAnalysisOfAPhoto() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Captures", withExtension: nil))
        let image = try XCTUnwrap(UIImage(contentsOfFile: root.appendingPathComponent("9x19-mm-example/01/photo.jpg").path))
        let analysis = TrainingRecorder.analyse(image, scale: nil, mode: .cartridge)
        XCTAssertEqual(try XCTUnwrap(analysis.aspect), 3, accuracy: 0.5)
        XCTAssertEqual(analysis.imageLongSide, 1200)
        XCTAssertNil(analysis.size, "no depth, no size")
        XCTAssertFalse(analysis.matches.isEmpty)
        XCTAssertLessThanOrEqual(analysis.matches.count, 5)
        XCTAssertEqual(analysis.outline?.count, 4)
    }

    func testSeriesShowACartridgeOrAnEmptyCase() {
        XCTAssertEqual(TrainingCapture.parts, [.cartridge, .emptyCase])
    }
}
