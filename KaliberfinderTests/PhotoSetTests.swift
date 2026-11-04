import UIKit
import Vision
import XCTest
@testable import Kaliberfinder

/// Raven's photos of known calibres on different surfaces (2026-11-04): eight 9x19 cartridges and
/// nine empty GP 11 cases, some with shadows, tarnish or an annealed neck.
final class PhotoSetTests: XCTestCase {
    static let photos: [(name: String, calibre: String, aspect: Double)] =
        (1...8).map { (String(format: "set-9x19-%02d", $0), "9x19 mm", 3.0) }
        + (1...9).map { (String(format: "set-gp11-case-%02d", $0), "7.5x55 mm Swiss (GP 11)", 4.5) }

    private func photo(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    /// A report of how each photo is measured today, for tuning the cut-out (see the CI log).
    func testReportMeasurements() async throws {
        var lines: [String] = []
        for entry in Self.photos {
            let image = try photo(entry.name)
            let cg = try XCTUnwrap(image.cgImage)
            let request = VNGenerateForegroundInstanceMaskRequest()
            let vision = (try? VNImageRequestHandler(cgImage: cg).perform([request])) != nil && request.results?.first != nil
            let analysis = await PhotoAnalyzer.analyze(image)
            var colour = "-"
            if let rgb = PhotoAnalyzer.rgbImage(cg), let points = ColorSegmenter.segment(rgb),
               let shape = ShapeMatcher.measure(points) {
                colour = String(format: "%.2f", shape.aspect)
            }
            let aspect = analysis.shape.map { String(format: "%.2f", $0.aspect) } ?? "-"
            lines.append("PHOTOSET \(entry.name) truth \(entry.aspect) vision \(vision) analysis \(aspect) colour \(colour)")
        }
        print(lines.joined(separator: "\n"))
        XCTAssertEqual(lines.count, Self.photos.count)
    }
}
