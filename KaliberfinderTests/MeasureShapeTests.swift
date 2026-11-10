import XCTest
@testable import Kaliberfinder

/// The shape dropdown and comparing every match on the dimensions screen (MEAS-04, MEAS-05).
final class MeasureShapeTests: XCTestCase {
    private func ids(_ matches: [DimensionMatch]) -> [String] { matches.map(\.cartridge.id) }

    func testShapeNarrowsTheList() {
        // Raven's case: 32.3 mm long.
        let any = DimensionMatcher.rank(MeasuredDimensions(overallLength: 32.3))
        XCTAssertTrue(ids(any).contains(".17 HMR"))
        XCTAssertTrue(ids(any).contains(".45 ACP"))
        let straight = DimensionMatcher.rank(MeasuredDimensions(overallLength: 32.3, shape: .straight))
        XCTAssertFalse(ids(straight).contains(".17 HMR"))
        XCTAssertTrue(straight.allSatisfy { $0.cartridge.dimensions.shoulder == nil && $0.cartridge.hasCase })
        let bottleneck = DimensionMatcher.rank(MeasuredDimensions(overallLength: 32.3, shape: .bottleneck))
        // The nearest bottleneck cases: .17 HMR (34.67 mm since its C.I.P. sheet) and 7.65 mm Parabellum (34.8 mm).
        XCTAssertTrue(ids(bottleneck).prefix(2).contains(".17 HMR"), "\(ids(bottleneck))")
        XCTAssertTrue(bottleneck.allSatisfy { $0.cartridge.dimensions.shoulder != nil })
    }

    func testShapeAloneRanksNothing() {
        XCTAssertTrue(MeasuredDimensions(shape: .bottleneck).isEmpty)
        XCTAssertTrue(DimensionMatcher.rank(MeasuredDimensions(shape: .bottleneck)).isEmpty)
    }

    func testShapesOfKnownCalibres() throws {
        func c(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id) }
        XCTAssertTrue(CaseShape.straight.fits(try c("9x19 mm")))
        XCTAssertTrue(CaseShape.straight.fits(try c("12/70")))
        XCTAssertFalse(CaseShape.straight.fits(try c(".44 Rundkugel (.454)")))
        XCTAssertTrue(CaseShape.bottleneck.fits(try c(".308 Winchester")))
        XCTAssertTrue(CaseShape.bottleneck.fits(try c(".30-30 Winchester")))
        XCTAssertFalse(CaseShape.bottleneck.fits(try c(".45 ACP")))
        for c in CartridgeCatalog.all { XCTAssertTrue(CaseShape.any.fits(c)) }
    }

    func testCompareTakesEveryMatch() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 32.3))
        let compare = DimensionMatcher.toCompare(matches)
        // .45 ACP, .32 S&W Long, .38 Super and 10 mm Auto (and others) are all within 1 mm. (The .22 WMR
        // is 34.3 mm long since calibre-data's municion.org check, the .17 HMR 34.67 mm since its C.I.P.
        // sheet, so they no longer are.)
        XCTAssertTrue(Set(compare.map(\.id)).isSuperset(of: [".45 ACP", ".32 S&W Long", ".38 Super", "10 mm Auto"]),
                      "\(compare.map(\.id))")
        XCTAssertTrue(compare.allSatisfy { c in matches.first { $0.cartridge == c }?.fit != .poor })
        XCTAssertEqual(MeasureView.compareTitle(matches: matches, selected: 0),
                       String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, compare.count))
        XCTAssertEqual(MeasureView.compareTitle(matches: matches, selected: 2), String(format: "1:1 vergleichen (%lld)".loc, 2))
    }

    func testCompareFallsBackToTheBestThree() {
        // 200 mm fits nothing: the best three are still offered.
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 200))
        XCTAssertTrue(matches.allSatisfy { $0.fit == .poor })
        XCTAssertEqual(Set(DimensionMatcher.toCompare(matches).map(\.id)), Set(ids(matches).prefix(3)))
        XCTAssertEqual(DimensionMatcher.toCompare(matches).map(\.id), DimensionMatcher.toCompare(matches).byLength().map(\.id), "by length")
        XCTAssertEqual(MeasureView.compareTitle(matches: matches, selected: 0), "Die besten drei 1:1 vergleichen".loc)
        XCTAssertTrue(DimensionMatcher.toCompare([]).isEmpty)
    }

    func testShapeTitlesAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertEqual(CaseShape.allCases.map { en[$0.title] }, ["Any shape", "Straight case", "Bottleneck case"])
        XCTAssertEqual(en["Form"], "Shape")
    }
}
