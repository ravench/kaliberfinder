import Foundation
import XCTest
@testable import Kaliberfinder

/// Forty-five calibres frozen from calibre-data (Fixtures/catalogue.json, written by
/// tools/catalogue_fixture.py): the matcher and catalogue tests run on them, so a data bump changes
/// no test. Rewrite the file on purpose only, when a test needs a calibre or a value that moved.
enum Fixture {
    static let catalogue: [Cartridge] = {
        guard let url = Bundle(for: Marker.self).url(forResource: "catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return CartridgeCatalog.decode(data)
    }()

    /// What matching uses with both switches off.
    static let current = CartridgeCatalog.matchable(includeObsolete: false, in: catalogue)

    static func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(catalogue.first { $0.id == id }, "\(id) is not in Fixtures/catalogue.json")
    }

    /// The calibre's own silhouette, as `ShapeMatcher.catalogue` holds it for the live catalogue.
    static func shape(_ id: String, part: ShapePart = .cartridge) throws -> ShapeMeasurement {
        try XCTUnwrap(ShapeMatcher.expected(for: cartridge(id), part: part), id)
    }

    private final class Marker {}
}
