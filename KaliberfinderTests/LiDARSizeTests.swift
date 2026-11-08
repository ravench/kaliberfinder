import XCTest
@testable import Kaliberfinder

/// LIDAR-08: the size calculation and its use in ranking, on recorded-style values.
final class LiDARSizeTests: XCTestCase {
    /// iPhone 15 Pro main camera: 4032 px long side, focal length about 2794 px.
    private let camera = (focal: 2794.0, reference: 4032.0)
    /// The analysis scales photos down to 1600 px on the long side.
    private let imageLongSide = 1600.0

    private func depth(_ distance: Double) -> DepthScale {
        DepthScale(tableDistance: distance, focalLength: camera.focal, referenceLongSide: camera.reference)
    }

    /// Pixel extents a cartridge of `length` × `diameter` mm lying on a table `distance` mm away would have.
    private func pixels(length: Double, diameter: Double, distance: Double, longSide: Double = 1600) -> (length: Double, aspect: Double) {
        let f = camera.focal * longSide / camera.reference
        let axis = distance - diameter / 2
        return (length * f / axis, length / diameter)
    }

    private func estimate(length: Double, diameter: Double, distance: Double) throws -> MeasuredSize {
        let p = pixels(length: length, diameter: diameter, distance: distance)
        return try SizeEstimator.estimate(lengthPixels: p.length, aspect: p.aspect, imageLongSide: imageLongSide, depth: depth(distance)).get()
    }

    // MARK: - Size from depth

    func testRecoversLengthAndDiameter() throws {
        for (length, diameter) in [(77.5, 12.6), (29.69, 9.93), (25.4, 5.7)] {
            for distance in [200.0, 250.0, 300.0] {
                let size = try estimate(length: length, diameter: diameter, distance: distance)
                XCTAssertEqual(size.length, length, accuracy: 0.01, "\(length) at \(distance)")
                XCTAssertEqual(size.diameter, diameter, accuracy: 0.01, "\(diameter) at \(distance)")
            }
        }
    }

    func testFocalLengthFollowsTheImageSize() throws {
        let p = pixels(length: 71.1, diameter: 11.9, distance: 250, longSide: 800)
        let size = try SizeEstimator.estimate(lengthPixels: p.length, aspect: p.aspect, imageLongSide: 800, depth: depth(250)).get()
        XCTAssertEqual(size.length, 71.1, accuracy: 0.01)
    }

    func testOutlineIsHalfADiameterAboveTheTable() throws {
        // Measuring at the table distance would make a GP 11 look about 2.5 % too long.
        let p = pixels(length: 77.5, diameter: 12.6, distance: 250)
        let f = camera.focal * imageLongSide / camera.reference
        let naive = p.length * 250 / f
        let size = try estimate(length: 77.5, diameter: 12.6, distance: 250)
        XCTAssertGreaterThan(naive - size.length, 1.5)
    }

    func testUncertaintyGrowsWithDistance() throws {
        let near = try estimate(length: 71.1, diameter: 11.9, distance: 200)
        let far = try estimate(length: 71.1, diameter: 11.9, distance: 400)
        XCTAssertGreaterThan(far.lengthError, near.lengthError)
        XCTAssertGreaterThan(near.lengthError, 0.5)
        XCTAssertLessThan(near.lengthError, 3)
        XCTAssertLessThan(near.diameterError, near.lengthError)
    }

    func testFailures() {
        let p = pixels(length: 71.1, diameter: 11.9, distance: 250)
        XCTAssertEqual(SizeEstimator.estimate(lengthPixels: p.length, aspect: p.aspect, imageLongSide: imageLongSide, depth: nil), .failure(.noDepth))
        XCTAssertEqual(SizeEstimator.estimate(lengthPixels: 0, aspect: p.aspect, imageLongSide: imageLongSide, depth: depth(250)), .failure(.noDepth))
        XCTAssertEqual(SizeEstimator.estimate(lengthPixels: p.length, aspect: p.aspect, imageLongSide: imageLongSide, depth: depth(600)), .failure(.outOfRange))
        XCTAssertEqual(SizeEstimator.estimate(lengthPixels: p.length, aspect: p.aspect, imageLongSide: imageLongSide, depth: depth(80)), .failure(.outOfRange))
        XCTAssertEqual(SizeEstimator.estimate(lengthPixels: 50, aspect: 1.1, imageLongSide: imageLongSide, depth: depth(250)), .failure(.endView))
    }

    func testTableDistanceIsTheMedianOfValidSamples() throws {
        // Table at 25 cm, a few samples on the cartridge (closer) and some dropouts.
        var samples = [Float](repeating: 0.25, count: 90) + [Float](repeating: 0.24, count: 6)
        samples += [.nan, 0, .infinity, -1]
        XCTAssertEqual(try XCTUnwrap(SizeEstimator.tableDistance(samples: samples)), 250, accuracy: 0.001)
        XCTAssertNil(SizeEstimator.tableDistance(samples: [0.25, .nan, .nan, 0]))
        XCTAssertNil(SizeEstimator.tableDistance(samples: []))
    }

    // MARK: - Guidance

    func testGuidance() {
        XCTAssertEqual(LiDARGuidance.state(distance: nil, tilt: 0), .noDepth)
        XCTAssertEqual(LiDARGuidance.state(distance: 120, tilt: 0), .tooClose)
        XCTAssertEqual(LiDARGuidance.state(distance: 500, tilt: 0), .tooFar)
        XCTAssertEqual(LiDARGuidance.state(distance: 250, tilt: 20), .tilted)
        XCTAssertEqual(LiDARGuidance.state(distance: 250, tilt: 3), .ready)
        XCTAssertEqual(LiDARGuidance.state(distance: 250, tilt: nil), .ready)
    }

    func testTiltFromGravity() {
        XCTAssertEqual(LiDARGuidance.tilt(gravityX: 0, y: 0, z: -1), 0, accuracy: 1e-9)
        XCTAssertEqual(LiDARGuidance.tilt(gravityX: 0, y: -1, z: 0), 90, accuracy: 1e-9)
        let ten = 10 * Double.pi / 180
        XCTAssertEqual(LiDARGuidance.tilt(gravityX: sin(ten), y: 0, z: -cos(ten)), 10, accuracy: 1e-9)
        XCTAssertEqual(LiDARGuidance.tilt(gravityX: 0, y: 0, z: 0), 90)
    }

    // MARK: - Ranking (LIDAR-05)

    private func size(of id: String, error: Double = 1) throws -> MeasuredSize {
        let d = try XCTUnwrap(CartridgeCatalog.cartridge(id: id)).dimensions
        return MeasuredSize(length: d.overallLength, diameter: d.base, lengthError: error, diameterError: error / 4)
    }

    func testSizeDecidesBetweenSimilarShapes() throws {
        let shape = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        let nine = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        // The best shape match that differs in size from 9x19 by more than the tolerance.
        let other = try XCTUnwrap(Matcher.rank(shape: shape, limit: .max).map(\.cartridge).first {
            abs($0.dimensions.overallLength - nine.dimensions.overallLength) > 3
        })
        let matches = Matcher.rank(shape: shape, size: try size(of: other.id))
        XCTAssertEqual(matches.first?.cartridge.id, other.id)
        XCTAssertEqual(matches.first?.sizeFit, .good)
        XCTAssertNotEqual(matches.first { $0.cartridge.id == "9x19 mm" }?.sizeFit, .good)
    }

    /// The size deviation shown is what lies beyond the length and diameter tolerances, averaged.
    func testDeviationIsWhatLiesBeyondTheTolerances() throws {
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        let d = gp11.dimensions
        let shape = try XCTUnwrap(ShapeMatcher.catalogue[gp11.id])
        func deviation(_ size: MeasuredSize) -> Double? {
            Matcher.rank(shape: shape, size: size, mode: .cartridge, cartridges: [gp11], limit: 1).first?.sizeDeviation
        }
        let close = MeasuredSize(length: d.overallLength / Matcher.lengthScaleWhole + 1.5, diameter: d.base / Matcher.diameterScale,
                                 lengthError: 2, diameterError: 0.5)
        XCTAssertEqual(try XCTUnwrap(deviation(close)), 0, accuracy: 1e-9)
        let off = MeasuredSize(length: d.overallLength / Matcher.lengthScaleWhole + 4, diameter: d.base / Matcher.diameterScale + 1.5,
                               lengthError: 2, diameterError: 0.5)
        XCTAssertEqual(try XCTUnwrap(deviation(off)),
                       ((4 * Matcher.lengthScaleWhole - Matcher.lengthTolerance) + (1.5 * Matcher.diameterScale - Matcher.diameterTolerance)) / 2,
                       accuracy: 1e-9)
    }

    func testSizeIsIgnoredForRoundSilhouettes() throws {
        let disc = ShapeMeasurement(aspect: 1, profile: ShapeMatcher.fractions.map { _ in 1 })
        let matches = Matcher.rank(shape: disc, size: try size(of: "9x19 mm"))
        XCTAssertTrue(matches.allSatisfy { $0.sizeDeviation == nil })
    }

    /// From silhouette pixels through depth to the ranking: a GP 11 photographed from 25 cm, as the
    /// camera sees it (`SeenFromAbove`).
    func testPhotoWithDepthEndToEnd() throws {
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        let distance = 250.0
        let f = camera.focal * imageLongSide / camera.reference
        let seen = SeenFromAbove.silhouette(of: gp11, distance: distance, focal: f, step: 0.25)
        let measured = try XCTUnwrap(ShapeMatcher.measureWithLength(seen.points, pixelSize: seen.pixelSize))
        let analysis = PhotoAnalysis(shape: measured.shape, lengthPixels: measured.length, imageLongSide: imageLongSide)
        let size = try analysis.size(depth: depth(distance)).get()
        XCTAssertEqual(size.length, gp11.dimensions.overallLength, accuracy: 0.5)
        XCTAssertEqual(size.diameter, gp11.dimensions.base, accuracy: 0.6)
        let matches = Matcher.rank(shape: analysis.shape, size: analysis.rawSize(depth: depth(distance)),
                                   perspective: analysis.perspective(depth: depth(distance)))
        XCTAssertEqual(matches.first?.cartridge.id, gp11.id)
        XCTAssertEqual(matches.first?.sizeFit, .good)
        XCTAssertTrue(MatchesView.reason(for: try XCTUnwrap(matches.first)).contains(" · "))
    }

    // MARK: - Match screen (LIDAR-06)

    func testMeasuredTextIsRoundedInTheChosenUnit() {
        let size = MeasuredSize(length: 77.4, diameter: 12.6, lengthError: 2, diameterError: 0.6)
        let metric = MatchesView.measuredText(size, unit: .metric)
        XCTAssertTrue(metric.contains(LengthUnit.metric.format(77.5)), metric)
        XCTAssertTrue(metric.contains(LengthUnit.metric.format(12.5)), metric)
        let imperial = MatchesView.measuredText(size, unit: .imperial)
        XCTAssertTrue(imperial.contains("3.045") || imperial.contains("3,045"), imperial)
        XCTAssertTrue(imperial.hasSuffix(" in"), imperial)
    }

    func testNotesSayWhenTheSizeIsMissing() {
        let side = ShapeMeasurement(aspect: 6, profile: ShapeMatcher.fractions.map { _ in 1 })
        let analysis = PhotoAnalysis(shape: side, lengthPixels: 600, imageLongSide: imageLongSide)
        XCTAssertTrue(MatchesView.notes(for: analysis).isEmpty)
        XCTAssertEqual(MatchesView.notes(for: analysis, depth: depth(250)).count, 1)
        XCTAssertEqual(MatchesView.notes(for: analysis, depth: depth(900)), ["Abstand ausserhalb 12–45 cm: Grösse nicht gemessen, Treffer nur nach Form.".loc])
        let noShape = PhotoAnalysis(shape: nil)
        XCTAssertEqual(noShape.size(depth: depth(250)), .failure(.endView))
        XCTAssertEqual(noShape.size(depth: nil), .failure(.noDepth))
    }
}
