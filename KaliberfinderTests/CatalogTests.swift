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
            if c.kind == "shot" {  // the hull opened by firing is longer than the loaded shell
                XCTAssertGreaterThanOrEqual(d.caseLength, d.overallLength, "\(c.name): opened hull shorter than the shell")
            } else {
                XCTAssertGreaterThanOrEqual(d.overallLength + 0.01, d.caseLength, "\(c.name): case longer than cartridge")
            }
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

    func testTipColourCodesComeFromCalibreData() throws {
        // GP 11: one code, the red tracer tip; every meaning and colour the catalogue uses has a title and a colour.
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        XCTAssertEqual(gp11.tipColours.map(\.colours), [["red"]])
        XCTAssertEqual(gp11.tipColours.first?.meaning, ["tracer"])
        XCTAssertEqual(gp11.tipColours.first?.countries.map(\.code), ["CH"])
        XCTAssertEqual(Cartridge.TipColour.title("tracer"), "Leuchtspur")
        XCTAssertTrue(try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm")).tipColours.isEmpty)
        let codes = CartridgeCatalog.all.flatMap(\.tipColours)
        XCTAssertGreaterThan(codes.count, 30)
        for meaning in Set(codes.flatMap(\.meaning)) {
            XCTAssertNotEqual(Cartridge.TipColour.title(meaning), meaning, "\(meaning) has no title")
        }
        for colour in Set(codes.flatMap(\.colours)) {
            XCTAssertNotEqual(Cartridge.TipColour.colourName(colour), colour, "\(colour) has no name")
            XCTAssertNotNil(TipSwatch.colours[colour], "\(colour) has no colour")
        }
    }

    func testEveryCategoryIsKnown() {
        let known = Set(CartridgeCatalog.Category.allCases.map(\.rawValue))
        for c in CartridgeCatalog.all {
            XCTAssertTrue(known.contains(c.category), "\(c.name): unknown category \(c.category)")
        }
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
        // The army's 1892 drawing (calibre-data #106), not the 54.6 misread on Raven's 1906 round.
        XCTAssertEqual(gp1890.dimensions.caseLength, 53.5, accuracy: 0.001)
        XCTAssertEqual(gp1890.dimensions.overallLength, 77.2, accuracy: 0.001)
        XCTAssertEqual(gp1890.category, CartridgeCatalog.Category.rifle.rawValue)
        XCTAssertTrue(gp1890.hasCase)
        for text in ["GP 1890", "GP 90/03", "7.5mm GP 90", "Patrone 1890", "7,5x53,5"] {
            XCTAssertTrue(CartridgeCatalog.search(text).contains { $0.id == gp1890.id }, text)
        }
        // The 1923 rework is its own round (calibre-data #104).
        XCTAssertFalse(CartridgeCatalog.search("GP 90/23").contains { $0.id == gp1890.id })
        XCTAssertTrue(CartridgeCatalog.search("GP 90/23").contains { $0.id == "7.5x54.5 mm Swiss (GP 90/23)" })
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
        XCTAssertTrue(finds("Mauser 8", "8x57 mm IS"))
        XCTAssertFalse(finds("Mauser 8", "7x57 mm Mauser"))
    }

    func testKadettenpatroneIsItsOwnRareRound() throws {
        let kp = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5 mm Kadettenpatrone"))
        XCTAssertEqual(kp.category, CartridgeCatalog.Category.rifle.rawValue)
        // The GP 90/23's 1 mm longer case (Raven's calliper: 54.6), longer overall, a jacketed round
        // nose. Not a profile twin of the GP 90/23, nor of the GP 1890 on its shorter case.
        let gp9023 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x54.5 mm Swiss (GP 90/23)"))
        let gp1890 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x53.5 mm Swiss (GP 1890)"))
        XCTAssertEqual(kp.dimensions.caseLength, gp9023.dimensions.caseLength, accuracy: 0.001)
        XCTAssertEqual(kp.dimensions.rim, gp9023.dimensions.rim, accuracy: 0.001)
        XCTAssertEqual(kp.dimensions.overallLength, 77.5, accuracy: 0.001)
        XCTAssertGreaterThan(kp.dimensions.caseLength, gp1890.dimensions.caseLength)
        XCTAssertFalse(CartridgeCatalog.sameProfile(kp, gp9023))
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

    func testLookalikeGroupsNameCatalogueCalibresOnce() throws {
        let groups = CartridgeCatalog.lookalikes
        XCTAssertGreaterThanOrEqual(groups.count, 20)
        for g in groups {
            XCTAssertGreaterThanOrEqual(g.calibres.count, 2)
            XCTAssertEqual(g.members.count, g.calibres.count, "\(g.calibres) names a calibre the catalogue lacks")
            XCTAssertFalse(g.differs.isEmpty)
        }
        let members = groups.flatMap(\.calibres)
        XCTAssertEqual(Set(members).count, members.count, "a calibre in two groups")
        let win = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".308 Winchester"))
        let group = try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: win))
        XCTAssertEqual(group.calibres, [".308 Winchester", "7.62x51 mm NATO"])
        XCTAssertEqual(group.differs, ["load"])
        XCTAssertEqual(LookalikeGroup.title("load"), "Ladung")
        // Every difference the catalogue names has a German title (and so a translation).
        for difference in Set(groups.flatMap(\.differs)) {
            XCTAssertNotEqual(LookalikeGroup.title(difference), difference, "\(difference) has no title")
        }
        let vetterli = try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: XCTUnwrap(CartridgeCatalog.cartridge(id: "10.4x38 mm R Vetterli"))))
        XCTAssertEqual(vetterli.calibres, ["10.4x38 mm R Vetterli", "10.4x38 mm R Vetterli Centrefire"])
        XCTAssertEqual(vetterli.differs.map { LookalikeGroup.title($0) }, ["Zündung"])
        XCTAssertNil(CartridgeCatalog.lookalikeGroup(of: try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))))
        // Identical-looking members compare once, at 1:1 generally too.
        XCTAssertEqual(LookalikeGroupView.compared(group.members).map(\.id), [".308 Winchester"])
        XCTAssertEqual(TrueScaleView.unique(group.members + [win]).map(\.id), [".308 Winchester"])
        let mauser = try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: XCTUnwrap(CartridgeCatalog.cartridge(id: "7x57 mm Mauser"))))
        XCTAssertEqual(mauser.differs, ["rim", "load"])
        XCTAssertGreaterThanOrEqual(LookalikeGroupView.compared(mauser.members).count, 2, "the rimmed 7x57 R stands apart")
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

    /// Settings show the calibre-data commit the catalogue was generated from (tools/generate_data.py).
    func testCatalogueNamesItsCalibreDataCommit() throws {
        let source = try XCTUnwrap(CartridgeCatalog.source)
        XCTAssertNotNil(source.commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression), source.commit)
        XCTAssertTrue(source.text.hasPrefix("\(source.commit.prefix(7)) · "), source.text)
    }

    func testCalibreDataDayKeepsItsOffset() throws {
        let json = #"{"version":1,"calibreData":{"commit":"04653a888e18b4cf5cd8d619d42f8d8501ebc369","date":"2026-11-08T17:40:47+01:00"},"cartridges":[]}"#
        let day = Date(timeIntervalSince1970: 1_794_156_047).formatted(date: .numeric, time: .omitted)
        XCTAssertEqual(CartridgeCatalog.decodeFile(Data(json.utf8))?.calibreData?.text, "04653a8 · \(day)")
        // git writes UTC as Z.
        let utc = json.replacingOccurrences(of: "17:40:47+01:00", with: "16:40:47Z")
        XCTAssertEqual(CartridgeCatalog.decodeFile(Data(utc.utf8))?.calibreData?.text, "04653a8 · \(day)")
    }

    func testUnreadableDateKeepsTheCatalogue() throws {
        let json = #"{"version":1,"calibreData":{"commit":"04653a888e18b4cf5cd8d619d42f8d8501ebc369","date":"soon"},"cartridges":[]}"#
        let file = try XCTUnwrap(CartridgeCatalog.decodeFile(Data(json.utf8)))
        XCTAssertEqual(file.calibreData?.text, "04653a8 · soon")
    }
}
