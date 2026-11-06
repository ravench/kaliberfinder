import XCTest
@testable import Kaliberfinder

/// The ends of a lying cartridge stand higher than its axis and look further out from above (`EndRise`).
final class EndRiseTests: XCTestCase {
    /// iPhone 17 Pro main camera, as the training captures record it, at the 1600 px the analysis uses.
    private let focal = 2961.0 * 1600 / 4032
    private let depth = { (distance: Double) in DepthScale(tableDistance: distance, focalLength: 2961, referenceLongSide: 4032) }

    private func cartridge(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id)) }

    /// The analysis of `id` lying 20 cm under the camera.
    private func photo(_ id: String, part: ShapePart, distance: Double = 200) throws -> PhotoAnalysis {
        let seen = SeenFromAbove.silhouette(of: try cartridge(id), part: part, distance: distance, focal: focal)
        let measured = try XCTUnwrap(ShapeMatcher.measureWithLength(seen.points, pixelSize: seen.pixelSize))
        return PhotoAnalysis(shape: measured.shape, lengthPixels: measured.length, imageLongSide: 1600)
    }

    func testNothingRisesWithoutPerspectiveOrSlices() throws {
        let shape = try XCTUnwrap(ShapeMatcher.caseCatalogue[".45 ACP"])
        XCTAssertEqual(EndRise.factor(shape, perspective: 0), 1)
        XCTAssertEqual(EndRise.factor(ShapeMeasurement(aspect: 3, profile: shape.profile), perspective: 0.06), 1, "no slice widths")
        XCTAssertEqual(EndRise.factor(ShapeMeasurement(aspect: 1, profile: shape.profile, widths: shape.widths), perspective: 0.06), 1, "end view")
        XCTAssertEqual(PhotoAnalysis(shape: nil).endRise(depth: depth(200)), 1)
    }

    /// At 20 cm both ends of an empty .45 ACP case rise half a diameter above its axis (about 3 %);
    /// a loaded round's tip lies on the axis, so only its head rises (half as much).
    func testAnEmptyCaseRisesAtBothEndsALoadedRoundAtOne() throws {
        let p = 12.0 / (200 - 6)
        let empty = EndRise.factor(try XCTUnwrap(ShapeMatcher.caseCatalogue[".45 ACP"]), perspective: p)
        let loaded = EndRise.factor(try XCTUnwrap(ShapeMatcher.catalogue[".45 ACP"]), perspective: p)
        XCTAssertEqual(empty, 1.032, accuracy: 0.003)
        XCTAssertEqual(loaded, 1.016, accuracy: 0.003)
    }

    /// The LiDAR size of an empty .45 ACP case seen from 20 cm: 22.8 mm long, not the 23.5 mm its
    /// outline spans at the axis's height.
    func testTheSizeLeavesOutTheRise() throws {
        let analysis = try photo(".45 ACP", part: .emptyCase)
        let size = try analysis.size(depth: depth(200)).get()
        XCTAssertEqual(size.length, 22.8, accuracy: 0.25)
        XCTAssertEqual(size.diameter, 12, accuracy: 0.25)
        let shape = try XCTUnwrap(analysis.shape), lengthPixels = try XCTUnwrap(analysis.lengthPixels)
        let raw = try SizeEstimator.estimate(lengthPixels: lengthPixels, aspect: shape.aspect, imageLongSide: 1600, depth: depth(200)).get()
        XCTAssertGreaterThan(raw.length, 23.3, "without the end rise")
    }

    /// What the matching compares: the length over the width at the axis's height, as the catalogue's
    /// outline has it, with LiDAR and without (the phone's 1× camera assumed).
    func testTheShapeAtTheAxisMatchesTheCatalogue() throws {
        for (id, part) in [(".45 ACP", ShapePart.emptyCase), ("9x19 mm", .cartridge), ("7.5x55 mm Swiss (GP 11)", .emptyCase)] {
            let analysis = try photo(id, part: part)
            let expected = try XCTUnwrap((part == .emptyCase ? ShapeMatcher.caseCatalogue : ShapeMatcher.catalogue)[id]).aspect
            let raw = try XCTUnwrap(analysis.shape).aspect
            XCTAssertGreaterThan(raw / expected, 1.005, id)
            for depth in [depth(200), nil] {
                XCTAssertEqual(try XCTUnwrap(analysis.shapeAtAxis(depth: depth)).aspect / expected, 1, accuracy: 0.008, id)
            }
        }
    }
}
