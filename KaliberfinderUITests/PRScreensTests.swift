// One stop per screen, so the tour grows with every pull request: two that each fit under the limit would fail main's lint together.
// swiftlint:disable file_length
import UIKit
import XCTest

/// A tour of the main screens, one screenshot per stop, run on a pull request and its base (PR screens in the Build job).
/// A pull request that changes a screen the tour does not reach adds a stop.
final class PRScreensTests: XCTestCase {
    private var application: XCUIApplication!
    private var launched = false
    /// The app, launched when a stop first touches it: a stop that needs launch arguments adds them to `application`
    /// before, so each stop launches the app once.
    private var app: XCUIApplication {
        if !launched { launched = true; application.launch() }
        return application
    }

    override func setUp() {
        // A broken stop should not cost the screenshots of the others.
        continueAfterFailure = true
        application = XCUIApplication()
        application.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
    }

    /// Types `text` into the search field of the screen, when it has one (a trailing return hides the keyboard).
    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) { field.tap(); field.typeText(text) }
    }

    func testTour() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        snap("01-Start")
        scroll()
        snap("02-Start-unten")
        scroll(up: false)

        if open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]) {
            snap("06-Einstellungen")
            if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bildschirm")).firstMatch) {
                snap("06d-Bildschirm-kalibrieren")
                app.navigationBars["Bildschirm kalibrieren"].buttons.firstMatch.tap()
            }
            scroll()
            snap("06b-Einstellungen-unten")  // version and calibre-data commit
            if open(app.buttons["Entwickleroptionen"].firstMatch) {
                snap("06c-Entwickleroptionen")
                app.navigationBars["Entwickleroptionen"].buttons.firstMatch.tap()  // back() would hit the home bar's gear
            }
            app.buttons["Fertig"].firstMatch.tap()
        }
        if open(app.buttons["Masse eingeben"].firstMatch) {
            snap("03-Masse-eingeben")
            // The outlines beside the shape and head choices, and the sketch as the choices say (TestFlight 2026-11-17).
            menuStop("Hülsenform", choice: "Gerade", "03a-Masse-Form")
            menuStop("Randform", choice: "Gürtelhülse", "03a-Masse-Randform")
            snap("03a-Masse-Skizze-gerade-Guertel")
            back()
        }
        if open(app.buttons["Alle Kaliber"].firstMatch) {
            snap("04-Alle-Kaliber")
            search("9x19")
            // A row opens its calibre's page; the group is a row on that page (Raven, 2026-11-13).
            if open(app.staticTexts["9x19 mm"].firstMatch) {
                snap("05-Kaliber")
                if open(app.buttons["Masszeichnung anzeigen"].firstMatch) {
                    snap("05c-Masszeichnung")
                    back()
                }
                scroll()
                snap("05-Kaliber-unten")  // origin, prevalence and tags sit below the measurements
            }
        }
    }

    /// Measurements typed by hand, 29.7 mm long with a 9 mm bullet: the 9x19 group is one row of the results
    /// (Raven, 2026-11-13). The values come as launch arguments: the number pad does not go away on the simulator.
    func testMeasuredMatches() {
        application.launchArguments += ["-screenTourLength", "29.7", "-screenTourBullet", "9.0"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch) else { return }
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "No results for the launch arguments")
        snap("03b-Masse-Treffer")  // the 9x19 group's row leads
        scroll()
        snap("03b-Masse-Treffer-unten")
    }

    /// The number pad has no return key: «Fertig» above it and a tap beside the fields put it away, and the fields
    /// keep the focus when the next one is tapped (TestFlight 2026-11-19).
    func testNumberPad() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch), open(app.textFields.element(boundBy: 3)) else { return }
        app.textFields.element(boundBy: 3).typeText("29.7")
        guard open(app.textFields.element(boundBy: 1)) else { return }
        app.textFields.element(boundBy: 1).typeText("9")
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "Typed values gave no results")
        snap("03i-Masse-Tastatur")
        guard open(app.buttons["Fertig"].firstMatch) else { return }
        XCTAssertTrue(app.buttons["Fertig"].waitForNonExistence(timeout: 5), "«Fertig» left the number pad up")
        guard open(app.textFields.element(boundBy: 0)), app.buttons["Fertig"].waitForExistence(timeout: 5) else { return XCTFail("No number pad") }
        app.textFields.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0, dy: -4)).tap()  // the sketch above it
        XCTAssertTrue(app.buttons["Fertig"].waitForNonExistence(timeout: 5), "A tap beside the fields left the number pad up")
    }

    /// The groups' switch off (Raven, 2026-11-13): the 9x19 and the Glisenti as rows of their own, each named
    /// after the group, and both drawn at 1:1.
    func testUngroupedMatches() {
        application.launchArguments += ["-screenTourLength", "29.7", "-screenTourBullet", "9.0", "-groupSizeGroups", "NO"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch) else { return }
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "No results for the launch arguments")
        snap("03c-Masse-Treffer-ungruppiert")
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden 1:1")).firstMatch),
           app.navigationBars["1:1"].waitForExistence(timeout: 5) {
            snap("03c-Masse-1zu1-ungruppiert")
        }
    }

    /// A group goes by calibre-data's name, and its row or column by a calibre it lists (review 2026-11-13): 34.6 mm long
    /// with a 7.85 mm bullet lists «7.63x25 mm» (was the obsolete «.30 Borchardt», hidden but ranked). The .38 Auto
    /// group of the old values, 34.3 mm and 8.8 mm, is cut since the list goes like a photo's (TestFlight 2026-11-17).
    func testGroupNames() {
        application.launchArguments += ["-screenTourLength", "34.6", "-screenTourBullet", "7.85"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch) else { return }
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "No results for the launch arguments")
        scroll(toRowAbove: "Mögliche Kaliber")
        // The group's row carries the family's name since calibre-data #181, never a member the switches hide.
        XCTAssertTrue(app.staticTexts["7.63x25 mm"].exists, "The Mauser's group is not listed under its family name")
        XCTAssertFalse(app.staticTexts[".38 ACP"].exists || app.staticTexts[".30 Borchardt"].exists, "A row is called after a calibre it does not list")
        snap("03d-Masse-Treffer-Gruppennamen")
        // The 7.63x25 mm group fits roughly: its column at 1:1.
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden 1:1")).firstMatch) {
            if app.navigationBars["1:1"].waitForExistence(timeout: 5) { snap("03e-Masse-1zu1-Gruppenname") }
            back()
        }
        // The group's page, then a member's page with its «Gruppe» row.
        guard open(app.staticTexts["7.63x25 mm"].firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["Gruppe 7.63x25 mm"].waitForExistence(timeout: 5), "The group page did not open")
        snap("03f-Gruppe-mit-Familienname")
        guard open(app.staticTexts["7.63x25 mm Mauser"].firstMatch),
              app.navigationBars["7.63x25 mm Mauser"].waitForExistence(timeout: 5) else { return }
        snap("03g-Kaliber-Gruppenzeile")
    }

    /// A group's row goes to its best match (Raven, 2026-11-22). 35.2 mm long with a 7.9 mm bullet is a 7.62x25 mm
    /// Tokarev; with the obsolete and rare calibres switched on, its row was drawn and rated as the group's parent, the
    /// .30 Borchardt, 1.2 mm off and not among the 1:1 button's, then as the Mauser, 0.4 mm off (review 2026-11-13).
    func testGroupRowOfANearerMember() {
        application.launchArguments += ["-screenTourLength", "35.2", "-screenTourBullet", "7.9",
                                        "-includeObsoleteCalibres", "YES", "-includeRareCalibres", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch) else { return }
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "No results for the launch arguments")
        scroll(toRowAbove: "Mögliche Kaliber")
        // The 7.5 FK: rare and well sourced, so the developer switch does not hide it (the 8 mm Rast-Gasser is cut, 0.65 mm behind).
        XCTAssertTrue(app.staticTexts["7.5 FK"].exists, "No rare calibre is listed: the switches' launch arguments did not arrive")
        // The row's own label, not the screen's.
        let group = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "7.63x25 mm")).firstMatch
        XCTAssertTrue(group.exists, "The 7.63x25 mm group's row is not on the screen")
        XCTAssertTrue(group.label.contains("Passt genau"), "The 7.63x25 mm row is not rated as its Tokarev: \(group.label)")
        snap("03h-Masse-Treffer-Gruppe-passt")
    }

    /// Calibres picked long, short, middle stand by length on the 1:1 screen.
    func testPickAndCompare() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch), open(app.buttons["Auswählen"].firstMatch) else { return }
        snap("19a-Auswahl-leer")  // the same list as «Alle Kaliber», with a circle per row, before anything is picked
        search("9x")
        // While typing, «Abbrechen» stays in the navigation bar (Raven, 2026-11-20: it went away).
        XCTAssertTrue(app.navigationBars.buttons["selectButton"].exists, "The selection button is gone while searching")
        snap("19b-Auswahl-Suche")
        for (query, name) in [("GP 11", "7.5x55 mm Swiss (GP 11)"), ("9x19", "9x19 mm"), (".45 ACP", ".45 ACP")] {
            // Clears the previous query; return hides the keyboard, so the rows can be tapped.
            search(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + query + "\n")
            _ = open(app.staticTexts[name].firstMatch)
        }
        snap("19-Auswahl")  // the last pick ticked, the count of all three on the button
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1:1 vergleichen")).firstMatch),
           app.navigationBars["1:1"].waitForExistence(timeout: 5) {
            snap("20-Auswahl-1zu1")
        }
    }

    /// The dimensioned drawing of a bottleneck rifle round (with its shoulder) and its sources, then of a belted magnum in inches,
    /// of a case whose rim stands on a foot, of the GP 90 with its nose-length source, of the .45 Colt's flat and of the 6.8/11 blank.
    func testMeasurementDrawings() {
        for (query, name, unit, shot) in [("GP 11", "7.5x55 mm Swiss (GP 11)", "metric", "34-Masszeichnung-GP11"),
                                          ("300 Win Mag", ".300 Winchester Magnum", "imperial", "35-Masszeichnung-Zoll"),
                                          // A rim on a foot: the rim's extension lines start at the rim (2026-11-17).
                                          ("11x59", "11x59 mm R Gras", "metric", "35b-Masszeichnung-Gras"),
                                          // A spitzer whose nose length is measured: its own «Kopflänge» source (calibre-data #197).
                                          ("GP 90", "5.6 mm GP 90", "metric", "35c-Masszeichnung-GP90"),
                                          // A flat nose (AECC flat width) and a crimped blank: their own source rows (calibre-data #204, #205).
                                          ("45 Colt", ".45 Colt", "metric", "35e-Masszeichnung-45Colt"),
                                          ("6.8/11", "6.8/11", "metric", "35g-Masszeichnung-6-8-11")] {
            application.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH", "-lengthUnit", unit]
            launched = false  // launched again with this unit
            XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
            guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
            search(query + "\n")
            guard open(app.staticTexts[name].firstMatch) else { return }
            if query == "GP 11" {
                // The colour codes of calibre-data (tip and bases) sit under the measurements (Raven, 2026-11-11).
                scroll(toRowAbove: "Zündhütchen")
                snap("39-GP11-Farbcodes")
                scroll()  // the «Quellen» row at the end of the page (Raven, 2026-11-15)
                snap("39b-GP11-Quellenzeile")
                scroll(up: false)
            }
            guard open(app.buttons["Masszeichnung anzeigen"].firstMatch) else { return }
            snap(shot)
            // The drawing's book button opens the calibre's sources, the measurements' first.
            let sourcesShot = ["GP 11": "34b-Quellen-GP11", "GP 90": "35d-Quellen-GP90", "45 Colt": "35f-Quellen-45Colt", "6.8/11": "35h-Quellen-6-8-11"][query]
            if let sourcesShot, open(app.navigationBars.buttons["Quellen"].firstMatch) {
                XCTAssertTrue(app.navigationBars["Quellen"].waitForExistence(timeout: 5), "The sources page did not open")
                snap(sourcesShot)
            }
        }
    }

    /// Primer-ring colour codes on a calibre page: the .303 British's pre-NATO British code (Raven, 2026-11-11).
    func testPrimerRingColourCodes() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search(".303 British\n")
        guard open(app.staticTexts[".303 British"].firstMatch) else { return }
        scroll(toRowAbove: "Zündhütchen")
        snap("40-303-Zuendhuetchenringe")
    }

    /// A hollow point's cavity, shaded with a bold dashed line inside the full nose: the .357 SIG (TestFlight 2026-11-16/17).
    func testHollowPoint() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("357 SIG\n")
        guard open(app.staticTexts[".357 SIG"].firstMatch) else { return }
        snap("46-357-SIG-Hohlspitze")
    }

    /// A blank closed inside the case (9 mm P.A.K.): no bullet diameter on its page or in its drawing.
    func testClosedBlank() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("PA Blanc\n")
        guard open(app.staticTexts["9 mm PA Blanc"].firstMatch) else { return }
        scroll(toRowAbove: "Gesamtlänge") // «Masse» whole: the bullet's row was its last but one
        snap("41-Knallpatrone-PAK")
        scroll(up: false)
        if open(app.buttons["Masszeichnung anzeigen"].firstMatch) {
            snap("41b-Knallpatrone-PAK-Masszeichnung")
        }
    }

    /// Loose balls in other materials: the steel BB and the plastic airsoft BBs.
    func testBBs() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("BB\n")
        snap("08-BBs")
        if open(app.staticTexts["6 mm Airsoft-BB"].firstMatch) {
            snap("09-Airsoft-BB")
        }
    }

    /// The .32 S&W family side by side, with the flush-seated wadcutter that shows only its case.
    func testWadcutter() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("32 S&W\n")
        snap("24-32-SW")
        if open(app.staticTexts[".32 S&W Long Wadcutter"].firstMatch) {
            snap("25-32-SW-Long-Wadcutter")
        }
    }

    /// The cannon rounds behind «Kanonenkaliber zeigen» (Raven, 2026-11-15: the same rules as every calibre): a complete
    /// one has its drawing, its tag, its 1:1 and its dimensioned drawing.
    func testCannonCalibres() {
        application.launchArguments += ["-showCannonCalibres", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("30x1\n")
        XCTAssertTrue(app.staticTexts["30x173 mm GAU-8"].waitForExistence(timeout: 5), "the cannon rounds are not listed")
        snap("45-Kanonen-Suche")
        guard open(app.staticTexts["30x173 mm GAU-8"].firstMatch), app.navigationBars["30x173 mm GAU-8"].waitForExistence(timeout: 5) else { return }
        snap("45b-Kanone-GAU-8")
        if open(app.buttons["In Originalgrösse anzeigen"].firstMatch), app.navigationBars["1:1"].waitForExistence(timeout: 5) {
            snap("45c-Kanone-1zu1")
        }
    }

    /// The Swiss cadet round, found by the name on its box, with its own drawing; sourced since calibre-data #163,
    /// the stop keeps the developer switch «Unbelegte Kaliber zeigen» on for the «Unbelegt» tag that follows.
    func testKadettenpatrone() {
        application.launchArguments += ["-showUnsourcedCalibres", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("Kadetten\n")
        if open(app.staticTexts["7.5 mm Kadettenpatrone"].firstMatch) {
            snap("26-Kadettenpatrone")
            app.navigationBars.buttons.firstMatch.tap()
        }
        // An unsourced calibre's rows carry the «Unbelegt» tag (Raven, 2026-11-15).
        search(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Mars\n")
        if app.staticTexts[".360 Mars"].waitForExistence(timeout: 5) { snap("26b-Unbelegt-Tag") }
    }

    /// A NATO round: the alliance's flag is drawn, as no emoji exists (calibre-data #51).
    func testNatoFlag() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("5.56\n")
        snap("27-NATO")
        if open(app.staticTexts["5.56x45 mm NATO"].firstMatch) {
            scroll()
            snap("27-NATO-Kaliber-unten") // the Herkunft row with the drawn flag
        }
    }

    /// The calibre picker of a new training series finds a calibre by its other names too, and shows them.
    func testTrainingCalibreSearch() {
        application.launchArguments += ["-trainingCaptureEnabled", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]),
              developerOptions(),
              open(app.buttons["Trainingsdaten aufnehmen"].firstMatch),
              open(app.buttons["Neue Aufnahmeserie"].firstMatch),
              open(app.staticTexts["Fotografiertes Kaliber"].firstMatch) else { return }
        search("Schmidt Rubin\n")
        XCTAssertTrue(app.staticTexts["7.5x53.5 mm Swiss (Patrone Modell 1890)"].waitForExistence(timeout: 5), "not found by another name")
        snap("23-Trainingsdaten-Kalibersuche")
    }

    /// A new training series of a round the catalogue lacks: searched in vain, then «Nicht in der Liste»,
    /// named after the search.
    func testTrainingUnlistedRound() {
        application.launchArguments += ["-trainingCaptureEnabled", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]),
              developerOptions(),
              open(app.buttons["Trainingsdaten aufnehmen"].firstMatch),
              open(app.buttons["Neue Aufnahmeserie"].firstMatch),
              open(app.staticTexts["Fotografiertes Kaliber"].firstMatch) else { return }
        search("Gras court\n")
        snap("24-Trainingsdaten-nicht-in-Liste")
        guard open(app.buttons["Nicht in der Liste"].firstMatch) else { return }
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Gras court", "named after the search")
        snap("25-Trainingsdaten-unbekannte-Patrone")
    }

    /// Cases that are not brass as first issued (developer switch), side and bottom: lacquered steel, brass body on a steel head, paper case in a brass cup.
    func testCaseMaterials() {
        application.launchArguments += ["-showOriginalMaterials", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        for (query, name, shot) in [("5.45", "5.45x39 mm", "10-Stahlhuelse"), ("Fury", ".277 SIG Fury", "11-Hybridhuelse"),
                                    ("Snider", ".577 Snider", "12-Papierhuelse")] {
            // Clears the previous query; return hides the keyboard, whose search field would cover the row (the bar stays since #281).
            search(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + query + "\n")
            if open(app.staticTexts[name].firstMatch) {
                snap(shot)
                back()
            }
        }
    }

    /// The matches for one of Raven's photos (an empty GP 11 case), with the measured frame and the
    /// detected neck and taper drawn over it. Then its matches at 1:1, by case length.
    func testPhotoMatches() {
        photoMatches("set-gp11-case-02", shot: "07-Foto-Treffer", compareShot: "17-Foto-Huelse-1zu1")
    }

    /// A loaded 9 mm: the outline follows its round bullet nose. Then all its matches at 1:1, by overall length.
    func testLoadedCartridgePhoto() {
        photoMatches("photo-9x19-wood", shot: "13-Foto-Patrone", compareShot: "14-Foto-1zu1")
        // The 9x19 stands towards the end of the row: drag until it shows, with its group tag (Raven, 2026-11-13).
        guard app.navigationBars["1:1"].exists else { return }
        let nine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "9x19 mm")).firstMatch
        let screen = app.windows.firstMatch.frame
        for _ in 0..<6 where !(nine.exists && screen.contains(nine.frame)) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
                .dragWithoutFling(to: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)))
        }
        XCTAssertTrue(nine.exists && screen.contains(nine.frame), "9x19 not on screen after the drags")
        snap("14b-Foto-1zu1-9x19")
    }

    /// One of Raven's empty 6 mm BR cases: its outline ends flat at the mouth, without a bullet.
    /// Then its match at 1:1 with «Geschosse bei leeren Hülsen zeigen» off (the matches don't use it).
    func testEmptyCasePhoto() {
        application.launchArguments += ["-showBulletsOnEmptyCases", "NO"]
        photoMatches("photo-6mmbr-case", shot: "15-Foto-leere-Huelse", compareShot: "18-Foto-Huelse-ohne-Geschoss")
    }

    /// The loaded 9 mm with the hidden switch that colours the outline by detection: the bullet up to
    /// the case mouth, where its copper meets the brass, a line across the case there, and the case.
    func testLoadedCartridgePartColours() {
        application.launchArguments += ["-outlinePartColours", "YES"]
        photoMatches("photo-9x19-wood", shot: "16-Foto-Erkennung-farbig")
    }

    /// Raven's flows (2026-11-08): a match opens its calibre's page, whose 1:1 draws that calibre alone;
    /// on the 1:1 comparison of all matches a tap on a drawing opens that calibre's page.
    func testMatchToCalibrePage() {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/set-gp11-case-02.jpg")
        application.launchArguments += ["-screenTourPhoto", photo.path]
        XCTAssertTrue(app.navigationBars["Treffer"].waitForExistence(timeout: 10))
        guard app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90) else { return XCTFail("No matches for the photo") }
        guard open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "6.5-284 Norma")).firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["6.5-284 Norma"].waitForExistence(timeout: 5), "The calibre's page did not open from the match")
        snap("32-Treffer-Kaliber")
        back()
        guard open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden 1:1")).firstMatch),
              app.navigationBars["1:1"].waitForExistence(timeout: 5),
              open(app.scrollViews.firstMatch.buttons.firstMatch) else { return } // the first drawing on screen
        XCTAssertTrue(app.staticTexts["Masse"].waitForExistence(timeout: 5), "The calibre's page did not open from the 1:1 screen")
        snap("33-1zu1-Kaliber")
    }

    /// A photo none of whose matches is sure (the loaded 9 mm looked at as an empty case): the hint and the
    /// link to measure by hand sit with the measurements, above the list of calibres.
    func testUnsureMatches() {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/photo-9x19-wood.jpg")
        application.launchArguments += ["-screenTourPhoto", photo.path]
        XCTAssertTrue(app.navigationBars["Treffer"].waitForExistence(timeout: 10))
        guard app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90) else { return XCTFail("No matches for the photo") }
        app.buttons["Leere Hülse"].tap()
        // With the measurements in the top block (Raven, 2026-11-08), so no scrolling.
        XCTAssertTrue(app.buttons["Masse von Hand eingeben"].waitForExistence(timeout: 5), "The link to measure by hand is not shown")
        snap("31-Foto-unsicher")
        scroll()  // the list's end: under «Mögliche Kaliber», that a match is no clearance to fire
        snap("31b-Foto-Treffer-unten")
    }

    /// A photo with no cartridge on it, so no matches: the way on is measuring by hand, with no link to
    /// the whole catalogue any more (Raven, 2026-11-14).
    func testNoMatches() throws {
        let photo = FileManager.default.temporaryDirectory.appendingPathComponent("tour-empty-paper.png")
        let paper = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { context in
            UIColor(white: 0.93, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }
        try XCTUnwrap(paper.pngData()).write(to: photo)
        application.launchArguments += ["-screenTourPhoto", photo.path]
        XCTAssertTrue(app.navigationBars["Treffer"].waitForExistence(timeout: 10))
        guard app.buttons["Masse von Hand eingeben"].waitForExistence(timeout: 90) else { return XCTFail("The link to measure by hand is not shown") }
        snap("31b-Foto-ohne-Treffer")
    }

    /// A calibre's lookalike group (Raven, 2026-11-08): from the .308 Winchester's page to the group, and the group at 1:1.
    func testLookalikeGroup() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search(".308 Win")
        // The search opens the calibre; its «Gruppe» row leads to the group (Raven, 2026-11-12).
        guard open(app.staticTexts[".308 Winchester"].firstMatch),
              app.navigationBars[".308 Winchester"].waitForExistence(timeout: 5),
              open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gruppe")).firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["Gruppe 7.62x51 mm"].waitForExistence(timeout: 5), "The group page did not open")
        snap("34-Aehnliche-Kaliber")
        guard open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1:1 vergleichen")).firstMatch),
              app.navigationBars["1:1"].waitForExistence(timeout: 5) else { return }
        snap("35-Aehnliche-Kaliber-1zu1")
    }

    /// A group told apart by the rim: «Unterscheiden sich in: Setztiefe des Geschosses, Hülsenrand» (review 2026-11-20).
    func testRimGroup() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search(".38 Special")
        guard open(app.staticTexts[".38 Special"].firstMatch), app.navigationBars[".38 Special"].waitForExistence(timeout: 5),
              open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gruppe")).firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["Gruppe .38 Special"].waitForExistence(timeout: 5), "The group page did not open")
        snap("34b-Gruppe-Huelsenrand")
    }

    /// A cartridge made both as rimfire and centrefire (calibre-data, Raven 2026-11-09): the rimfire
    /// Vetterli's page and its group with the centrefire version, which differ in ignition.
    func testIgnitionGroup() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("Vetterli")
        guard open(app.staticTexts["10.4x38 mm R Vetterli"].firstMatch),
              app.navigationBars["10.4x38 mm R Vetterli"].waitForExistence(timeout: 5),
              open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gruppe")).firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["Gruppe 10.4x38 mm R Vetterli"].waitForExistence(timeout: 5), "The group page did not open")
        snap("37-Vetterli-Zuendung")
        guard open(app.staticTexts["10.4x38 mm R Vetterli"].firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["10.4x38 mm R Vetterli"].waitForExistence(timeout: 5), "The calibre's page did not open from the group")
        snap("36-Vetterli")
    }

    /// A calibre drawn to its C.I.P. sheet (calibre-data #68): the 6.5 PRC is 75.06 mm long, not 84.8.
    func testCIPCorrection() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("6.5 PRC")
        guard open(app.staticTexts["6.5 PRC"].firstMatch) else { return }
        snap("38-6-5-PRC")
    }

    /// The «Trainingsdaten» screen, on a copy of the example package of KaliberfinderTests/Captures so it shows the
    /// same series on every run and the checked-in one stays as it is: changing a choice writes its package.json.
    func testTrainingCapture() {
        let captures = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try FileManager.default.copyItem(at: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("KaliberfinderTests/Captures"), to: captures))
        application.launchArguments += ["-trainingCaptureEnabled", "YES", "-screenTourCaptures", captures.path]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]), developerOptions() else { return }
        snap("21a-Einstellungen-Trainingsdaten")  // the switch on, with the link below it
        guard open(app.buttons["Trainingsdaten aufnehmen"].firstMatch) else { return }
        snap("21-Trainingsdaten")
        guard open(app.staticTexts["9x19 mm"].firstMatch) else { return }
        XCTAssertTrue(app.buttons["Als ZIP teilen"].waitForExistence(timeout: 5), "The saved series did not open")
        snap("22-Trainingsdaten-Serie")
        // The outlines next to the Randform and Hülsenform choices (TestFlight 1174 and 1175), paper and plastic
        // hulls as two choices (TestFlight 1175); the fixture's own choice closes each menu again.
        menuStop("Randform", choice: "Randlos", "22c-Trainingsdaten-Randform")
        menuStop("Hülsenform", choice: "Konisch", "22d-Trainingsdaten-Huelsenform")
        menuStop("Hülsenmaterial", choice: "Messing", "22e-Trainingsdaten-Huelsenmaterial")
        // A rimfire round, paper-patched (Raven 2026-11-19): no primer field or head view, the patch's length.
        menuStop("Zündart", choice: "Randfeuer"); menuStop("Geschoss", choice: "Mit Papierpflaster")
        // The calliper fields at the end, with the sketch of where to measure over them.
        scroll(); snap("22b-Trainingsdaten-Schieblehre")
    }

    /// With the training capture on, a calibre's detail page starts a series of that calibre.
    func testTrainingSeriesFromACalibre() {
        application.launchArguments += ["-trainingCaptureEnabled", "YES"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("9x19\n")
        guard open(app.staticTexts["9x19 mm"].firstMatch) else { return }
        snap("28-Kaliber-Trainingsdaten")
        guard open(app.buttons["Trainingsdaten aufnehmen"].firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["Neue Serie"].waitForExistence(timeout: 5), "The new series sheet did not open")
        XCTAssertTrue(app.staticTexts["9x19 mm"].firstMatch.exists, "The calibre is not preselected")
        snap("29-Trainingsdaten-neue-Serie-Kaliber")
    }

    /// The release notes a TestFlight build shows the first time it is opened (CI writes them into the
    /// bundle; here from a fixture, as if they were not shown yet).
    func testWhatsNew() {
        let notes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/changelog.json")
        application.launchArguments += ["-screenTourChangelog", notes.path, "-changelogShownBuild", "none"]
        XCTAssertTrue(app.navigationBars["Neu in dieser Version"].waitForExistence(timeout: 10), "The release notes did not open")
        snap("30-Neu-in-dieser-Version")
    }

    /// Opens the matches for a photo from KaliberfinderTests/Fixtures and takes the screenshot `shot`;
    /// with `compareShot`, also one of the 1:1 screen that compares all of them.
    private func photoMatches(_ fixture: String, shot: String, compareShot: String? = nil) {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/\(fixture).jpg")
        application.launchArguments += ["-screenTourPhoto", photo.path]
        // The colour cut-out on the simulator can take a while on a busy runner; a stop that would show its spinner fails.
        guard app.navigationBars["Treffer"].waitForExistence(timeout: 10),
              app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90) else { return XCTFail("No matches for \(shot)") }
        snap(shot)
        // A busy runner can take over 5 s for the 1:1 row; a missed stop fails, not vanishes (Raven, 2026-11-19).
        if let compareShot, open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden 1:1")).firstMatch) {
            guard app.navigationBars["1:1"].waitForExistence(timeout: 30) else { return XCTFail("No 1:1 screen for \(compareShot)") }
            snap(compareShot)
        }
    }

    /// A group's word finds its rounds, in any language (Raven, 2026-11-19): the Italian «a salve» lists the blanks.
    func testGroupWordFindsTheBlanks() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("a salve\n")
        XCTAssertTrue(app.staticTexts["9 mm PA Blanc"].waitForExistence(timeout: 5), "«a salve» does not find the blanks")
        snap("08c-Suche-Gruppenwort")
    }

    /// A Berdan primer's row: the title without a size, then the calibre's own diameter (8.15x46 mm R).
    func testBerdanPrimer() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("8.15x46\n")
        guard open(app.staticTexts["8.15x46 mm R"].firstMatch) else { return }
        scroll()  // the page's end holds the measurements' last row, the primer
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Berdan Nitro, ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No Berdan primer row on the 8.15x46 mm R's page")
        snap("42-Berdan-Zuendhuetchen")
    }

    /// A belt wider than the rim (calibre-data #150): the .378 Weatherby Magnum is drawn with its belt, and its
    /// measurements name the belt's diameter.
    func testBeltWiderThanTheRim() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search(".378 Weatherby\n")
        guard open(app.staticTexts[".378 Weatherby Magnum"].firstMatch) else { return }
        snap("43-Guertel-378-Weatherby")
        // Its drawing: the belt's line on the belt, the base's on the body in front of it (tester, 2026-11-14).
        if open(app.buttons["Masszeichnung anzeigen"].firstMatch) { snap("43c-Guertel-Masszeichnung"); app.navigationBars.buttons.firstMatch.tap() }
        scroll(toRowAbove: "Gesamtlänge")
        snap("43b-Guertel-378-Weatherby-Masse")
    }

    /// A round taller than the screen at 1:1 scrolls (tester, 2026-11-14): the base first, the tip after a swipe down.
    func testTallRoundScrollsAtOneToOne() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("50 BMG\n")
        guard open(app.staticTexts[".50 BMG"].firstMatch), open(app.buttons["In Originalgrösse anzeigen"].firstMatch) else { return }
        snap("14c-1zu1-50-BMG"); app.swipeDown(); snap("14d-1zu1-50-BMG-Spitze")
    }

    /// The silver jacket of an early service round (calibre-data #151): the 8x57 mm IS was drawn with a copper bullet.
    func testSilverJacket() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        search("8x57\n")
        guard open(app.staticTexts["8x57 mm IS"].firstMatch) else { return }
        snap("44-Silbermantel-8x57-IS")
    }

    /// The calibration screen: the slider and the buttons dock at the bottom (Raven, 2026-11-11, on an iPad).
    func testCalibration() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]),
              open(app.staticTexts["Bildschirm"].firstMatch) else { return }
        XCTAssertTrue(app.buttons["Speichern"].waitForExistence(timeout: 5), "The calibration screen did not open")
        snap("38-Bildschirm-kalibrieren")
    }

    /// At 235 % text size (App Accessibility, 2026-11-23): the start screen's switches, the compare button and the 1:1 labels.
    func testLargeText() {
        application.launchArguments += ["-screenTourLength", "29.7", "-screenTourBullet", "9.0", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        scroll(); snap("47a-Grosse-Schrift-Start"); scroll(up: false)
        if open(app.buttons["Masse eingeben"].firstMatch) { snap("47b-Grosse-Schrift-Treffer") }
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden")).firstMatch) { snap("47c-Grosse-Schrift-1zu1") }
    }

    private func open(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(element) not found")
            return false
        }
        element.tap()
        return true
    }

    /// Scrolls the Settings sheet to its last section and opens the developer options, where the training switch (on by
    /// launch argument) and its link sit. The drags run along the left edge: a swipe through the middle can catch a switch.
    private func developerOptions() -> Bool {
        for _ in 0..<6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)))
        }
        return open(app.buttons["Entwickleroptionen"].firstMatch)
    }

    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    /// Opens the menu of the row whose label starts with `row`, snaps it as `name` if given, and picks `choice`; tapped once
    /// hittable, as the menu before it may still be fading out over it (tour of #277).
    private func menuStop(_ row: String, choice: String, _ name: String? = nil) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch
        guard button.waitForExistence(timeout: 5), button.wait(for: \.isHittable, toEqual: true, timeout: 5) else { return XCTFail("\(row) not tappable") }
        button.tap()
        if app.buttons[choice].waitForExistence(timeout: 5), let name { snap(name) }
        app.buttons[choice].tap()
    }

    /// Swipes to the very end (or start): a single swipe stops at a different place on each run, the end does not.
    private func scroll(up: Bool = true) {
        for _ in 0..<6 {
            if up { app.swipeUp(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
        }
    }

    /// Drags the page until the row `label` (the last of the section above) is in the upper third of the screen, so the
    /// section below it is in the picture whole (a page's end would cut its first rows off). A swipe would fling past the zone.
    private func scroll(toRowAbove label: String) {
        let row = app.staticTexts[label].firstMatch, height = app.frame.height
        for _ in 0..<10 {
            let top = row.exists ? row.frame.minY : height
            if top > 0 && top < height / 3 { return }
            let distance = min(top - height / 4, height * 0.6)
            guard distance > 0 else { return }  // already above the top: leave the page as it is
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.dragWithoutFling(to: from.withOffset(CGVector(dx: 0, dy: -distance)))
        }
    }

    private func snap(_ name: String) {
        sleep(2) // let animations settle and scroll indicators fade
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUICoordinate {
    /// Holds before lifting, so the view stops where the finger stops; a plain `press(forDuration:thenDragTo:)` coasts on a
    /// different distance each run (14b showed other calibres, 2026-11-21). Here, not in its own file: the base tour gets only this file.
    func dragWithoutFling(to end: XCUICoordinate) { press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3) }
}
