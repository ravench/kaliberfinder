import ImageIO
import UIKit
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
            if open(app.staticTexts["9x19 mm"].firstMatch) {
                snap("05-Kaliber")
            }
        }
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
    /// detected neck and taper drawn over it.
    func testPhotoMatches() {
        photoMatches(fixture("set-gp11-case-02"), shot: "07-Foto-Treffer")
    }

    /// A loaded 9 mm: the outline follows its round bullet nose.
    func testLoadedCartridgePhoto() {
        photoMatches(fixture("photo-9x19-wood"), shot: "13-Foto-Patrone")
    }

    /// An empty .45 ACP case: its outline ends flat at the mouth. The simulator has no Vision, so the
    /// tour paints the case Vision found in one of Raven's photos (its mask in the golden set), whose
    /// outline had a nose at the mouth.
    func testEmptyCasePhoto() {
        guard let photo = paintedMask("45-acp-20261105-115201/11") else { return XCTFail("golden mask missing") }
        photoMatches(photo, shot: "14-Foto-leere-Huelse")
    }

    /// The repository's folder, for the test photos and the golden set.
    private let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func fixture(_ name: String) -> URL {
        sources.appendingPathComponent("KaliberfinderTests/Fixtures/\(name).jpg")
    }

    /// A golden-set shot's Vision mask (KaliberfinderTests/Golden) as a photo of the size it was taken
    /// at: the object brass on a grey table. Saved as a JPEG for `-screenTourPhoto`.
    private func paintedMask(_ shot: String) -> URL? {
        let folder = sources.appendingPathComponent("KaliberfinderTests/Golden/\(shot)")
        guard let json = try? Data(contentsOf: folder.appendingPathComponent("shot.json")),
              let mask = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["mask"] as? [String: Any],
              let width = mask["imageWidth"] as? Int, let height = mask["imageHeight"] as? Int,
              let source = CGImageSourceCreateWithURL(folder.appendingPathComponent("vision-instances.png") as CFURL, nil),
              let labels = CGImageSourceCreateImageAtIndex(source, 0, nil), labels.bitsPerPixel == 8,
              let bytes = labels.dataProvider?.data as Data? else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            // The label nearest each photo pixel, as Vision scales its mask to the photo.
            let row = min(labels.height - 1, (2 * y + 1) * labels.height / (2 * height)) * labels.bytesPerRow
            for x in 0..<width {
                let label = bytes[row + min(labels.width - 1, (2 * x + 1) * labels.width / (2 * width))]
                let rgb: [UInt8] = label == 0 ? [128, 126, 122] : [200, 160, 60]
                for c in 0..<3 { pixels[(y * width + x) * 4 + c] = rgb[c] }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tour-\(shot.replacingOccurrences(of: "/", with: "-")).jpg")
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage(), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.9),
              (try? jpeg.write(to: url)) != nil else { return nil }
        return url
    }

    /// Opens the matches for the photo file `photo` and takes the screenshot `shot`.
    private func photoMatches(_ photo: URL, shot: String) {
        app.terminate()
        app.launchArguments += ["-screenTourPhoto", photo.path]
        app.launch()
        if app.navigationBars["Treffer"].waitForExistence(timeout: 10) {
            // The colour cut-out on the simulator can take a while on a busy runner.
            _ = app.staticTexts["Mögliche Kaliber"].waitForExistence(timeout: 90)
            snap(shot)
        }
    }

    private func open(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(element) not found")
            return false
        }
        element.tap()
        return true
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Swipes to the very end (or start): a single swipe or drag stops at a different place on
    /// each run, the end of the content does not.
    private func scroll(up: Bool = true) {
        for _ in 0..<6 {
            if up { app.swipeUp(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
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
