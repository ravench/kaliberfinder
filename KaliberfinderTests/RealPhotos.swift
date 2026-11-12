import UIKit
import XCTest
@testable import Kaliberfinder

/// Raven's photos in the test bundle (Fixtures/photo-*.jpg), and their analysis through the phone's
/// path, done once per run: on the CI simulator Vision finds nothing, so each analysis walks the
/// whole crop cascade and the colour cut-out, 20 to 30 s.
enum RealPhotos {
    static func image(_ name: String) throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Marker.self).url(forResource: name, withExtension: "jpg"), name)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
    }

    static func analysis(_ name: String) async throws -> PhotoAnalysis {
        try await Once.value("RealPhotos \(name)") { await PhotoAnalyzer.analyze(try image(name)) }
    }

    private final class Marker {}
}
