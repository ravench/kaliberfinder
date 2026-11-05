import Foundation
import XCTest
@testable import Kaliberfinder

/// The golden set in KaliberfinderTests/Golden (see its README): shots from the private training
/// data, kept as Vision's instance mask and the phone's numbers, never the photo. Every shot goes
/// through the phone's path (subject picking, outline, neck, LiDAR size, ranking in automatic mode),
/// and the scores must stay within `tolerance` of Golden/baseline.json. Prints a GOLDEN line per
/// shot and the new baseline for the CI log.
final class GoldenSetTests: XCTestCase {
    /// What one shot gave: where its calibre ranks (nil: not listed), whether automatic mode saw
    /// the right part, and for calibres with a clear neck whether the neck was found.
    struct ShotResult: Codable, Equatable {
        var rank: Int?
        var part: Bool
        var neck: Bool?
    }

    /// Shares in percent: calibre first, calibre in the first five, part right, neck found (of the
    /// shots of calibres with a neck).
    struct Scores: Codable, Equatable {
        var top1: Double
        var top5: Double
        var part: Double
        var neck: Double

        init(_ results: [ShotResult]) {
            func share(_ hits: Int, of n: Int) -> Double { n == 0 ? 0 : (1000 * Double(hits) / Double(n)).rounded() / 10 }
            let necked = results.compactMap(\.neck)
            top1 = share(results.filter { $0.rank == 1 }.count, of: results.count)
            top5 = share(results.filter { ($0.rank ?? .max) <= 5 }.count, of: results.count)
            part = share(results.filter(\.part).count, of: results.count)
            neck = share(necked.filter { $0 }.count, of: necked.count)
        }
    }

    struct Baseline: Codable, Equatable {
        var scores: Scores
        var shots: [String: ShotResult]
    }

    /// How many percentage points a score may fall below the baseline.
    static let tolerance = 2.0

    private var root: URL {
        get throws { try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Golden", withExtension: nil), "Golden folder missing in the test bundle") }
    }

    private func golden() throws -> [SavedCapture] {
        CaptureStore(root: try root).packages().sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    func testEveryGoldenShotCanBeReplayed() throws {
        let packages = try golden()
        XCTAssertFalse(packages.isEmpty)
        for package in packages {
            let name = package.url.lastPathComponent
            XCTAssertNotNil(CartridgeCatalog.cartridge(id: package.package.calibre), "\(name): unknown calibre \(package.package.calibre)")
            XCTAssertTrue(TrainingCapture.parts.map(\.rawValue).contains(package.package.part), name)
            XCTAssertFalse(package.shots.isEmpty, name)
            for entry in package.shots {
                let shotName = "\(name)/\(entry.url.lastPathComponent)"
                let mask = try XCTUnwrap(entry.shot.mask, shotName)
                XCTAssertNotNil(mask.imageWidth, shotName)
                XCTAssertNotNil(mask.imageHeight, shotName)
                XCTAssertNotNil(CaptureStore.mask(of: entry.shot, at: entry.url), "\(shotName): mask (is Git LFS installed?)")
                XCTAssertNotNil(entry.shot.analysis, shotName)
            }
        }
    }

    /// The app repo is public: the golden set holds masks and JSON only, never a photo or depth map.
    func testTheGoldenSetHasNoPhotos() throws {
        let allowed: Set = [TrainingCapture.packageFile, TrainingCapture.shotFile, TrainingCapture.maskFile, "README.md", "baseline.json"]
        let files = FileManager.default.enumerator(at: try root, includingPropertiesForKeys: [.isDirectoryKey])?
            .compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files { XCTAssertTrue(allowed.contains(file.lastPathComponent), file.path) }
    }

    func testScoresDoNotDropBelowTheBaseline() throws {
        var results: [String: ShotResult] = [:], lines: [String] = []
        for package in try golden() {
            for entry in package.shots {
                let name = "\(package.url.lastPathComponent)/\(entry.url.lastPathComponent)"
                let (result, line) = try replay(entry, of: package.package)
                results[name] = result
                lines.append("GOLDEN \(name) \(line)")
            }
        }
        let scores = Scores(Array(results.values))
        let now = Baseline(scores: scores, shots: results)
        let json = try TrainingCapture.encoder.encode(now)
        lines.append(String(format: "GOLDEN %d shots: first %.1f%%, top 5 %.1f%%, part %.1f%%, neck %.1f%%",
                            results.count, scores.top1, scores.top5, scores.part, scores.neck))
        lines.append("GOLDEN baseline.json:\n" + String(decoding: json, as: UTF8.self))
        print(lines.joined(separator: "\n"))

        let data = try Data(contentsOf: try root.appendingPathComponent("baseline.json"))
        let baseline = try TrainingCapture.decoder.decode(Baseline.self, from: data)
        XCTAssertEqual(Set(baseline.shots.keys), Set(results.keys), "golden shots changed: update Golden/baseline.json from the GOLDEN lines")
        for (label, was, isNow) in [("first", baseline.scores.top1, scores.top1), ("top 5", baseline.scores.top5, scores.top5),
                                    ("part", baseline.scores.part, scores.part), ("neck", baseline.scores.neck, scores.neck)] {
            XCTAssertGreaterThanOrEqual(isNow, was - Self.tolerance, "\(label): \(isNow) % against \(was) % in Golden/baseline.json")
        }
        for (name, result) in results.sorted(by: { $0.key < $1.key }) where baseline.shots[name] != result {
            print("GOLDEN changed \(name): \(baseline.shots[name].map { "\($0)" } ?? "new") -> \(result)")
        }
    }

    /// The replay scales Vision's square mask to the photo it covers, as Vision does on the phone:
    /// a 40 × 10 box in a 100 × 100 mask over an 800 × 400 photo is 320 × 40 pixels there.
    func testReplayScalesTheMaskToThePhoto() throws {
        var labels = [UInt8](repeating: 0, count: 100 * 100)
        for y in 45..<55 { for x in 30..<70 { labels[y * 100 + x] = 1 } }
        let analysis = PhotoAnalyzer.analyze(instanceLabels: labels, width: 100, height: 100, imageWidth: 800, imageHeight: 400, isBrass: true)
        XCTAssertEqual(try XCTUnwrap(analysis.shape?.aspect), 8, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(analysis.lengthPixels), 320, accuracy: 10)
        XCTAssertEqual(analysis.imageLongSide, 800)
        XCTAssertTrue(analysis.isBrass)
        XCTAssertEqual(analysis.outline?.count, 4)
        XCTAssertNil(PhotoAnalyzer.analyze(instanceLabels: [UInt8](repeating: 0, count: 100 * 100), width: 100, height: 100,
                                           imageWidth: 800, imageHeight: 400, isBrass: true).shape, "nothing in the mask")
    }

    /// One shot through the phone's path, and its report line.
    private func replay(_ entry: SavedShot, of package: CapturePackage) throws -> (ShotResult, String) {
        let shot = entry.shot
        let info = try XCTUnwrap(shot.mask), labels = try XCTUnwrap(CaptureStore.mask(of: shot, at: entry.url))
        let analysis = PhotoAnalyzer.analyze(instanceLabels: labels, width: info.width, height: info.height,
                                             imageWidth: try XCTUnwrap(info.imageWidth), imageHeight: try XCTUnwrap(info.imageHeight),
                                             isBrass: shot.analysis?.isBrass ?? true)
        let size = try? analysis.size(depth: shot.scale?.depthScale).get()
        let ranked = Matcher.rank(shape: analysis.shape, size: size, mode: .auto, cartridges: CartridgeCatalog.all,
                                  brass: analysis.isBrass, limit: .max)
        let rank = ranked.firstIndex { $0.cartridge.id == package.calibre }.map { $0 + 1 }
        let cartridge = try XCTUnwrap(CartridgeCatalog.cartridge(id: package.calibre))
        let part = analysis.shape.map { ScanMode.auto.part(for: $0) == package.scanMode.part(for: $0) } ?? false
        let expected = ShapeMatcher.expected(for: cartridge, part: package.scanMode == .emptyCase ? .emptyCase : .cartridge)
        let neck = expected?.neck?.isClear == true ? analysis.shape?.neck != nil : nil
        let line = String(format: "%@ %@ rank %@ aspect %.2f (phone %.2f)%@ part %@ neck %@ first %@",
                          package.calibre, package.part, rank.map { "\($0)" } ?? "–", analysis.shape?.aspect ?? 0,
                          shot.analysis?.aspect ?? 0, size.map { String(format: " size %.1f x %.1f mm", $0.length, $0.diameter) } ?? "",
                          part ? "ok" : "wrong", neck.map { $0 ? "found" : "missed" } ?? "–", ranked.first?.cartridge.id ?? "–")
        return (ShotResult(rank: rank, part: part, neck: neck), line)
    }
}
