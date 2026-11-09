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
        for id in ["7.5x55 mm Swiss (GP 11)", "9x19 mm", ".22 LR", ".30 Super Carry"] { picks = picks.toggling(try c(id), by: .overallLength) }
        // 9x19 and .30 Super Carry are both 29.7 mm long: the narrower one (Ø 8.74 against 9.96) first.
        XCTAssertEqual(picks.map(\.id), [".22 LR", ".30 Super Carry", "9x19 mm", "7.5x55 mm Swiss (GP 11)"])
        // Tapping a pick again takes it out and leaves the others in order.
        XCTAssertEqual(picks.toggling(try c("9x19 mm"), by: .overallLength).map(\.id), [".22 LR", ".30 Super Carry", "7.5x55 mm Swiss (GP 11)"])
    }

    func testTheStandardOrderIsByCaseLength() throws {
        func c(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id) }
        // Cases 15.6, 19.15 and 20.3 mm, though the 9x19 and the .30 Super Carry are equally long loaded.
        let picks = try [c("9x19 mm"), c(".30 Super Carry"), c(".22 LR")]
        XCTAssertEqual(picks.byLength(.caseLength).map(\.id), [".22 LR", "9x19 mm", ".30 Super Carry"])
        XCTAssertEqual(picks.byLength(.overallLength).map(\.id), [".22 LR", ".30 Super Carry", "9x19 mm"])
        // A ball has no case: its whole length counts either way.
        let ball = try c(".36 Rundkugel (.375)")
        XCTAssertEqual(ball.compareLength(.caseLength), ball.dimensions.overallLength)
        // Until the user chooses, the case length.
        UserDefaults.standard.removeObject(forKey: CompareLength.key)
        XCTAssertEqual(CompareLength.current, .caseLength)
        XCTAssertEqual(CompareLength.caseLength.title, "Hülsenlänge")
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
        XCTAssertEqual(gp1890.dimensions.caseLength, 54.6, accuracy: 0.001, "the case of Raven's 1906 round, not the 53.5 of the name")
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

    func testSearchTakesWordsInAnyOrderAcrossAllNames() {
        func finds(_ query: String, _ id: String) -> Bool { CartridgeCatalog.search(query).contains { $0.id == id } }
        // Words in another order, or with words of the name left out.
        XCTAssertTrue(finds("Vetterli 10.4", "10.4x38 mm R Vetterli"))
        XCTAssertTrue(finds("10.4 Vetterli", "10.4x38 mm R Vetterli"))
        XCTAssertTrue(finds("Luger 9mm", "9x19 mm"))
        XCTAssertTrue(finds("Swiss 7.5", "7.5x55 mm Swiss (GP 11)"))
        XCTAssertTrue(finds("Revolver 1882", "7.5 mm Swiss Ordnance 1882"))
        // Each word may be in a different name: «GP 11» in the name, «K31» a search alias.
        XCTAssertTrue(finds("GP 11 K31", "7.5x55 mm Swiss (GP 11)"))
        // Only other names hold the word (search aliases, «Auch bekannt als», headstamps).
        XCTAssertTrue(finds("Parabellum", "9x19 mm"))
        XCTAssertTrue(finds("Schmidt Rubin", "7.5x53.5 mm Swiss (GP 1890)"))
        XCTAssertTrue(finds("9 mm Para", "9x19 mm"))
        // Hyphens are like spaces, accents don't matter.
        XCTAssertTrue(finds("Martini Henry", ".577/450 Martini-Henry"))
        XCTAssertTrue(finds("Mannlicher Schonauer", "6.5x54 mm Mannlicher-Schönauer"))
        // A headstamp typed as it is, where dropping "mm" joins two words.
        XCTAssertTrue(finds("357 REM MAG", ".357 Magnum"))
        // Every word must be found.
        XCTAssertEqual(CartridgeCatalog.search("Vetterli 9").map(\.id), [])
        XCTAssertEqual(CartridgeCatalog.search("Mauser 8").map(\.id), ["8x57 mm IS"])
    }

    func testSwissArmyNamesFindTheParabellumRounds() {
        func finds(_ query: String, _ id: String) -> Bool { CartridgeCatalog.search(query).contains { $0.id == id } }
        XCTAssertTrue(finds("Pist Pat 41", "9x19 mm"))
        XCTAssertTrue(finds("Pistolenpatrone 41", "9x19 mm"))
        XCTAssertTrue(finds("9 mm Pist Pat 41", "9x19 mm"))
        XCTAssertTrue(finds("Pistolenpatrone 7,65", "7.65 mm Parabellum"))
        XCTAssertFalse(finds("Pist Pat 41", "7.65 mm Parabellum"))
    }

    func testWadcutterIsItsOwnCalibreSeatedFlush() throws {
        let wc = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".32 S&W Long Wadcutter"))
        // Seated flush with the case mouth: the case is the whole round and no bullet shows from the side.
        XCTAssertEqual(wc.dimensions.overallLength, wc.dimensions.caseLength, accuracy: 0.001)
        XCTAssertNil(wc.outline.bullet)
        XCTAssertTrue(wc.hasCase)
        XCTAssertFalse(wc.rare)
        XCTAssertFalse(wc.obsolete)
        // Its own C.I.P. cartridge with a shorter case, so a row of its own next to the .32 S&W Long.
        let long = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".32 S&W Long"))
        XCTAssertLessThan(wc.dimensions.caseLength, long.dimensions.caseLength)
        for text in [".32 S&W Long WC", "32 wadcutter", "32WC"] {
            XCTAssertTrue(CartridgeCatalog.search(text).contains { $0.id == wc.id }, text)
        }
    }

    func testKadettenpatroneIsItsOwnRareRound() throws {
        let kp = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5 mm Kadettenpatrone"))
        XCTAssertEqual(kp.category, CartridgeCatalog.Category.rifle.rawValue)
        // Measured on Raven's round: the GP 1890's case (54.8 measured, drawn at 54.6), longer overall,
        // with a jacketed round nose. Not a profile twin of the GP 1890.
        let gp1890 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x53.5 mm Swiss (GP 1890)"))
        XCTAssertEqual(kp.dimensions.caseLength, gp1890.dimensions.caseLength, accuracy: 0.001)
        XCTAssertEqual(kp.dimensions.rim, gp1890.dimensions.rim, accuracy: 0.001)
        XCTAssertEqual(kp.dimensions.overallLength, 77.5, accuracy: 0.001)
        XCTAssertFalse(CartridgeCatalog.sameProfile(kp, gp1890))
        XCTAssertNil(kp.outline.bulletMaterial, "a jacket, not the GP 1890's steel cap")
        XCTAssertNil(kp.outline.patch)
        // Made for the cadet rifle only: matched only with both switches on, always found by search.
        XCTAssertTrue(kp.obsolete)
        XCTAssertTrue(kp.rare)
        XCTAssertFalse(CartridgeCatalog.matchable(includeObsolete: true).contains { $0.id == kp.id })
        XCTAssertTrue(CartridgeCatalog.matchable(includeObsolete: true, includeRare: true).contains { $0.id == kp.id })
        for text in ["Kadettenpatrone", "Kadetten-Pat", "Cart. 7,5 mm cadetti", "KG97"] {
            XCTAssertTrue(CartridgeCatalog.search(text).contains { $0.id == kp.id }, text)
        }
        XCTAssertFalse(CartridgeCatalog.search("GP 1890").contains { $0.id == kp.id })
    }

    func testNormalized() {
        XCTAssertEqual(CartridgeCatalog.normalized(" 7,5 × 55 mm "), "75x55")
        XCTAssertEqual(CartridgeCatalog.normalized(".45 ACP"), "45acp")
        XCTAssertEqual(CartridgeCatalog.normalized("Mannlicher-Schönauer"), "mannlicherschonauer")
    }

    func testGroupedKeepsCategoryOrder() {
        let groups = CartridgeCatalog.grouped(CartridgeCatalog.all).map(\.category)
        XCTAssertEqual(groups, CartridgeCatalog.Category.allCases.map(\.rawValue))
    }

    func testDecodeRejectsGarbage() {
        XCTAssertTrue(CartridgeCatalog.decode(Data("nope".utf8)).isEmpty)
    }
}
