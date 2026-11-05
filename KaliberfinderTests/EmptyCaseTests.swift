import XCTest
import SwiftUI
@testable import Kaliberfinder

/// Empty cases, rim and neck detection, the scan mode and dropping far-off matches (SCAN-01 to SCAN-04).
final class EmptyCaseTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// Pixels inside a cartridge (or only its case), as a photo of it lying on its side would give:
    /// rotated by `angle`, `pixelsPerMM` pixels per millimetre, sampled every `step` mm.
    private func photo(_ c: Cartridge, part: ShapePart, angle: Double = 0.7, pixelsPerMM: Double = 6,
                       step: Double = 0.3) throws -> ShapeMeasurement {
        let caseOnly = part == .emptyCase
        let g = OutlineGeometry(c.outline, includeBullet: !caseOnly)
        let top = caseOnly ? c.outline.height - c.dimensions.caseLength : 0
        var points: [Point] = []
        var y = top + step / 2
        while y < c.outline.height {
            var x = step / 2
            while x < c.outline.width {
                if g.contains(Point(x: x, y: y)) {
                    points.append(Point(x: pixelsPerMM * (x * cos(angle) - y * sin(angle)) + 500,
                                        y: pixelsPerMM * (x * sin(angle) + y * cos(angle)) + 300))
                }
                x += step
            }
            y += step
        }
        return try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: pixelsPerMM * step), c.id)
    }

    // MARK: - The reported case

    func testEmptyRifleCaseFindsRifleCalibres() throws {
        // Sampled every 0.15 mm: on a 0.3 mm grid the rounding of the body width outweighs the
        // difference to similar cases now that heads and shoulders follow the drawings.
        let shape = try photo(cartridge(".308 Winchester"), part: .emptyCase, step: 0.15)
        XCTAssertEqual(ScanMode.auto.part(for: shape), .emptyCase)
        let matches = Matcher.rank(shape: shape, limit: .max)
        // Without a scale the GP 1890 case (same shape, only 2 mm longer) can tie with the .308 twins.
        let top = Set(matches.prefix(3).map(\.cartridge.id))
        XCTAssertTrue(top.isSuperset(of: [".308 Winchester", "7.62x51 mm NATO"]), top.sorted().joined(separator: ", "))
        XCTAssertTrue(matches.allSatisfy { $0.part == .emptyCase })
        // Before, .500 S&W Magnum and .357 Magnum came first: no handgun calibre may be listed.
        let handgun = matches.filter { $0.cartridge.category == CartridgeCatalog.Category.handgun.rawValue }
        XCTAssertTrue(handgun.isEmpty, handgun.map(\.cartridge.id).joined(separator: ", "))
    }

    func testAlmostEveryEmptyCaseIsAmongTheFirstFive() throws {
        // Without a scale some straight cases are the same tube (.32 S&W Long vs .44 Magnum),
        // so with over 200 calibres a few rank lower. Checked with every calibre matching uses,
        // obsolete ones too; rare ones are left out of matching (CartridgeCatalog.matchable).
        var missed: [String] = []
        let pool = CartridgeCatalog.matchable(includeObsolete: true)
        let cases = pool.enumerated().filter { $0.element.hasCase }
        for (i, c) in cases {
            let shape = try photo(c, part: .emptyCase, angle: Double(i % 7) * 0.45, pixelsPerMM: 5 + Double(i % 4))
            let ids = Matcher.rank(shape: shape, cartridges: pool, limit: 5).map(\.cartridge.id)
            if !ids.contains(c.id) { missed.append("\(c.id): \(ids)") }
        }
        XCTAssertLessThanOrEqual(Double(missed.count) / Double(cases.count), 0.05, missed.joined(separator: "\n"))
    }

    func testLiDARSizeSeparatesLookAlikeCases() throws {
        // Without a scale the .32 S&W Long case can rank behind .44 Magnum (the same tube, longer).
        // With the size from LiDAR, calibres more than 3 mm off are dropped.
        let c = try cartridge(".32 S&W Long")
        let d = c.dimensions
        let size = MeasuredSize(length: d.caseLength, diameter: d.base, lengthError: 1, diameterError: 0.25)
        let matches = Matcher.rank(shape: try photo(c, part: .emptyCase), size: size, limit: 5)
        XCTAssertEqual(matches.first?.cartridge.id, c.id, "\(matches.map(\.cartridge.id))")
        XCTAssertFalse(matches.contains { $0.cartridge.id == ".44 Magnum" })
    }

    func testLoadedCartridgesAreNotTakenForCases() throws {
        // The Nagant bullet sits wholly inside the case and a blank has none, so the loaded round looks like an empty case.
        // Sampled every 0.5 mm, not 0.3 mm: the whole catalogue twice takes a third of the time.
        for c in CartridgeCatalog.all where c.hasCase && c.kind != "shot" && c.dimensions.overallLength > c.dimensions.caseLength {
            let shape = try photo(c, part: .cartridge, step: 0.5)
            XCTAssertEqual(ScanMode.auto.part(for: shape), .cartridge, c.id)
            XCTAssertEqual(ScanMode.auto.part(for: try photo(c, part: .emptyCase, step: 0.5)), .emptyCase, c.id)
        }
    }

    func testModeOverridesTheDetection() throws {
        let shape = try photo(cartridge(".308 Winchester"), part: .emptyCase)
        XCTAssertEqual(ScanMode.cartridge.part(for: shape), .cartridge)
        XCTAssertTrue(Matcher.rank(shape: shape, mode: .cartridge).allSatisfy { $0.part == .cartridge })
        let loaded = try photo(cartridge("9x19 mm"), part: .cartridge)
        XCTAssertEqual(ScanMode.emptyCase.part(for: loaded), .emptyCase)
        XCTAssertEqual(Set(ScanMode.allCases.map(\.rawValue)).count, 3)
    }

    /// Each photo starts on «Automatisch», whatever was picked for an earlier photo
    /// (the choice used to be saved under "scanMode" and stuck to every later photo).
    func testEveryPhotoStartsOnAutomatic() throws {
        UserDefaults.standard.set(ScanMode.cartridge.rawValue, forKey: "scanMode")
        defer { UserDefaults.standard.removeObject(forKey: "scanMode") }
        let view = MatchesView(photo: UIImage())
        let state = try XCTUnwrap(Mirror(reflecting: view).children.first { $0.label == "_mode" }?.value as? State<ScanMode>)
        XCTAssertEqual(state.wrappedValue, .auto)
    }

    // MARK: - Rim and neck

    func testRimAndNeckAreDetected() throws {
        let rifle = try XCTUnwrap(photo(cartridge(".308 Winchester"), part: .emptyCase).mouthFirst().features)
        XCTAssertTrue(rifle.hasNeck)
        XCTAssertFalse(rifle.isRimmed)
        let revolver = try XCTUnwrap(photo(cartridge(".38 Special"), part: .emptyCase).mouthFirst().features)
        XCTAssertFalse(revolver.hasNeck)
        XCTAssertTrue(revolver.isRimmed)
        let pistol = try XCTUnwrap(photo(cartridge("9x19 mm"), part: .emptyCase).mouthFirst().features)
        XCTAssertFalse(pistol.hasNeck)
        XCTAssertFalse(pistol.isRimmed)
        let rimmedRifle = try XCTUnwrap(photo(cartridge(".303 British"), part: .emptyCase).mouthFirst().features)
        XCTAssertTrue(rimmedRifle.hasNeck)
        XCTAssertTrue(rimmedRifle.isRimmed)
    }

    func testRimAndNeckRuleOutCalibres() throws {
        let rimmed = try photo(cartridge(".38 Special"), part: .emptyCase)
        let rimless = try XCTUnwrap(ShapeMatcher.caseCatalogue["9x19 mm"])
        XCTAssertNil(ShapeMatcher.distance(rimmed, to: rimless, part: .emptyCase))
        let bottleneck = try photo(cartridge(".223 Remington"), part: .emptyCase)
        let straight = try XCTUnwrap(ShapeMatcher.caseCatalogue[".357 Magnum"])
        XCTAssertNil(ShapeMatcher.distance(bottleneck, to: straight, part: .emptyCase))
        // The own calibre always fits, either way round.
        let own = try XCTUnwrap(ShapeMatcher.caseCatalogue[".223 Remington"])
        XCTAssertNotNil(ShapeMatcher.distance(bottleneck, to: own, part: .emptyCase))
        XCTAssertNotNil(ShapeMatcher.distance(bottleneck.reversed(), to: own, part: .emptyCase))
        // Shapes built by hand have no slice widths, so nothing is ruled out.
        let plain = ShapeMeasurement(aspect: 3, profile: ShapeMatcher.fractions.map { _ in 1 })
        XCTAssertTrue(ShapeMatcher.featuresFit(plain, own, part: .emptyCase))
        XCTAssertNil(plain.features)
    }

    func testCaseShapesExistOnlyForCalibresWithACase() throws {
        XCTAssertEqual(ShapeMatcher.caseCatalogue.count, CartridgeCatalog.all.filter(\.hasCase).count)
        XCTAssertNil(ShapeMatcher.expected(for: try cartridge(".58 Minié"), part: .emptyCase))
        let empty = try XCTUnwrap(ShapeMatcher.caseCatalogue[".308 Winchester"])
        XCTAssertEqual(empty.aspect, 51.2 / 11.9, accuracy: 0.1)
        XCTAssertTrue(try XCTUnwrap(empty.features).isFlatEnd)
        XCTAssertFalse(try XCTUnwrap(ShapeMatcher.catalogue[".308 Winchester"]?.features).isFlatEnd)
    }

    // MARK: - Far-off matches

    func testFarOffMatchesAreDropped() throws {
        for id in ["9x19 mm", ".45 ACP", ".308 Winchester", ".38 Special"] {
            for part in [ShapePart.cartridge, .emptyCase] {
                let matches = Matcher.rank(shape: try photo(cartridge(id), part: part), limit: .max)
                let distances = matches.compactMap(\.shapeDistance)
                XCTAssertEqual(distances.count, matches.count)
                let best = try XCTUnwrap(distances.min(), id)
                XCTAssertTrue(distances.allSatisfy { $0 <= Matcher.maxShapeDistance && $0 <= best + Matcher.maxBehindBest }, id)
                XCTAssertTrue(matches.allSatisfy { $0.shapeFit != .poor }, id)
            }
        }
    }

    func testSizeOfAnEmptyCaseIsComparedWithTheCaseLength() throws {
        let c = try cartridge(".308 Winchester")
        let d = c.dimensions
        let size = MeasuredSize(length: d.caseLength, diameter: d.base, lengthError: 1, diameterError: 0.3)
        XCTAssertEqual(Matcher.deviation(of: c, from: size, part: .emptyCase), 0)
        XCTAssertGreaterThan(Matcher.deviation(of: c, from: size, part: .cartridge), 5)
        // An empty .308 case measured with LiDAR: still listed, with a good size fit.
        let matches = Matcher.rank(shape: try photo(c, part: .emptyCase), size: size)
        XCTAssertEqual(matches.first { $0.cartridge.id == c.id }?.sizeFit, .good)
        // A size far off drops the calibre.
        let huge = MeasuredSize(length: 99, diameter: 20.4, lengthError: 1, diameterError: 0.3)
        XCTAssertFalse(Matcher.rank(shape: try photo(c, part: .emptyCase), size: huge, limit: .max).contains { $0.cartridge.id == c.id })
    }

    // MARK: - Match screen

    func testFeaturesText() throws {
        let rifle = try photo(cartridge(".308 Winchester"), part: .emptyCase)
        XCTAssertEqual(MatchesView.featuresText(rifle, mode: .auto),
                       String(format: "Erkannt: %@".loc, ["leere Hülse".loc, "Flaschenhals".loc, "ohne Rand".loc].joined(separator: " · ")))
        let revolver = try photo(cartridge(".38 Special"), part: .emptyCase)
        XCTAssertTrue(try XCTUnwrap(MatchesView.featuresText(revolver, mode: .auto)).contains("gerade Hülse".loc))
        XCTAssertTrue(try XCTUnwrap(MatchesView.featuresText(revolver, mode: .auto)).contains("mit Rand".loc))
        let loaded = try photo(cartridge("9x19 mm"), part: .cartridge)
        XCTAssertEqual(MatchesView.featuresText(loaded, mode: .auto),
                       String(format: "Erkannt: %@".loc, ["Patrone".loc, "ohne Rand".loc].joined(separator: " · ")))
        XCTAssertNil(MatchesView.featuresText(ShapeMeasurement(aspect: 3, profile: [1]), mode: .auto))
        let analysis = PhotoAnalysis(shape: rifle)
        XCTAssertEqual(MatchesView.notes(for: analysis).count, 1)
    }

    func testNewTextsAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        for mode in ScanMode.allCases { XCTAssertNotNil(en[mode.title], mode.title) }
        XCTAssertEqual(en["Leere Hülse"], "Empty case")
        XCTAssertEqual(en["Flaschenhals"], "bottleneck")
        XCTAssertEqual(en["Was liegt im Bild?"], "What is in the photo?")
    }
}
