import XCTest
@testable import Kaliberfinder

/// The «where to measure» sketch over the calliper fields of a training series (MeasuringGuide).
final class MeasuringGuideTests: XCTestCase {
    /// Every calliper value has a field, every field a letter of its own, and each letter is on the sketch once.
    func testEveryFieldHasItsLetterOnTheSketch() {
        let fields = TrainingPackageView.calliperFields, letters = fields.map(\.letter)
        XCTAssertEqual(fields.count, Mirror(reflecting: Measurements()).children.count, "a field for every measurement")
        XCTAssertEqual(Set(letters).count, letters.count)
        XCTAssertEqual(MeasuringGuide.marks.map(\.letter).sorted(), letters.sorted())
        // Each field writes a value of its own.
        var m = Measurements()
        for (i, field) in fields.enumerated() { m[keyPath: field.value] = Double(i + 1) }
        XCTAssertEqual(Set(Mirror(reflecting: m).children.compactMap { $0.value as? Double }), Set((1...fields.count).map(Double.init)))
    }

    /// Drawing, lines and letters stay inside the sketch's box, and a letter neither overlaps another
    /// nor sits on a line or the drawing.
    func testLettersAndLinesFitTheBox() {
        let box = MeasuringGuide.box
        func inside(_ r: CGRect) -> Bool { r.minX >= box.minX && r.maxX <= box.maxX && r.minY >= box.minY && r.maxY <= box.maxY }
        let segments = MeasuringGuide.marks.map { [$0.from, $0.to] } + MeasuringGuide.extensions
        let shapes = [MeasuringGuide.caseOutline.boundingRect, MeasuringGuide.bullet.boundingRect]
        for r in shapes + segments.map(Self.bounds) { XCTAssertTrue(inside(r), "\(r)") }
        // A bold capital on its baseline is about ¾ of the font size wide and high (generous for I, tight for W).
        let size = MeasuringGuide.letterSize
        let letters = MeasuringGuide.marks.map { mark in
            let w = 0.75 * size * Double(mark.letter.count), h = 0.75 * size
            return (mark.letter, CGRect(x: mark.label.x - w / 2, y: mark.label.y - h, width: w, height: h))
        }
        for (i, (letter, r)) in letters.enumerated() {
            XCTAssertTrue(inside(r), letter)
            for (other, o) in letters.dropFirst(i + 1) { XCTAssertFalse(r.intersects(o), "\(letter) \(other)") }
            for s in segments { XCTAssertFalse(r.intersects(Self.bounds(s).insetBy(dx: -0.5, dy: -0.5)), "\(letter) \(s)") }
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            for shape in [MeasuringGuide.caseOutline, MeasuringGuide.bullet] {
                XCTAssertFalse(corners.contains { shape.contains($0) }, letter)
            }
        }
    }

    private static func bounds(_ line: [CGPoint]) -> CGRect {
        let xs = line.map(\.x), ys = line.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }
}
