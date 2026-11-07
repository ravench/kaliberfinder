import Foundation
import XCTest
@testable import Kaliberfinder

/// The golden set in KaliberfinderTests/Golden (see its README): shots from the private training
/// data, kept as Vision's instance mask and the phone's numbers, never the photo. Every shot goes
/// through the phone's path (subject picking, outline, neck, LiDAR size, ranking in automatic mode),
/// and the scores (`Evaluation`, shared with the evaluation tool) must stay within `tolerance` of
/// Golden/baseline.json. Prints a GOLDEN line per shot and the new baseline for the CI log.
final class GoldenSetTests: XCTestCase {
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
        var results: [String: Evaluation.ShotResult] = [:], lines: [String] = []
        for package in try golden() {
            for entry in package.shots {
                let name = "\(package.url.lastPathComponent)/\(entry.url.lastPathComponent)"
                let (shot, line) = try replay(entry, named: name, of: package.package)
                results[name] = shot.result
                lines.append("GOLDEN \(name) \(line)")
            }
        }
        let now = Evaluation.Baseline(results)
        let scores = now.scores
        let json = try TrainingCapture.encoder.encode(now)
        lines.append("GOLDEN " + Evaluation.summary(scores, count: results.count))
        lines.append("GOLDEN baseline.json:\n" + (String(bytes: json, encoding: .utf8) ?? ""))
        print(lines.joined(separator: "\n"))

        let data = try Data(contentsOf: try root.appendingPathComponent("baseline.json"))
        let baseline = try TrainingCapture.decoder.decode(Evaluation.Baseline.self, from: data)
        XCTAssertEqual(Set(baseline.shots.keys), Set(results.keys), "golden shots changed: update Golden/baseline.json from the GOLDEN lines")
        // A baseline from before the list rows were counted would gate the phone's list against
        // ranks among all calibres, and "of all" against nothing.
        XCTAssertTrue(baseline.shots.values.contains(where: \.hasRows) || baseline.shots.values.allSatisfy { $0.rank == nil },
                      "Golden/baseline.json has no list rows: update it from the GOLDEN lines")
        for (label, was, isNow) in [("first", baseline.scores.top1, scores.top1), ("top 5", baseline.scores.top5, scores.top5),
                                    ("first, obsolete on", baseline.scores.top1Obsolete, scores.top1Obsolete),
                                    ("top 5, obsolete on", baseline.scores.top5Obsolete, scores.top5Obsolete),
                                    ("first, all on", baseline.scores.top1All, scores.top1All),
                                    ("top 5, all on", baseline.scores.top5All, scores.top5All),
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
        let analysis = PhotoAnalyzer.analyze(instanceLabels: labels, mask: (100, 100), image: (800, 400), isBrass: true)
        XCTAssertEqual(try XCTUnwrap(analysis.shape?.aspect), 8, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(analysis.lengthPixels), 320, accuracy: 10)
        XCTAssertEqual(analysis.imageLongSide, 800)
        XCTAssertTrue(analysis.isBrass)
        XCTAssertEqual(analysis.outline?.count, 4)
        XCTAssertNil(PhotoAnalyzer.analyze(instanceLabels: [UInt8](repeating: 0, count: 100 * 100), mask: (100, 100), image: (800, 400),
                                           isBrass: true).shape, "nothing in the mask")
    }

    /// One shot through the phone's path, and its report line.
    private func replay(_ entry: SavedShot, named name: String, of package: CapturePackage) throws -> (Evaluation.Shot, String) {
        let shot = entry.shot
        let info = try XCTUnwrap(shot.mask), labels = try XCTUnwrap(CaptureStore.mask(of: shot, at: entry.url))
        let image = (width: try XCTUnwrap(info.imageWidth), height: try XCTUnwrap(info.imageHeight))
        let analysis = PhotoAnalyzer.analyze(instanceLabels: labels, mask: (info.width, info.height), image: image,
                                             isBrass: shot.analysis?.isBrass ?? true)
        let scored = Evaluation.shot(name, analysis: analysis, depth: shot.scale?.depthScale, package: package)
        let result = scored.result
        let rows = [result.row, result.rowObsolete, result.rowAll].map { $0.map { "\($0)" } ?? "–" }.joined(separator: "/")
        let line = String(format: "%@ %@ rows %@ rank %@ aspect %.2f (phone %.2f)%@ part %@ neck %@ first %@",
                          package.calibre, package.part, rows, result.rank.map { "\($0)" } ?? "–",
                          analysis.shape?.aspect ?? 0,
                          shot.analysis?.aspect ?? 0, scored.size.map { String(format: " size %.1f x %.1f mm", $0.length, $0.diameter) } ?? "",
                          result.part ? "ok" : "wrong", result.neck.map { $0 ? "found" : "missed" } ?? "–", scored.first ?? "–")
        return (scored, line)
    }
}
