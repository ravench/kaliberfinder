import XCTest

/// A tour of the main screens, one screenshot per stop. The Build job's PR screens run it on the
/// pull request and on its base branch and posts the screens that changed as a comment.
/// A pull request that changes a screen the tour does not reach adds a stop.
final class PRScreensTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        // A broken stop should not cost the screenshots of the others.
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    func testTour() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        snap("01-Start")
        scroll()
        snap("02-Start-unten")
        scroll(up: false)

        if open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]) {
            snap("06-Einstellungen")
            scroll()
            snap("06b-Einstellungen-unten")  // version and calibre-data commit
            app.buttons["Fertig"].firstMatch.tap()
        }
        if open(app.buttons["Masse eingeben"].firstMatch) {
            snap("03-Masse-eingeben")
            back()
        }
        if open(app.buttons["Alle Kaliber"].firstMatch) {
            snap("04-Alle-Kaliber")
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("9x19")
            }
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
        app.terminate()
        app.launchArguments += ["-screenTourLength", "29.7", "-screenTourBullet", "9.0"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch) else { return }
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "No results for the launch arguments")
        snap("03b-Masse-Treffer")  // the 9x19 group's row leads
        scroll()
        snap("03b-Masse-Treffer-unten")
    }

    /// The groups' switch off (Raven, 2026-11-13): the 9x19 and the Glisenti as rows of their own, each named
    /// after the group, and both drawn at 1:1.
    func testUngroupedMatches() {
        app.terminate()
        app.launchArguments += ["-screenTourLength", "29.7", "-screenTourBullet", "9.0", "-groupSizeGroups", "NO"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Masse eingeben"].firstMatch) else { return }
        XCTAssertTrue(app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 5), "No results for the launch arguments")
        snap("03c-Masse-Treffer-ungruppiert")
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden 1:1")).firstMatch),
           app.navigationBars["1:1"].waitForExistence(timeout: 5) {
            snap("03c-Masse-1zu1-ungruppiert")
        }
    }

    /// Calibres picked long, short, middle stand by length: in the picked list and on the 1:1 screen.
    func testPickAndCompare() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Auswählen und vergleichen"].firstMatch) else { return }
        for (query, name) in [("GP 11", "7.5x55 mm Swiss (GP 11)"), ("9x19", "9x19 mm"), (".45 ACP", ".45 ACP")] {
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                // Clears the previous query; return hides the keyboard, so the rows can be tapped.
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + query + "\n")
            }
            _ = open(app.staticTexts[name].firstMatch)
        }
        snap("19-Auswahl")
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1:1 vergleichen")).firstMatch),
           app.navigationBars["1:1"].waitForExistence(timeout: 5) {
            snap("20-Auswahl-1zu1")
        }
    }

    /// The dimensioned drawing of a bottleneck rifle round (with its shoulder), then of a belted magnum
    /// in inches.
    func testMeasurementDrawings() {
        for (query, name, unit, shot) in [("GP 11", "7.5x55 mm Swiss (GP 11)", "metric", "34-Masszeichnung-GP11"),
                                          ("300 Win Mag", ".300 Winchester Magnum", "imperial", "35-Masszeichnung-Zoll")] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH", "-lengthUnit", unit]
            app.launch()
            XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
            guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText(query + "\n") // return hides the keyboard
            }
            guard open(app.staticTexts[name].firstMatch) else { return }
            if query == "GP 11" {
                // The colour codes of calibre-data (tip and bases) sit under the measurements (Raven, 2026-11-11).
                scroll(toRowAbove: "Zündhütchen")
                snap("39-GP11-Farbcodes")
                scroll(up: false)
            }
            guard open(app.buttons["Masszeichnung anzeigen"].firstMatch) else { return }
            snap(shot)
        }
    }

    /// Primer-ring colour codes on a calibre page: the .303 British's pre-NATO British code (Raven, 2026-11-11).
    func testPrimerRingColourCodes() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText(".303 British\n") // return hides the keyboard
        }
        guard open(app.staticTexts[".303 British"].firstMatch) else { return }
        scroll(toRowAbove: "Zündhütchen")
        snap("40-303-Zuendhuetchenringe")
    }

    /// Loose balls in other materials: the steel BB and the plastic airsoft BBs.
    func testBBs() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("BB\n") // return hides the keyboard, so all BB rows show
        }
        snap("08-BBs")
        if open(app.staticTexts["6 mm Airsoft-BB"].firstMatch) {
            snap("09-Airsoft-BB")
        }
    }

    /// The .32 S&W family side by side, with the flush-seated wadcutter that shows only its case.
    func testWadcutter() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("32 S&W\n") // return hides the keyboard, so all three rows show
        }
        snap("24-32-SW")
        if open(app.staticTexts[".32 S&W Long Wadcutter"].firstMatch) {
            snap("25-32-SW-Long-Wadcutter")
        }
    }

    /// The Swiss cadet round, found by the name on its box, with its own drawing.
    func testKadettenpatrone() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Kadetten\n")
        }
        if open(app.staticTexts["7.5 mm Kadettenpatrone"].firstMatch) {
            snap("26-Kadettenpatrone")
        }
    }

    /// A NATO round: the alliance's flag is drawn, as no emoji exists (calibre-data #51).
    func testNatoFlag() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("5.56\n") // return hides the keyboard, so the rows show their flags
        }
        snap("27-NATO")
        if open(app.staticTexts["5.56x45 mm NATO"].firstMatch) {
            scroll()
            snap("27-NATO-Kaliber-unten") // the Herkunft row with the drawn flag
        }
    }

    /// The calibre picker of a new training series finds a calibre by its other names too, and shows them.
    func testTrainingCalibreSearch() {
        app.terminate()
        app.launchArguments += ["-trainingCaptureEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]),
              settingsBottom(),
              open(app.buttons["Trainingsdaten aufnehmen"].firstMatch),
              open(app.buttons["Neue Aufnahmeserie"].firstMatch),
              open(app.staticTexts["Fotografiertes Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Schmidt Rubin\n") // return hides the keyboard
        }
        XCTAssertTrue(app.staticTexts["7.5x53.5 mm Swiss (GP 1890)"].waitForExistence(timeout: 5), "not found by another name")
        snap("23-Trainingsdaten-Kalibersuche")
    }

    /// A new training series of a round the catalogue lacks: searched in vain, then «Nicht in der Liste»,
    /// named after the search.
    func testTrainingUnlistedRound() {
        app.terminate()
        app.launchArguments += ["-trainingCaptureEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]),
              settingsBottom(),
              open(app.buttons["Trainingsdaten aufnehmen"].firstMatch),
              open(app.buttons["Neue Aufnahmeserie"].firstMatch),
              open(app.staticTexts["Fotografiertes Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Gras court\n") // return hides the keyboard
        }
        snap("24-Trainingsdaten-nicht-in-Liste")
        guard open(app.buttons["Nicht in der Liste"].firstMatch) else { return }
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Gras court", "named after the search")
        snap("25-Trainingsdaten-unbekannte-Patrone")
    }

    /// Cases that are not brass, from the side and from below: lacquered steel, a brass body on a
    /// steel head, and a paper case in a brass cup.
    func testCaseMaterials() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        for (query, name, shot) in [("5.45", "5.45x39 mm", "10-Stahlhuelse"), ("Fury", ".277 SIG Fury", "11-Hybridhuelse"),
                                    ("Snider", ".577 Snider", "12-Papierhuelse")] {
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                // Clears the previous query first.
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + query)
            }
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
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)))
        }
        snap("14b-Foto-1zu1-9x19")
    }

    /// One of Raven's empty 6 mm BR cases: its outline ends flat at the mouth, without a bullet.
    /// Then its match at 1:1 with «Geschosse bei leeren Hülsen zeigen» off (the matches don't use it).
    func testEmptyCasePhoto() {
        app.launchArguments += ["-showBulletsOnEmptyCases", "NO"]
        photoMatches("photo-6mmbr-case", shot: "15-Foto-leere-Huelse", compareShot: "18-Foto-Huelse-ohne-Geschoss")
    }

    /// The loaded 9 mm with the hidden switch that colours the outline by detection: the bullet up to
    /// the case mouth, where its copper meets the brass, a line across the case there, and the case.
    func testLoadedCartridgePartColours() {
        app.launchArguments += ["-outlinePartColours", "YES"]
        photoMatches("photo-9x19-wood", shot: "16-Foto-Erkennung-farbig")
    }

    /// Raven's flows (2026-11-08): a match opens its calibre's page, whose 1:1 draws that calibre alone;
    /// on the 1:1 comparison of all matches a tap on a drawing opens that calibre's page.
    func testMatchToCalibrePage() {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/set-gp11-case-02.jpg")
        app.terminate()
        app.launchArguments += ["-screenTourPhoto", photo.path]
        app.launch()
        XCTAssertTrue(app.navigationBars["Treffer"].waitForExistence(timeout: 10))
        _ = app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90)
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
        app.terminate()
        app.launchArguments += ["-screenTourPhoto", photo.path]
        app.launch()
        XCTAssertTrue(app.navigationBars["Treffer"].waitForExistence(timeout: 10))
        _ = app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90)
        app.buttons["Leere Hülse"].tap()
        // With the measurements in the top block (Raven, 2026-11-08), so no scrolling.
        XCTAssertTrue(app.buttons["Masse von Hand eingeben"].waitForExistence(timeout: 5), "The link to measure by hand is not shown")
        snap("31-Foto-unsicher")
    }

    /// A calibre's lookalike group (Raven, 2026-11-08): from the .308 Winchester's page to the group, and the group at 1:1.
    func testLookalikeGroup() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText(".308 Win")
        }
        // The search opens the calibre; its «Gruppe» row leads to the group (Raven, 2026-11-12).
        guard open(app.staticTexts[".308 Winchester"].firstMatch),
              app.navigationBars[".308 Winchester"].waitForExistence(timeout: 5),
              open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gruppe")).firstMatch) else { return }
        XCTAssertTrue(app.navigationBars["Gruppe .308 Winchester"].waitForExistence(timeout: 5), "The group page did not open")
        snap("34-Aehnliche-Kaliber")
        guard open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1:1 vergleichen")).firstMatch),
              app.navigationBars["1:1"].waitForExistence(timeout: 5) else { return }
        snap("35-Aehnliche-Kaliber-1zu1")
    }

    /// A cartridge made both as rimfire and centrefire (calibre-data, Raven 2026-11-09): the rimfire
    /// Vetterli's page and its group with the centrefire version, which differ in ignition.
    func testIgnitionGroup() {
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Vetterli")
        }
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
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("6.5 PRC")
        }
        guard open(app.staticTexts["6.5 PRC"].firstMatch) else { return }
        snap("38-6-5-PRC")
    }

    /// The «Trainingsdaten» screen, on the example package of KaliberfinderTests/Captures so
    /// it shows the same series on every run: the saved series, and one of them opened from the list.
    func testTrainingCapture() {
        let captures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Captures")
        app.terminate()
        app.launchArguments += ["-trainingCaptureEnabled", "YES", "-screenTourCaptures", captures.path]
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]), settingsBottom() else { return }
        snap("21a-Einstellungen-Trainingsdaten")  // the switch on, with the link below it
        guard open(app.buttons["Trainingsdaten aufnehmen"].firstMatch) else { return }
        snap("21-Trainingsdaten")
        guard open(app.staticTexts["9x19 mm"].firstMatch) else { return }
        XCTAssertTrue(app.buttons["Als ZIP teilen"].waitForExistence(timeout: 5), "The saved series did not open")
        snap("22-Trainingsdaten-Serie")
        // The outlines next to the Randform and Hülsenform choices (TestFlight 1174 and 1175), paper and plastic
        // hulls as two choices (TestFlight 1175); the fixture's own choice closes each menu again.
        menuStop("Randform", choice: "Randlos", "22c-Trainingsdaten-Randform")
        menuStop("Hülsenform", choice: "Konische Hülse", "22d-Trainingsdaten-Huelsenform")
        menuStop("Hülsenmaterial", choice: "Messing", "22e-Trainingsdaten-Huelsenmaterial")
        // The calliper fields at the end, with the sketch of where to measure over them.
        scroll()
        snap("22b-Trainingsdaten-Schieblehre")
    }

    /// With the training capture on, a calibre's detail page starts a series of that calibre.
    func testTrainingSeriesFromACalibre() {
        app.terminate()
        app.launchArguments += ["-trainingCaptureEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("9x19\n")
        }
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
        app.terminate()
        app.launchArguments += ["-screenTourChangelog", notes.path, "-changelogShownBuild", "none"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Neu in dieser Version"].waitForExistence(timeout: 10), "The release notes did not open")
        snap("30-Neu-in-dieser-Version")
    }

    /// Opens the matches for a photo from KaliberfinderTests/Fixtures and takes the screenshot `shot`;
    /// with `compareShot`, also one of the 1:1 screen that compares all of them.
    private func photoMatches(_ fixture: String, shot: String, compareShot: String? = nil) {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KaliberfinderTests/Fixtures/\(fixture).jpg")
        app.terminate()
        app.launchArguments += ["-screenTourPhoto", photo.path]
        app.launch()
        if app.navigationBars["Treffer"].waitForExistence(timeout: 10) {
            // The colour cut-out on the simulator can take a while on a busy runner.
            _ = app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90)
            snap(shot)
            if let compareShot, open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle passenden 1:1")).firstMatch),
               app.navigationBars["1:1"].waitForExistence(timeout: 5) {
                snap(compareShot)
            }
        }
    }

    /// A Berdan primer's row: the title without a size, then the calibre's own diameter (8.15x46 mm R: 6.35 mm).
    func testBerdanPrimer() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.buttons["Alle Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("8.15x46\n") // return hides the keyboard
        }
        guard open(app.staticTexts["8.15x46 mm R"].firstMatch) else { return }
        scroll(toRowAbove: "Halsdurchmesser")
        snap("42-Berdan-Zuendhuetchen")
    }

    /// The calibration screen: the slider and the buttons dock at the bottom (Raven, 2026-11-11, on an iPad).
    func testCalibration() {
        XCTAssertTrue(app.navigationBars["Kaliberfinder"].waitForExistence(timeout: 10), "Start screen missing")
        guard open(app.navigationBars["Kaliberfinder"].buttons["Einstellungen"]),
              open(app.staticTexts["Bildschirm"].firstMatch) else { return }
        XCTAssertTrue(app.buttons["Speichern"].waitForExistence(timeout: 5), "The calibration screen did not open")
        snap("38-Bildschirm-kalibrieren")
    }

    private func open(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(element) not found")
            return false
        }
        element.tap()
        return true
    }

    /// Scrolls the Settings sheet to its last section, where the training switch (on by launch argument)
    /// and its link sit. The drags run along the left edge: a swipe through the middle can catch the
    /// switch and turn it off.
    private func settingsBottom() -> Bool {
        for _ in 0..<6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)))
        }
        return true
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Swipes to the very end (or start): a single swipe or drag stops at a different place on
    /// each run, the end of the content does not.
    /// Opens the picker menu of the series row whose label starts with `row`, takes the screen while the menu
    /// is up, and taps `choice`, the fixture's own value, so the menu closes and nothing changes.
    private func menuStop(_ row: String, choice: String, _ name: String) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch
        guard button.waitForExistence(timeout: 5) else { return }
        button.tap()
        if app.buttons[choice].waitForExistence(timeout: 5) { snap(name) }
        app.buttons[choice].tap()
    }

    private func scroll(up: Bool = true) {
        for _ in 0..<6 {
            if up { app.swipeUp(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
        }
    }

    /// Drags the page until the row `label` (the last of the section above) is in the upper third of the
    /// screen, so the section below it is in the picture whole (a page's end would cut its first rows off).
    /// Drags, not swipes: a swipe flings the row past the zone.
    private func scroll(toRowAbove label: String) {
        let row = app.staticTexts[label].firstMatch, height = app.frame.height
        for _ in 0..<10 {
            let top = row.exists ? row.frame.minY : height
            if top > 0 && top < height / 3 { return }
            let distance = min(top - height / 4, height * 0.6)
            guard distance > 0 else { return }  // already above the top: leave the page as it is
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -distance)))
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
