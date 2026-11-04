import UIKit
import XCTest
@testable import Kaliberfinder

/// Raven's photos of known calibres on different surfaces (2026-11-04): eight 9x19 cartridges and
/// nine empty GP 11 cases and nine empty 6 mm BR Norma cases, some with shadows, tarnish or an annealed neck.
final class PhotoSetTests: XCTestCase {
    static let photos: [(name: String, calibre: String, aspect: Double)] =
        (1...8).map { (String(format: "set-9x19-%02d", $0), "9x19 mm", 3.0) }
        + (1...9).map { (String(format: "set-gp11-case-%02d", $0), "7.5x55 mm Swiss (GP 11)", 4.5) }
        + (1...9).map { (String(format: "set-6mmbr-case-%02d", $0), "6 mm BR Norma (case)", 3.3) }

    private func photo(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    /// Every photo through the analysis (on the simulator the colour cut-out, since Vision's
    /// foreground mask isn't available there), with a report in the CI log. The shapes must come
    /// close to the true calibre: before choosing the most cartridge-like patch (2026-11-04),
    /// 13 of 26 were within 10% and the worst was off ten-fold (wood grain or a shadow measured).
    func testPhotoSetMeasuresCloseToTheTruth() async throws {
        var lines: [String] = [], errors: [Double] = []
        for entry in Self.photos {
            let analysis = await PhotoAnalyzer.analyze(try photo(entry.name))
            let aspect = analysis.shape?.aspect ?? 0
            let error = abs(aspect / entry.aspect - 1)
            errors.append(error)
            lines.append(String(format: "PHOTOSET %@ truth %.1f measured %.2f error %+.0f%%",
                                entry.name, entry.aspect, aspect, 100 * (aspect / entry.aspect - 1)))
        }
        print(lines.joined(separator: "\n"))
        let close = errors.filter { $0 < 0.15 }.count
        print("PHOTOSET within 15%: \(close) of \(errors.count), worst \(Int(100 * (errors.max() ?? 0)))%")
        XCTAssertGreaterThanOrEqual(close, 17, lines.joined(separator: "\n"))
        XCTAssertLessThan(errors.max() ?? 1, 0.5, lines.joined(separator: "\n"))
    }
}
