import UIKit
import XCTest
@testable import Kaliberfinder

/// Every training capture package in KaliberfinderTests/Captures (see its README): complete, and
/// measured close to the calibre it was tagged with. Prints a CAPTURE line per shot for the CI log.
final class CaptureFixtureTests: XCTestCase {
    private func captures() throws -> [SavedCapture] {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Captures", withExtension: nil), "Captures folder missing in the test bundle")
        return CaptureStore(root: root).packages()
    }

    func testEveryPackageIsComplete() throws {
        let captures = try captures()
        XCTAssertFalse(captures.isEmpty)
        for capture in captures {
            let name = capture.url.lastPathComponent
            XCTAssertEqual(capture.package.format, TrainingCapture.format, name)
            XCTAssertNotNil(CartridgeCatalog.cartridge(id: capture.package.calibre), "\(name): unknown calibre \(capture.package.calibre)")
            XCTAssertTrue(TrainingCapture.parts.map(\.rawValue).contains(capture.package.part), name)
            XCTAssertFalse(capture.shots.isEmpty, name)
            for entry in capture.shots {
                let shotName = "\(name)/\(entry.url.lastPathComponent)"
                XCTAssertNotNil(UIImage(contentsOfFile: entry.url.appendingPathComponent(entry.shot.photo).path), shotName)
                if entry.shot.depth != nil { XCTAssertNotNil(CaptureStore.depth(of: entry.shot, at: entry.url), "\(shotName): depth") }
                if entry.shot.mask != nil { XCTAssertNotNil(CaptureStore.mask(of: entry.shot, at: entry.url), "\(shotName): mask") }
                // The stored depth gives the distance the app measured with.
                if let scale = entry.shot.scale, let info = entry.shot.depth, let depth = CaptureStore.depth(of: entry.shot, at: entry.url) {
                    let distance = try XCTUnwrap(SizeEstimator.tableDistance(depth: depth, width: info.width, height: info.height), shotName)
                    XCTAssertEqual(distance, scale.tableDistance, accuracy: 0.5, shotName)
                }
            }
        }
    }

    /// Each shot through today's analysis, like the photo set: the shape must come within 50 % of the
    /// tagged calibre's. The report shows where the calibre ranks, to follow detection changes.
    func testCapturesMeasureCloseToTheirCalibre() async throws {
        var lines: [String] = [], failures: [String] = []
        for capture in try captures() {
            let mode = capture.package.scanMode
            let catalogue = mode == .emptyCase ? ShapeMatcher.caseCatalogue : ShapeMatcher.catalogue
            let truth = try XCTUnwrap(catalogue[capture.package.calibre], capture.package.calibre).aspect
            for entry in capture.shots {
                let image = try XCTUnwrap(UIImage(contentsOfFile: entry.url.appendingPathComponent(entry.shot.photo).path))
                let analysis = await PhotoAnalyzer.analyze(image)
                let size = try? analysis.size(depth: entry.shot.scale?.depthScale).get()
                let ranked = Matcher.rank(shape: analysis.shape, size: size, mode: mode, cartridges: CartridgeCatalog.all,
                                          brass: analysis.isBrass, limit: .max)
                let rank = ranked.firstIndex { $0.cartridge.id == capture.package.calibre }.map { "\($0 + 1)" } ?? "–"
                let aspect = analysis.shape?.aspect ?? 0
                let line = String(format: "CAPTURE %@/%@ %@ truth %.2f measured %.2f error %+.0f%% rank %@%@",
                                  capture.url.lastPathComponent, entry.url.lastPathComponent, capture.package.calibre,
                                  truth, aspect, 100 * (aspect / truth - 1), rank,
                                  size.map { String(format: " size %.1f x %.1f mm", $0.length, $0.diameter) } ?? "")
                lines.append(line)
                if abs(aspect / truth - 1) >= 0.5 { failures.append(line) }
            }
        }
        print(lines.joined(separator: "\n"))
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
