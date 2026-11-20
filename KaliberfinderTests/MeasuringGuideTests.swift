import XCTest
@testable import Kaliberfinder

/// The «where to measure» sketch over the calliper fields of a training series (MeasuringGuide).
final class MeasuringGuideTests: XCTestCase {
    /// Every calliper value has a field, every field a letter of its own, and each letter is on the sketch once.
    func testEveryFieldHasItsLetterOnTheSketch() {
        let fields = TrainingPackageView.calliperFields, letters = fields.map(\.letter)
        XCTAssertEqual(fields.count, Mirror(reflecting: Measurements()).children.count, "a field for every measurement")
        XCTAssertEqual(Set(letters).count, letters.count)
        XCTAssertEqual((MeasuringGuide.marks + [MeasuringGuide.beltMark]).map(\.letter).sorted(), letters.sorted())
        // Each field writes a value of its own.
        var m = Measurements()
        for (i, field) in fields.enumerated() { m[keyPath: field.value] = Double(i + 1) }
        XCTAssertEqual(Set(Mirror(reflecting: m).children.compactMap { $0.value as? Double }), Set((1...fields.count).map(Double.init)))
    }

    /// Drawing, lines and letters stay inside the sketch's box, and a letter neither overlaps another
    /// nor sits on a line or the drawing: on the training sketch and on the form's, whatever shape and head.
    func testLettersAndLinesFitTheBox() {
        let forms = CaseShape.allCases.flatMap { shape in
            RimKind.allCases.map { MeasuringGuide(letters: MeasureView.letters, shape: shape, head: $0) }
        }
        let series = CaseShape.allCases.flatMap { shape in
            RimKind.allCases.map { MeasuringGuide(letters: Set(TrainingPackageView.fields(shape: shape, head: $0, bullet: "paper").map(\.letter)), shape: shape, head: $0) }
        }
        for guide in [MeasuringGuide()] + forms + series { assertLettersAndLinesFit(guide) }
    }

    /// The training screen's fields and sketch follow the series' Randform and Hülsenform like the form's
    /// (Raven 2026-11-19): a belted head adds the belt field, a straight or tapered case has no shoulder fields,
    /// and its neck mark spans the body at the mouth.
    func testTheTrainingSketchFollowsTheSeriesFacts() throws {
        let all = TrainingPackageView.calliperFields.map(\.letter)
        XCTAssertEqual(TrainingPackageView.fields(shape: .any, head: .any).map(\.letter), all.filter { !["G", "PP"].contains($0) })
        XCTAssertEqual(TrainingPackageView.fields(shape: .any, head: .belted, bullet: "paper").map(\.letter), all)
        XCTAssertEqual(TrainingPackageView.fields(shape: .straight, head: .rimless).map(\.letter), all.filter { !["G", "S", "H", "PP"].contains($0) })
        // Rimfire rounds have no primer, so no field and no head view (Raven 2026-11-19); a paper patch has its length.
        let rimfire = TrainingPackageView.fields(shape: .straight, head: .rimmed, ignition: "rimfire").map(\.letter)
        XCTAssertEqual(rimfire, ["R", "B", "N", "D", "E", "L", "OAL"])
        XCTAssertFalse(MeasuringGuide(letters: Set(rimfire), shape: .straight, head: .rimmed).showsHead)
        XCTAssertEqual(TrainingPackageView.fields(shape: .straight, head: .rimmed, ignition: "centrefire", bullet: "paper").map(\.letter),
                       ["R", "P", "B", "N", "D", "E", "L", "PP", "OAL"])
        XCTAssertFalse(TrainingPackageView.fields(shape: .any, head: .any, bullet: "lead").contains { $0.letter == "PP" })
        XCTAssertEqual(TrainingPackageView.shape(of: nil), .any)
        XCTAssertEqual(TrainingPackageView.shape(of: "tapered"), .straight)
        XCTAssertEqual(TrainingPackageView.shape(of: "bottleneck"), .bottleneck)
        XCTAssertEqual(TrainingPackageView.head(of: "rebated"), .rimless)
        XCTAssertEqual(TrainingPackageView.head(of: "semi"), .semiRimmed)
        XCTAssertEqual(TrainingPackageView.head(of: "belted"), .belted)
        XCTAssertEqual(TrainingPackageView.head(of: nil), .any)
        let straight = MeasuringGuide(letters: nil, shape: .straight, head: .rimless)
        let n = try XCTUnwrap(straight.shownMarks.first { $0.letter == "N" })
        XCTAssertTrue(straight.caseOutline.contains(CGPoint(x: 340, y: n.from.y + 1)), "the mark spans the body")
        XCTAssertFalse(straight.caseOutline.contains(CGPoint(x: 340, y: n.from.y - 1)))
        XCTAssertEqual(MeasuringGuide().shownMarks.first { $0.letter == "N" }?.from, MeasuringGuide.marks.first { $0.letter == "N" }?.from)
    }

    private func assertLettersAndLinesFit(_ guide: MeasuringGuide, file: StaticString = #filePath, line: UInt = #line) {
        let box = guide.box, what = "\(guide.shape) \(guide.head)"
        func inside(_ r: CGRect) -> Bool { r.minX >= box.minX && r.maxX <= box.maxX && r.minY >= box.minY && r.maxY <= box.maxY }
        let segments = guide.shownMarks.map { [$0.from, $0.to] } + guide.shownExtensions
        let shapes = [guide.caseOutline.boundingRect, guide.bullet.boundingRect]
        for r in shapes + segments.map(Self.bounds) { XCTAssertTrue(inside(r), "\(what) \(r)", file: file, line: line) }
        // A bold capital on its baseline is about ¾ of the font size wide and high (generous for I, tight for W).
        let size = MeasuringGuide.letterSize
        let letters = guide.shownMarks.map { mark in
            let w = 0.75 * size * Double(mark.letter.count), h = 0.75 * size
            return (mark.letter, CGRect(x: mark.label.x - w / 2, y: mark.label.y - h, width: w, height: h))
        }
        for (i, (letter, r)) in letters.enumerated() {
            XCTAssertTrue(inside(r), "\(what) \(letter)", file: file, line: line)
            for (other, o) in letters.dropFirst(i + 1) { XCTAssertFalse(r.intersects(o), "\(what) \(letter) \(other)", file: file, line: line) }
            for s in segments {
                XCTAssertFalse(r.intersects(Self.bounds(s).insetBy(dx: -0.5, dy: -0.5)), "\(what) \(letter) \(s)", file: file, line: line)
            }
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            for shape in [guide.caseOutline, guide.bullet] {
                XCTAssertFalse(corners.contains { shape.contains($0) }, "\(what) \(letter)", file: file, line: line)
            }
        }
    }

    /// The form's sketch follows its choices (TestFlight 2026-11-17): the default is the rimmed bottleneck round of the
    /// training screen; a straight case has no shoulder and a wider bullet, the heads differ at the rim, a belted
    /// one adds the belt and its mark; the rim's and bullet's marks span what is drawn.
    func testTheSketchFollowsShapeAndHead() {
        func guide(_ shape: CaseShape = .any, _ head: RimKind = .any) -> MeasuringGuide {
            MeasuringGuide(letters: MeasureView.letters, shape: shape, head: head)
        }
        XCTAssertEqual(guide().caseOutline.description, MeasuringGuide().caseOutline.description)
        XCTAssertEqual(guide(.bottleneck, .rimmed).caseOutline.description, MeasuringGuide().caseOutline.description)
        XCTAssertEqual(guide().bullet.description, MeasuringGuide().bullet.description)
        // A straight case: the same length and head, no shoulder (fewer corners), the mouth nearly as wide as the body.
        let straight = guide(.straight), bottleneck = guide(.bottleneck)
        XCTAssertEqual(straight.caseOutline.boundingRect, bottleneck.caseOutline.boundingRect)
        XCTAssertLessThan(straight.caseOutline.description.count, bottleneck.caseOutline.description.count)
        XCTAssertTrue(straight.caseOutline.contains(CGPoint(x: 340, y: 65)), "the body reaches the mouth at full width")
        XCTAssertFalse(bottleneck.caseOutline.contains(CGPoint(x: 340, y: 65)), "the neck is narrower")
        XCTAssertGreaterThan(straight.bulletRadius, bottleneck.bulletRadius)
        XCTAssertLessThan(straight.bulletRadius, MeasuringGuide.axis - 61.9, "the bullet fits inside the mouth")
        // The heads: a rim wider than the body, a semi-rim a little, rimless and belted flush with it, all with a groove.
        let rims = Dictionary(uniqueKeysWithValues: RimKind.allCases.map { ($0, guide(.any, $0)) })
        XCTAssertEqual(rims[.any]?.rimRadius, rims[.rimmed]?.rimRadius)
        XCTAssertGreaterThan(rims[.rimmed]?.rimRadius ?? 0, rims[.semiRimmed]?.rimRadius ?? 0)
        XCTAssertGreaterThan(rims[.semiRimmed]?.rimRadius ?? 0, rims[.rimless]?.rimRadius ?? 0)
        XCTAssertEqual(rims[.rimless]?.rimRadius, rims[.belted]?.rimRadius)
        XCTAssertEqual(rims[.rimless]?.rimRadius, 37.1, "the body's radius at the head")
        for (head, g) in rims {
            let groove = g.caseOutline.contains(CGPoint(x: 54, y: 60))
            XCTAssertEqual(groove, [.any, .rimmed].contains(head), "\(head) groove")
            XCTAssertEqual(g.caseOutline.contains(CGPoint(x: 44.8, y: MeasuringGuide.axis - g.rimRadius + 1)), true, "\(head) rim")
            XCTAssertFalse(g.caseOutline.contains(CGPoint(x: 44.8, y: MeasuringGuide.axis - g.rimRadius - 1)), "\(head) rim edge")
            let rimMark = g.shownMarks.first { $0.letter == "R" }
            XCTAssertEqual(rimMark?.from.y, MeasuringGuide.axis - g.rimRadius, "\(head) R spans the rim")
            XCTAssertEqual(g.shownMarks.contains { $0.letter == "G" }, head == .belted, "\(head) belt mark")
        }
        let belted = guide(.any, .belted)
        XCTAssertTrue(belted.caseOutline.contains(CGPoint(x: 69, y: MeasuringGuide.axis - MeasuringGuide.belt.radius + 1)))
        XCTAssertFalse(guide(.any, .rimless).caseOutline.contains(CGPoint(x: 69, y: MeasuringGuide.axis - MeasuringGuide.belt.radius + 1)))
        XCTAssertEqual(belted.shownExtensions.count, guide(.any, .rimless).shownExtensions.count + 1, "the belt's line up to its letter")
        let bulletMark = straight.shownMarks.first { $0.letter == "D" }
        XCTAssertEqual(bulletMark?.to.y, MeasuringGuide.axis + straight.bulletRadius)
        XCTAssertTrue(MeasuringGuide().shownMarks.allSatisfy { $0.letter != "G" }, "the training sketch has no belt")
    }

    /// The dimensions form draws the sketch with its own fields' letters: those marks and lines, nothing else
    /// (TestFlight 2026-11-16); the head's line stays while a length is shown.
    func testTheFormShowsItsLettersOnly() {
        XCTAssertTrue(MeasureView.letters.isSubset(of: MeasuringGuide.marks.map(\.letter)))
        let guide = MeasuringGuide(letters: MeasureView.letters)
        XCTAssertEqual(Set(guide.shownMarks.map(\.letter)), MeasureView.letters)
        XCTAssertEqual(guide.shownExtensions.count, MeasuringGuide.extensions.filter { !$0.letters.filter(MeasureView.letters.contains).isEmpty }.count)
        XCTAssertTrue(guide.shownExtensions.contains { $0 == [CGPoint(x: 40, y: 140), CGPoint(x: 40, y: 184)] }, "the head's line, down to OAL")
        XCTAssertFalse(guide.shownExtensions.contains { $0.first?.x == 286 }, "H's line")
        XCTAssertEqual(MeasuringGuide().shownMarks.count, MeasuringGuide.marks.count)
        XCTAssertEqual(MeasuringGuide.dimensionLines(guide.shownMarks).count, 3 * guide.shownMarks.count)
        // No field on the head view, so none is drawn and the box ends after the side view (TestFlight 2026-11-17).
        XCTAssertFalse(guide.showsHead)
        XCTAssertTrue(MeasuringGuide().showsHead)
        XCTAssertTrue(MeasuringGuide(letters: ["P"]).showsHead)
        XCTAssertLessThan(guide.box.maxX, 594 - 43.2, "the head view is outside")
        let drawn = guide.shownMarks.map { [$0.from, $0.to, $0.label] } + guide.shownExtensions
        for line in drawn + [[CGPoint(x: guide.bullet.boundingRect.maxX, y: 0)]] {
            XCTAssertTrue(line.allSatisfy { $0.x >= guide.box.minX && $0.x <= guide.box.maxX }, "\(line)")
        }
        XCTAssertEqual(MeasuringGuide().box, MeasuringGuide.box)
    }

    /// The lengths stand on rows from the first down without a gap for a hidden one, and the box ends below the last
    /// (review 2026-11-19): the form's L and OAL take the first two rows, a straight case's E, L, OAL three.
    /// The head's line starts under the rim like E's own; the patch's lines start under the mouth and the nose.
    func testLengthRowsCloseUp() throws {
        let form = MeasuringGuide(letters: MeasureView.letters)
        XCTAssertEqual(form.rows, ["L": 156, "OAL": 180])
        XCTAssertEqual(form.box.maxY, 188)
        XCTAssertEqual(form.shownMarks.first { $0.letter == "OAL" }?.label.y, 175)
        let straight = MeasuringGuide(letters: Set(TrainingPackageView.fields(shape: .straight, head: .rimless, bullet: "paper").map(\.letter)),
                                      shape: .straight, head: .rimless)
        XCTAssertEqual(straight.rows, ["E": 156, "L": 180, "OAL": 204])
        XCTAssertEqual(MeasuringGuide().rows, ["E": 156, "H": 180, "L": 204, "OAL": 228])
        XCTAssertEqual(MeasuringGuide().box, MeasuringGuide.box)
        let lines = straight.shownExtensions
        let rimBottom = MeasuringGuide.axis + straight.rimRadius + 0.8
        XCTAssertTrue(lines.contains([CGPoint(x: 40, y: rimBottom), CGPoint(x: 40, y: 208)]), "the head's line")
        XCTAssertTrue(lines.contains([CGPoint(x: 49.6, y: rimBottom), CGPoint(x: 49.6, y: 160)]), "E's line")
        let mouth = try XCTUnwrap(lines.first { $0[0].x == 362.2 })
        XCTAssertGreaterThan(mouth[0].y, MeasuringGuide.axis + straight.neckRadius, "below the straight case's mouth")
        let patchEnd = try XCTUnwrap(lines.first { $0[0].x == 430 })
        XCTAssertFalse(straight.bullet.contains(CGPoint(x: 430, y: patchEnd[0].y - 0.5)), "just under the nose")
        XCTAssertTrue(straight.bullet.contains(CGPoint(x: 430, y: patchEnd[0].y - 2)))
        // PP under the bullet, clear of D's letter and line above it.
        let pp = try XCTUnwrap(straight.shownMarks.first { $0.letter == "PP" })
        XCTAssertGreaterThan(pp.from.y, MeasuringGuide.axis + straight.bulletRadius)
    }

    private static func bounds(_ line: [CGPoint]) -> CGRect {
        let xs = line.map(\.x), ys = line.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }
}
