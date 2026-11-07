import XCTest
@testable import Kaliberfinder

final class CatalogTests: XCTestCase {
    func testCatalogueLoadsWithUniqueIDs() {
        let all = CartridgeCatalog.all
        XCTAssertGreaterThan(all.count, 90)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    func testDimensionsArePlausible() {
        for c in CartridgeCatalog.all {
            let d = c.dimensions
            XCTAssertGreaterThan(d.overallLength, 0, c.name)
            XCTAssertGreaterThanOrEqual(d.overallLength + 0.01, d.caseLength, "\(c.name): case longer than cartridge")
            XCTAssertGreaterThan(d.rim, 0, c.name)
            XCTAssertLessThanOrEqual(c.outline.width, max(d.rim, d.base, d.bullet) + 0.01, c.name)
            XCTAssertEqual(c.outline.height, d.overallLength, accuracy: 0.01, c.name)
            if let shoulder = d.shoulder {
                XCTAssertLessThanOrEqual(d.neck, shoulder, c.name)
            }
        }
    }

    func testPicksStandByLengthNotInTheOrderPicked() throws {
        func c(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id) }
        var picks: [Cartridge] = []
        for id in ["7.5x55 mm Swiss (GP 11)", "9x19 mm", ".22 LR", ".30 Super Carry"] { picks = picks.toggling(try c(id)) }
        // 9x19 and .30 Super Carry are both 29.7 mm long: the narrower one (Ø 8.74 against 9.96) first.
        XCTAssertEqual(picks.map(\.id), [".22 LR", ".30 Super Carry", "9x19 mm", "7.5x55 mm Swiss (GP 11)"])
        // Tapping a pick again takes it out and leaves the others in order.
        XCTAssertEqual(picks.toggling(try c("9x19 mm")).map(\.id), [".22 LR", ".30 Super Carry", "7.5x55 mm Swiss (GP 11)"])
    }

    func testKnownDimensions() throws {
        let nine = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        XCTAssertEqual(nine.dimensions.caseLength, 19.15, accuracy: 0.001)
        XCTAssertEqual(nine.dimensions.overallLength, 29.7, accuracy: 0.001)
        XCTAssertEqual(nine.dimensions.rim, 9.96, accuracy: 0.001)
        XCTAssertNil(nine.dimensions.shoulder)
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        XCTAssertEqual(gp11.dimensions.shoulder, 11.6)
        XCTAssertTrue(gp11.hasCase)
        let ball = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".44 Rundkugel (.454)"))
        XCTAssertFalse(ball.hasCase)
    }

    func testEveryCategoryIsKnown() {
        let known = Set(CartridgeCatalog.Category.allCases.map(\.rawValue))
        for c in CartridgeCatalog.all {
            XCTAssertTrue(known.contains(c.category), "\(c.name): unknown category \(c.category)")
        }
    }

    func testObsoleteCalibresAreMarked() throws {
        XCTAssertTrue(try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x53.5 mm Swiss (GP 1890)")).obsolete)
        XCTAssertFalse(try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)")).obsolete)
        XCTAssertFalse(try XCTUnwrap(CartridgeCatalog.cartridge(id: "5.6 mm GP 90")).obsolete)
    }

    func testMatchingSkipsRareCalibresUnlessSwitchedOn() {
        XCTAssertFalse(CartridgeCatalog.matchable(includeObsolete: true).contains(where: \.rare))
        XCTAssertFalse(CartridgeCatalog.matchable(includeObsolete: false).contains { $0.id == "11x59 mm R Gras" })
        XCTAssertEqual(CartridgeCatalog.matchable(includeObsolete: true, includeRare: true), CartridgeCatalog.all)
        let rareOnly = CartridgeCatalog.matchable(includeObsolete: false, includeRare: true)
        XCTAssertTrue(rareOnly.contains { $0.id == ".450 No. 2 Nitro Express" })
        XCTAssertFalse(rareOnly.contains { $0.id == "11x59 mm R Gras" }, "rare and obsolete needs both switches")
        XCTAssertTrue(CartridgeCatalog.search("Gras").contains { $0.id == "11x59 mm R Gras" })
    }

    func testMatchingSkipsObsoleteCalibresUnlessSwitchedOn() {
        let current = CartridgeCatalog.matchable(includeObsolete: false)
        XCTAssertFalse(current.isEmpty)
        XCTAssertFalse(current.contains(where: \.obsolete))
        XCTAssertFalse(current.contains { $0.id == "7.5x53.5 mm Swiss (GP 1890)" })
        XCTAssertEqual(CartridgeCatalog.matchable(includeObsolete: true), CartridgeCatalog.all.filter { !$0.rare })
        XCTAssertTrue(CartridgeCatalog.matchable(includeObsolete: true).contains { $0.id == "7.5x53.5 mm Swiss (GP 1890)" })
        // The catalogue list and search still show obsolete calibres.
        XCTAssertTrue(CartridgeCatalog.search("GP 1890").contains { $0.id == "7.5x53.5 mm Swiss (GP 1890)" })
    }

    func testSearchMatchesAliasesIgnoringSpacesDotsAndMM() {
        XCTAssertTrue(CartridgeCatalog.search("9 mm Luger").contains { $0.id == "9x19 mm" })
        XCTAssertTrue(CartridgeCatalog.search("9MM LUGER").contains { $0.id == "9x19 mm" })
        XCTAssertTrue(CartridgeCatalog.search("GP90").contains { $0.id == "5.6 mm GP 90" })
        XCTAssertTrue(CartridgeCatalog.search("win 308").contains { $0.id == ".308 Winchester" })
        XCTAssertEqual(CartridgeCatalog.search("").count, CartridgeCatalog.all.count)
        XCTAssertTrue(CartridgeCatalog.search("no such calibre").isEmpty)
    }

    func testGP1890IsSeparateFromGP11AndGP90() throws {
        let gp1890 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x53.5 mm Swiss (GP 1890)"))
        XCTAssertEqual(gp1890.dimensions.caseLength, 53.5, accuracy: 0.001)
        XCTAssertEqual(gp1890.dimensions.overallLength, 77.0, accuracy: 0.001)
        XCTAssertEqual(gp1890.category, CartridgeCatalog.Category.rifle.rawValue)
        XCTAssertTrue(gp1890.hasCase)
        for text in ["GP 1890", "GP 90/23", "7.5mm GP 90", "Patrone 1890", "7,5x53,5"] {
            XCTAssertTrue(CartridgeCatalog.search(text).contains { $0.id == gp1890.id }, text)
        }
    }

    func testGP1890HasPaperPatchedSteelCappedBullet() throws {
        let gp1890 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x53.5 mm Swiss (GP 1890)"))
        XCTAssertEqual(gp1890.outline.bulletMaterial, "steel")
        let band = try XCTUnwrap(gp1890.outline.patch.map(OutlineGeometry.parse)?.first, "paper band above the case mouth")
        let mouth = gp1890.dimensions.overallLength - gp1890.dimensions.caseLength
        let ys = band.map(\.y)
        XCTAssertEqual(ys.max() ?? 0, mouth, accuracy: 0.01, "the paper starts at the case mouth")
        XCTAssertLessThan((ys.max() ?? 0) - (ys.min() ?? 0), mouth / 2, "most of the visible bullet is the steel cap")
        // The paper band lies inside the bullet silhouette, so shape matching is unchanged by it.
        let whole = OutlineGeometry(gp1890.outline), caseOnly = OutlineGeometry(gp1890.outline, includeBullet: false)
        XCTAssertEqual(whole.polygons.count, caseOnly.polygons.count + 1)
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        XCTAssertNil(gp11.outline.patch)
        XCTAssertNil(gp11.outline.bulletMaterial)
    }

    func testNormalized() {
        XCTAssertEqual(CartridgeCatalog.normalized(" 7,5 × 55 mm "), "75x55")
        XCTAssertEqual(CartridgeCatalog.normalized(".45 ACP"), "45acp")
    }

    func testGroupedKeepsCategoryOrder() {
        let groups = CartridgeCatalog.grouped(CartridgeCatalog.all).map(\.category)
        XCTAssertEqual(groups, CartridgeCatalog.Category.allCases.map(\.rawValue))
    }

    func testDecodeRejectsGarbage() {
        XCTAssertTrue(CartridgeCatalog.decode(Data("nope".utf8)).isEmpty)
    }
}
