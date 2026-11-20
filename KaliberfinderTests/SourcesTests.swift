import XCTest
@testable import Kaliberfinder

/// The calibre's sources page (Raven, 2026-11-15): calibre-data's sources, grouped by the parts of the calibre
/// page, run on the frozen fixture.
final class SourcesTests: XCTestCase {
    private static let file: CartridgeCatalog.File? = {
        guard let url = Bundle(for: SourcesTests.self).url(forResource: "catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return CartridgeCatalog.decodeFile(data)
    }()
    private let works = SourcesTests.file?.sources ?? []

    func testGP11ListsItsMeasurementSourcesFirst() throws {
        let gp11 = try Fixture.cartridge("7.5x55 mm Swiss (GP 11)")
        XCTAssertEqual(gp11.sources.map(\.parts),
                       [["mm"], ["shoulder_angle", "case_head"], ["primer"], ["bullet"], ["origin"], ["colour_codes"]])
        let measurements = try XCTUnwrap(gp11.sources.first)
        XCTAssertEqual(measurements.refs.map { works[$0.work].title },
                       ["Cartridges of the World", "C.I.P.", "Hornady Handbook of Cartridge Reloading"])
        XCTAssertEqual(measurements.refs.first?.pages, ["573"])
        XCTAssertNil(works[measurements.refs[1].work].year, "a web page has no year")
        XCTAssertNotNil(works[measurements.refs[1].work].url, "a web page opens in the browser")
    }

    /// A shop's or a load data page is named as a source but is no link (Raven, 2026-11-18): its work has no URL,
    /// and a row without one is plain text, as a book's is.
    func testShopsAreSourcesWithoutALink() throws {
        let shops = CartridgeCatalog.works.filter { ["starlinebrass.com", "ammo-one1.com", "loaddata.com"].contains($0.title ?? "") }
        XCTAssertGreaterThanOrEqual(shops.count, 16)
        XCTAssertTrue(shops.allSatisfy { $0.url == nil && $0.detail != nil }, "\(shops.filter { $0.url != nil })")
        let linked = CartridgeCatalog.works.compactMap(\.url?.host)
        XCTAssertFalse(linked.contains { $0.hasSuffix("starlinebrass.com") || $0.hasSuffix("ammo-one1.com") })
        XCTAssertGreaterThan(linked.count, 1000)
    }

    func testEveryRefNamesAWork() {
        let refs = Fixture.catalogue.flatMap { $0.sources.flatMap { $0.refs.map(\.work) } }
        XCTAssertFalse(refs.isEmpty)
        XCTAssertTrue(refs.allSatisfy(works.indices.contains))
    }

    func testABookShowsAuthorsYearAndPages() {
        let book = CartridgeCatalog.Work(title: "Military Small Arms Ammunition of the World, 1945-1980", detail: "Peter Labbett",
                                         year: 1980, url: nil, measured: nil)
        let detail = SourcesView.detail(book, pages: ["76", "77", "86"])
        XCTAssertTrue(detail.hasPrefix("Peter Labbett · 1980 · "), detail)
        XCTAssertTrue(detail.hasSuffix("76, 77, 86"), detail)
        XCTAssertEqual(SourcesView.title(book), book.title)
    }

    func testAWebPageShowsItsHostOnly() {
        let page = CartridgeCatalog.Work(title: "municion.org", detail: nil, year: nil,
                                         url: URL(string: "https://municion.org/producto/x/"), measured: nil)
        XCTAssertTrue(SourcesView.detail(page, pages: []).isEmpty, "no year, no pages: the title says it")
    }

    func testACaliperMeasurementShowsItsDay() {
        let measured = CartridgeCatalog.Work(title: nil, detail: nil, year: nil, url: nil, measured: "2026-11-08")
        XCTAssertEqual(SourcesView.title(measured), "Eigene Messung".loc)
        let day = SourcesView.detail(measured, pages: [])
        XCTAssertNotEqual(day, "2026-11-08", "the day is formatted")
        XCTAssertTrue(day.contains("8") && day.contains("11"), day)
    }

    func testHeaderNamesTheMergedParts() {
        let group = Cartridge.SourceGroup(parts: ["shoulder_angle", "case_head"], refs: [])
        XCTAssertEqual(SourcesView.header(group), "Schulterwinkel".loc + " · " + "Hülsenboden".loc)
    }

    func testCasePartNamesTheMaterial() {
        let group = Cartridge.SourceGroup(parts: ["case", "origin"], refs: [])
        XCTAssertEqual(SourcesView.header(group), "Hülsenmaterial".loc + " · " + "Herkunft".loc)
    }

    func testNoseIsTheHeadLengthForRoundAndPointedNoses() {
        // Raven 2026-11-20: the curved part in front of the straight one, round noses too (calibre-data #202).
        XCTAssertEqual(Cartridge.SourceGroup.title("nose"), "Kopflänge")
    }

    func testEveryPartHasATitle() {
        for part in ["mm", "shoulder_angle", "nose", "flat", "mouth", "crimp_length", "case_head", "primer", "bullet", "case", "origin", "colour_codes"] {
            XCTAssertNotEqual(Cartridge.SourceGroup.title(part), part, part)
        }
    }
}
