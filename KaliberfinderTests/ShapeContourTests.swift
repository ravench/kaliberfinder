import CoreGraphics
import XCTest
@testable import Kaliberfinder

/// The green outline drawn over the photo follows the cartridge's shape (SHAPE-07): the bullet as a
/// typical nose curve, straight lines along the neck and body, from what was detected, joined into one.
final class ShapeContourTests: XCTestCase {
    private let ppm = 6.0
    private let step = 0.15

    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// Pixel position of outline point (x, y) in mm, turned by `angle`, as in the other shape tests.
    private func pixel(_ x: Double, _ y: Double, angle: Double) -> CGPoint {
        CGPoint(x: ppm * (x * cos(angle) - y * sin(angle)) + 500, y: ppm * (x * sin(angle) + y * cos(angle)) + 500)
    }

    /// The silhouette points of the cartridge (or its case) lying on its side, and its outline geometry.
    private func silhouette(_ c: Cartridge, caseOnly: Bool, angle: Double) -> (points: [Point], geometry: OutlineGeometry, top: Double) {
        let g = OutlineGeometry(c.outline, includeBullet: !caseOnly)
        let top = caseOnly ? c.outline.height - c.dimensions.caseLength : 0
        var points: [Point] = []
        var y = top + step / 2
        while y < c.outline.height {
            var x = step / 2
            while x < c.outline.width {
                if g.contains(Point(x: x, y: y)) {
                    let p = pixel(x, y, angle: angle)
                    points.append(Point(x: p.x, y: p.y))
                }
                x += step
            }
            y += step
        }
        return (points, g, top)
    }

    /// Area of a closed polygon (shoelace).
    private func area(_ p: [CGPoint]) -> Double {
        abs(p.indices.reduce(0.0) { s, i in let a = p[i], b = p[(i + 1) % p.count]; return s + a.x * b.y - b.x * a.y }) / 2
    }

    /// The polygon for a cartridge, checked against the silhouette: it covers about the silhouette's
    /// area (far less than its box when the shape narrows), and no corner lies more than 1 mm off its
    /// edge (the lines and curves are fitted, and the neck's width runs on over a slimmer bullet).
    private func check(_ id: String, caseOnly: Bool, angle: Double) throws -> (polygon: ShapeContour, boxArea: Double, silhouetteArea: Double) {
        let c = try cartridge(id)
        let (points, _, _) = silhouette(c, caseOnly: caseOnly, angle: angle)
        let pixelSize = ppm * step
        let box = try XCTUnwrap(ShapeMatcher.orientedBox(points, pixelSize: pixelSize))
        let shape = try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: pixelSize), id)
        let polygon = try XCTUnwrap(ShapeContour.polygon(points, pixelSize: pixelSize, shape: shape, box: box), id)
        XCTAssertEqual(polygon.parts.count, polygon.points.count, id)
        let silhouetteArea = Double(points.count) * pixelSize * pixelSize
        XCTAssertEqual(area(polygon.points), silhouetteArea, accuracy: 0.1 * silhouetteArea, "\(id) angle \(angle)")
        for corner in polygon.points {
            let nearest = points.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? .infinity
            XCTAssertLessThan(nearest / ppm, 1, "\(id) angle \(angle)")
        }
        let boxArea = hypot(box[1].x - box[0].x, box[1].y - box[0].y) * hypot(box[3].x - box[0].x, box[3].y - box[0].y)
        return (polygon, boxArea, silhouetteArea)
    }

    func testOutlineFollowsTheNeckOfAnEmptyGP11Case() throws {
        for angle in [0.7, 0.7 + .pi, 2.0] {
            let (polygon, boxArea, silhouetteArea) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: true, angle: angle)
            // The neck and shoulder are cut out of the box.
            XCTAssertLessThan(silhouetteArea, 0.95 * boxArea, "angle \(angle)")
            // Straight lines only: mouth, neck end, shoulder, head on each side; each edge from its detection.
            XCTAssertEqual(polygon.parts, [.neck, .neck, .body, .end, .body, .neck, .neck, .end], "angle \(angle)")
            XCTAssertNil(polygon.nose, "angle \(angle)")
        }
    }

    func testOutlineFollowsTheBulletOfALoadedRound() throws {
        let (polygon, boxArea, silhouetteArea) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: false, angle: 0.7)
        XCTAssertLessThan(silhouetteArea, 0.9 * boxArea)
        // The pointed bullet: the outline comes close to the tip.
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let tip = pixel(gp11.outline.width / 2, 0, angle: 0.7)
        let nearest = polygon.points.map { hypot($0.x - tip.x, $0.y - tip.y) }.min() ?? .infinity
        XCTAssertLessThan(nearest / ppm, 1.5)
        // The bullet's edges start each side, from the tip, and the tip is an end.
        XCTAssertEqual(polygon.parts.first, .bullet)
        XCTAssertEqual(polygon.parts.last, .end)
        XCTAssertTrue(polygon.parts.contains(.neck))
        XCTAssertEqual(polygon.nose?.kind, .pointed)
    }

    /// How far the nose curve, and a straight line from the tip to where the nose ends, are off the
    /// silhouette's slices in front of that point, at most (in body widths, on each side).
    private func noseMiss(_ id: String, angle: Double) throws -> (nose: NoseCurve, curve: Double, straight: Double) {
        let (polygon, _, _) = try check(id, caseOnly: false, angle: angle)
        let nose = try XCTUnwrap(polygon.nose, id)
        // Each side has its nose corners, then the rest of the outline.
        XCTAssertEqual(Array(polygon.parts.prefix(NoseCurve.segments)), Array(repeating: ShapeContour.Part.bullet, count: NoseCurve.segments), id)
        XCTAssertEqual(polygon.parts.filter { $0 == .bullet }.count, 2 * NoseCurve.segments, id)
        let (points, _, _) = silhouette(try cartridge(id), caseOnly: false, angle: angle)
        let w = try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: ppm * step), id).widths
        let bins = Double(w.count), tip = w[0] / 2
        var curve = 0.0, straight = 0.0
        for i in w.indices where (Double(i) + 0.5) / bins < nose.length {
            // A slice's width is its widest point: its back edge on a nose.
            let f = min(Double(i + 1) / bins, nose.length)
            curve = max(curve, abs(nose.half(at: f) - w[i] / 2))
            straight = max(straight, abs(tip + (nose.base - tip) * f / nose.length - w[i] / 2))
        }
        return (nose, curve, straight)
    }

    func testRoundNosesAreDrawnRound() throws {
        for id in ["9x19 mm", ".45 ACP", ".38 Special"] {
            for angle in [0.7, 2.0] {
                let (nose, curve, straight) = try noseMiss(id, angle: angle)
                XCTAssertEqual(nose.kind, .round, "\(id) angle \(angle)")
                // The curve stays within 2.5 % of the body width; a straight line cut off the round nose by twice that.
                XCTAssertLessThan(curve, 0.025, "\(id) angle \(angle)")
                XCTAssertGreaterThan(straight, 0.05, "\(id) angle \(angle)")
            }
        }
    }

    func testPointedNoseOfARifleBullet() throws {
        for id in ["7.5x55 mm Swiss (GP 11)", "5.56x45 mm NATO"] {
            let (nose, curve, _) = try noseMiss(id, angle: 0.7)
            XCTAssertEqual(nose.kind, .pointed, id)
            XCTAssertLessThan(curve, 0.04, id)
        }
    }

    func testNoseCurves() {
        // The catalogue's curves: full width where the nose starts, none at a sharp tip; a pointed nose
        // is slimmer than a round one in between.
        for kind in NoseCurve.Kind.allCases {
            XCTAssertEqual(kind.width(0), 1, accuracy: 1e-12)
            XCTAssertEqual(kind.width(1), 0, accuracy: 1e-12)
        }
        XCTAssertEqual(NoseCurve.Kind.round.width(0.6), 0.8, accuracy: 1e-12)
        XCTAssertLessThan(NoseCurve.Kind.pointed.width(0.5), NoseCurve.Kind.round.width(0.5) - 0.1)
        // Cut flat at the tip, it meets the case or body at its full width.
        let nose = NoseCurve(kind: .round, cut: 0.8, length: 0.3, base: 0.4)
        XCTAssertEqual(nose.half(at: 0), 0.4 * 0.6, accuracy: 1e-12)
        XCTAssertEqual(nose.half(at: 0.3), 0.4, accuracy: 1e-12)
        XCTAssertEqual(nose.half(at: 0.5), 0.4, accuracy: 1e-12)
        // Corners from the tip back, closer together at the tip, the last short of the base.
        let corners = nose.points()
        XCTAssertEqual(corners.count, NoseCurve.segments)
        XCTAssertEqual(corners.first?.f, 0)
        XCTAssertEqual(corners.first?.half ?? 0, 0.24, accuracy: 1e-12)
        let gaps = zip(corners.dropFirst(), corners).map { $0.f - $1.f }
        XCTAssertTrue(gaps.allSatisfy { $0 > 0 })
        XCTAssertEqual(gaps, gaps.sorted())
        XCTAssertLessThan(corners.last?.f ?? 1, 0.3)
    }

    func testFitFindsTheCurveTheSlicesCameFrom() throws {
        let bins = ShapeMatcher.bins
        let truth = NoseCurve(kind: .pointed, cut: NoseCurve.cuts[4], length: 0.3, base: 0.4)
        let halves = (0..<bins).map { i -> Double in
            (Double(i) + 0.5) / Double(bins) < truth.length ? truth.half(at: min(Double(i + 1) / Double(bins), truth.length)) : 0.4
        }
        let bases = [0.25, 0.3, 0.35].map { (f: $0, half: 0.4) }
        XCTAssertEqual(NoseCurve.fitted(halfWidths: halves, bases: bases) { _ in 0.4 }, truth)
        XCTAssertNil(NoseCurve.fitted(halfWidths: halves, bases: []) { _ in 0.4 })
    }

    func testStraightCartridge() throws {
        let (polygon, _, _) = try check("9x19 mm", caseOnly: false, angle: 2.0)
        XCTAssertFalse(polygon.parts.contains(.neck))
        XCTAssertTrue(polygon.parts.contains(.body))
    }

    func testNoOutlineWithoutABoxOrForAnEndView() throws {
        let shape = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        let square = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        XCTAssertNil(ShapeContour.polygon([Point(x: 1, y: 1)], pixelSize: 1, shape: shape, box: []))
        XCTAssertNil(ShapeContour.polygon([], pixelSize: 1, shape: shape, box: square))
        // Seen end on: round, so no outline even with a full set of widths.
        let endView = ShapeMatcher.measurement(aspect: 1, relativeWidths: Array(repeating: 1, count: ShapeMatcher.bins))
        XCTAssertTrue(endView.isEndView)
        XCTAssertNil(ShapeContour.polygon([Point(x: 1, y: 1)], pixelSize: 1, shape: endView, box: square))
    }

    func testPartsKeepTheirEdgesWhenMoved() {
        let nose = NoseCurve(kind: .round, cut: 1, length: 0.2, base: 0.45)
        let contour = ShapeContour(points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0)], parts: [.body, .end], nose: nose)
        let moved = contour.map { CGPoint(x: 0.1 + $0.x * 0.5, y: 0.2 + $0.y * 0.5) }
        XCTAssertEqual(moved.points, [CGPoint(x: 0.35, y: 0.45), CGPoint(x: 0.6, y: 0.2)])
        XCTAssertEqual(moved.parts, [.body, .end])
        XCTAssertEqual(moved.nose, nose)
        // Coloured drawing: each part's edges only, the last edge back to the first corner.
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 5)]
        XCTAssertEqual(CandidatePhotoView.path(edges: [2], of: corners).boundingRect, CGRect(x: 0, y: 0, width: 10, height: 5))
        XCTAssertTrue(CandidatePhotoView.path(edges: [], of: corners).isEmpty)
        XCTAssertEqual(Set(CandidatePhotoView.coloured.map(\.part)).count, 4)
    }

    private func middle(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }

    /// An empty case has no bullet: the nose goes, and the neck (or body) runs on to where the tip was.
    func testOutlineWithoutTheBullet() throws {
        let (loaded, _, _) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: false, angle: 0.7)
        let empty = loaded.withoutBullet()
        XCTAssertNil(empty.nose)
        XCTAssertEqual(empty.parts, [.neck, .neck, .body, .end, .body, .neck, .neck, .end])
        XCTAssertEqual(empty.points.count, empty.parts.count)
        let n = loaded.points.count, b = NoseCurve.segments, m = empty.points.count
        // The mouth lies where the tip was, as wide as the neck; everything behind the neck's start stays.
        let tip = middle(loaded.points[0], loaded.points[n - 1]), mouth = middle(empty.points[0], empty.points[m - 1])
        XCTAssertEqual(mouth.x, tip.x, accuracy: 1e-9)
        XCTAssertEqual(mouth.y, tip.y, accuracy: 1e-9)
        let neck = hypot(loaded.points[b].x - loaded.points[n - 1 - b].x, loaded.points[b].y - loaded.points[n - 1 - b].y)
        XCTAssertEqual(hypot(empty.points[0].x - empty.points[m - 1].x, empty.points[0].y - empty.points[m - 1].y), neck, accuracy: 1e-9)
        XCTAssertEqual(Array(empty.points[1..<(m - 1)]), Array(loaded.points[(b + 1)..<(n - 1 - b)]))
        // A straight case keeps its body up to the mouth; an outline without a bullet stays as it is.
        let (straight, _, _) = try check("9x19 mm", caseOnly: false, angle: 2.0)
        XCTAssertEqual(straight.withoutBullet().parts, [.body, .end, .body, .end])
        let (emptyGP11, _, _) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: true, angle: 0.7)
        XCTAssertEqual(emptyGP11.withoutBullet(), emptyGP11)
    }

    /// The Matches photo draws no bullet on an empty case, whether the app reads one or the user picks «Leere Hülse».
    func testMatchesDrawNoBulletOnAnEmptyCase() throws {
        let id = "7.5x55 mm Swiss (GP 11)"
        let (loaded, _, _) = try check(id, caseOnly: false, angle: 0.7)
        let cartridge = PhotoAnalysis(shape: ShapeMatcher.catalogue[id], contour: loaded)
        XCTAssertEqual(MatchesView.frames(overview: nil, measured: cartridge, picking: false).parts, loaded.parts)
        XCTAssertEqual(MatchesView.frames(overview: nil, measured: cartridge, picking: false, mode: .emptyCase).measured,
                       loaded.withoutBullet().points)
        // Read as an empty case (its neck runs to the mouth): no bullet, unless the user picks «Patrone».
        let emptyCase = PhotoAnalysis(shape: ShapeMatcher.caseCatalogue[id], contour: loaded)
        XCTAssertFalse(MatchesView.frames(overview: nil, measured: emptyCase, picking: false).parts.contains(.bullet))
        XCTAssertEqual(MatchesView.frames(overview: nil, measured: emptyCase, picking: false, mode: .cartridge).measured, loaded.points)
    }

    /// Raven's 6 mm BR (golden shot 6-mm-br-norma-20261105-115031/08, 2026-11-07): its neck's widths vary too
    /// much for `NeckShape`, so the outline read the neck as a bullet. As an empty case it keeps the neck.
    func testEmptyCaseKeepsANeckTooUnevenForNeckShape() {
        let w = [0.47, 0.592, 0.582, 0.557, 0.578, 0.557, 0.524, 0.605, 0.685, 0.799, 0.849, 0.907, 0.936, 0.932, 0.983, 1.002,
                 0.977, 0.981, 0.942, 0.963, 0.975, 0.994, 0.988, 0.983, 1.014, 0.992, 1.01, 1.004, 1.054, 1.0, 1.014, 0.992,
                 1.014, 1.006, 0.992, 0.961, 0.979, 0.965, 0.903, 0.797]
        XCTAssertNil(NeckShape(widths: w, aspect: 3.5))
        XCTAssertNil(NeckShape(widths: Array(w.reversed()), aspect: 3.5))
        let behind: [ShapeContour.Corner] = [(11.5 / 40, 0.47, .body), (1, 0.45, .end)]
        let side = ShapeContour.emptySide(behind, widths: w, hasNeck: false, front: 11)
        XCTAssertEqual(side.map(\.part), [.neck, .neck, .body, .end])
        // The neck from the mouth to the shoulder (slices 1 to 7), as wide as its middle slice.
        XCTAssertEqual(side[0].f, 0)
        XCTAssertEqual(side[1].f, 8 / 40, accuracy: 1e-9)
        XCTAssertEqual(side[0].half, 0.578 / 2, accuracy: 1e-9)
        XCTAssertEqual(side[1].half, side[0].half)
        XCTAssertEqual(side[2].f, behind[0].f)
        XCTAssertEqual(side[3].f, behind[1].f)
        // A detected neck, or a front that narrows like a bullet's nose (9×19), only runs on to the mouth.
        for (widths, neck) in [(w, true), ([0.35, 0.5, 0.61, 0.7, 0.76, 0.81, 0.84, 0.87, 0.89] + [Double](repeating: 0.95, count: 31), false)] {
            let straight = ShapeContour.emptySide(behind, widths: widths, hasNeck: neck, front: neck ? 11 : 9)
            XCTAssertEqual(straight.map(\.part), [.body, .end], "neck \(neck)")
            XCTAssertEqual(straight[0].f, 0)
            XCTAssertEqual(straight[0].half, behind[0].half)
        }
    }

    func testNoColourLegendUnderThePhoto() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let notes = MatchesView.notes(for: PhotoAnalysis(shape: ShapeMatcher.catalogue[gp11.id], contour: ShapeContour(points: [.zero], parts: [.end])), mode: .cartridge)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("Flaschenhals".loc), notes[0])
    }
}
