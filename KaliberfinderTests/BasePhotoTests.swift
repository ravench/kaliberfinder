import UIKit
import XCTest
@testable import Kaliberfinder

/// Two-shot flow: the side photo gives shape and size, only the base photo is read for text.
final class BasePhotoTests: XCTestCase {
    private let side = ShapeMeasurement(aspect: 3.5, profile: ShapeMatcher.fractions.map { _ in 1 })
    private let disc = ShapeMeasurement(aspect: 1, profile: ShapeMatcher.fractions.map { _ in 1 })

    /// A plain white picture with large black text, like a sharp headstamp photo.
    private func textImage(_ text: String) -> UIImage {
        let size = CGSize(width: 900, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 110), .foregroundColor: UIColor.black]
            (text as NSString).draw(at: CGPoint(x: 60, y: 130), withAttributes: attributes)
        }
    }

    func testBasePhotoAlwaysReadsText() {
        XCTAssertTrue(PhotoKind.base.readsText(shape: nil))
        XCTAssertTrue(PhotoKind.base.readsText(shape: side))
        XCTAssertTrue(PhotoKind.base.readsText(shape: disc))
    }

    func testSidePhotoReadsTextOnlyWhenItShowsAnEnd() {
        XCTAssertFalse(PhotoKind.side.readsText(shape: side))
        XCTAssertFalse(PhotoKind.side.readsText(shape: nil))
        XCTAssertTrue(PhotoKind.side.readsText(shape: disc))
    }

    func testTextIsReadFromTheBasePhoto() {
        let result = PhotoAnalyzer.analyzeNow(textImage("WIN 308"), kind: .base)
        XCTAssertNil(result.shape, "the base photo is not measured")
        XCTAssertTrue(result.texts.joined(separator: " ").contains("308"), "read: \(result.texts)")
        XCTAssertTrue(HeadstampReader.hits(in: result.texts).contains { $0.cartridgeID == ".308 Winchester" })
    }

    func testTextOnTheSidePhotoIsIgnored() {
        let result = PhotoAnalyzer.analyzeNow(textImage("WIN 308"), kind: .side)
        XCTAssertEqual(result.texts, [])
    }

    func testHitsComeFromTheBasePhoto() {
        let sideResult = PhotoAnalysis(shape: side, texts: [])
        XCTAssertTrue(MatchesView.hits(side: sideResult, baseTexts: nil).isEmpty)
        let hits = MatchesView.hits(side: sideResult, baseTexts: ["WIN 308"])
        XCTAssertTrue(hits.contains { $0.cartridgeID == ".308 Winchester" })
    }

    func testRoundFirstPhotoStillCounts() {
        let round = PhotoAnalysis(shape: disc, texts: ["9mm Luger"])
        XCTAssertFalse(MatchesView.hits(side: round, baseTexts: nil).isEmpty)
    }

    func testBaseNote() {
        XCTAssertEqual(MatchesView.baseNote([]), "Keine Aufschrift erkannt.".loc)
        XCTAssertEqual(MatchesView.baseNote(["  ", ""]), "Keine Aufschrift erkannt.".loc)
        let note = MatchesView.baseNote(["WIN 308", "WIN 308", "NATO"])
        XCTAssertTrue(note.contains("WIN 308 / NATO"), note)
        XCTAssertEqual(note.components(separatedBy: "WIN 308").count, 2, "duplicates are dropped")
    }

    func testBasePhotoTextsAreTranslated() {
        for key in ["Boden fotografieren", "Bodenfoto auswählen", "Keine Aufschrift erkannt.", "Aufschrift erkannt: «%@»",
                    "Die Aufschrift wird nur auf dem Bodenfoto gelesen. Boden formatfüllend, scharf und von vorne fotografieren."] {
            let english = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertFalse(english.isEmpty, key)
        }
    }
}
