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
        // The .32 S&W Long Wadcutter, seated flush, is the same tube 0.13 mm shorter: no photo or LiDAR
        // size tells the two apart, so they share the top two places, in either order.
        let ids = matches.map(\.cartridge.id)
        XCTAssertEqual(Set(ids.prefix(2)), [c.id, ".32 S&W Long Wadcutter"], "\(ids)")
        XCTAssertFalse(matches.contains { $0.cartridge.id == ".44 Magnum" })
    }

    func testLoadedCartridgesAreNotTakenForCases() throws {
        // The Nagant bullet sits wholly inside the case and a blank has none, so the loaded round looks like an empty case.
        // Sampled every 0.3 mm: at 0.5 mm five short rounds (.22 Long, .32 S&W Long …) come out as empty cases.
        for c in CartridgeCatalog.all where c.hasCase && c.kind != "shot" && c.dimensions.overallLength > c.dimensions.caseLength {
            let shape = try photo(c, part: .cartridge)
            XCTAssertEqual(ScanMode.auto.part(for: shape), .cartridge, c.id)
            XCTAssertEqual(ScanMode.auto.part(for: try photo(c, part: .emptyCase)), .emptyCase, c.id)
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

    /// Each photo starts on what the app detects, whatever was picked for an earlier photo
    /// (the choice used to be saved under "scanMode" and stuck to every later photo).
    func testEveryPhotoStartsOnTheDetection() throws {
        UserDefaults.standard.set(ScanMode.cartridge.rawValue, forKey: "scanMode")
        defer { UserDefaults.standard.removeObject(forKey: "scanMode") }
        let view = MatchesView(photo: UIImage())
        let state = try XCTUnwrap(Mirror(reflecting: view).children.first { $0.label == "_override" }?.value as? State<ScanMode?>)
        XCTAssertNil(state.wrappedValue)
    }

    /// The picker has no «Automatisch» segment: it highlights what the app detected, and the
    /// other segment overrides it.
    func testPickerHighlightsTheDetectedPart() throws {
        XCTAssertEqual(ScanMode.choices, [.cartridge, .emptyCase])
        let empty = try photo(cartridge(".308 Winchester"), part: .emptyCase)
        let loaded = try photo(cartridge("9x19 mm"), part: .cartridge)
        XCTAssertEqual(ScanMode.detected(in: empty), .emptyCase)
        XCTAssertEqual(ScanMode.detected(in: loaded), .cartridge)
        for shape in [empty, loaded] {
            let detected = ScanMode.detected(in: shape)
            XCTAssertEqual(detected.part(for: shape), ScanMode.auto.part(for: shape))
            let other = try XCTUnwrap(ScanMode.choices.first { $0 != detected })
            XCTAssertNotEqual(other.part(for: shape), ScanMode.auto.part(for: shape))
        }
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
        // A head narrower than the calibre's (rounded off or in shadow) only costs the rim penalty.
        let rimlessPhoto = try photo(cartridge("9x19 mm"), part: .emptyCase)
        let rimmedCase = try XCTUnwrap(ShapeMatcher.caseCatalogue[".38 Special"])
        let narrow = try XCTUnwrap(ShapeMatcher.distance(rimlessPhoto, to: rimmedCase, part: .emptyCase))
        let plainDistance = [rimlessPhoto, rimlessPhoto.reversed()].map { ShapeMatcher.distance($0, rimmedCase) }.min() ?? 0
        XCTAssertGreaterThanOrEqual(narrow, plainDistance + ShapeMatcher.rimPenalty - 1e-9)
        // A bottleneck case the other way round shows its neck where the head should be: as narrow as a
        // clear neck (7.62x39 mm, 0.76 of the body), it is no head, even within a rim's width of one.
        let shortNeck = try photo(cartridge("7.62x39 mm"), part: .emptyCase)
        let straightRimless = try XCTUnwrap(ShapeMatcher.caseCatalogue[".45 ACP"])
        XCTAssertLessThanOrEqual(try XCTUnwrap(shortNeck.mouthFirst().features).mouth, NeckShape.clearUpTo)
        XCTAssertFalse(ShapeMatcher.featuresFit(shortNeck.mouthFirst().reversed(), straightRimless, part: .emptyCase))
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

    /// A case mouth whose first slice is only partly filled (the mask rounds its corners) is still
    /// flat; a bullet's tip narrows over several slices. Widths from the second look at a .45 ACP case
    /// and a 9 mm round (2026-11-05).
    func testAMouthWithARoundedCornerIsFlat() {
        func shape(_ front: [Double]) -> ShapeMeasurement {
            ShapeMatcher.measurement(aspect: 2, relativeWidths: front + Array(repeating: 1, count: ShapeMatcher.bins - front.count))
        }
        XCTAssertEqual(shape([0.82, 0.97, 0.99, 0.99]).features?.isFlatEnd, true)
        XCTAssertEqual(ScanMode.auto.part(for: shape([0.82, 0.97, 0.99, 0.99])), .emptyCase)
        XCTAssertEqual(shape([0.33, 0.44, 0.53, 0.60]).features?.isFlatEnd, false)
        XCTAssertEqual(shape([0.40, 0.57, 0.67, 0.73]).features?.isFlatEnd, false, ".45 ACP round nose")
        XCTAssertEqual(shape([0.30, 0.62, 0.70, 0.78]).features?.isFlatEnd, false, "a flat nose behind a partly filled slice")
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
        for mode in ScanMode.choices { XCTAssertNotNil(en[mode.title], mode.title) }
        XCTAssertNil(en["Automatisch"])
        XCTAssertEqual(en["Leere Hülse"], "Empty case")
        XCTAssertEqual(en["Flaschenhals"], "bottleneck")
        XCTAssertEqual(en["Was liegt im Bild?"], "What is in the photo?")
    }
}
