import XCTest
@testable import Kaliberfinder

/// The dimensioned drawing (MeasurementsView): where its dimension lines and labels go.
final class MeasurementsTests: XCTestCase {
    /// An iPhone 17 Pro and an iPhone SE, inside the screen's margins.
    private let phone = CGSize(width: 370, height: 700)
    private let small = CGSize(width: 343, height: 520)
    private let label = DimensionLayout.label
    /// The labels at text size xxxLarge.
    private let largest = DimensionLayout.largestLabel

    private func layout(_ id: String, size: CGSize? = nil, label: CGSize? = nil) throws -> DimensionLayout {
        DimensionLayout(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: id)), size: size ?? phone, label: label ?? self.label)
    }

    /// The drawing shows what the detail screen lists: no bullet on blanks and shot shells, no neck on
    /// shot shells, a shoulder only on bottleneck cases, and one length where the case is the whole round.
    func testPartsFollowTheDetailScreen() throws {
        XCTAssertEqual(try layout("9x19 mm").dimensions.map(\.part), [.bullet, .neck, .base, .rim, .caseLength, .overall])
        XCTAssertEqual(try layout("7.5x55 mm Swiss (GP 11)").dimensions.map(\.part),
                       [.bullet, .neck, .shoulder, .base, .rim, .caseLength, .overall])
        XCTAssertEqual(try layout("12/70").dimensions.map(\.part), [.base, .rim, .overall])
        XCTAssertEqual(try layout(".378 Weatherby Magnum").dimensions.map(\.part),
                       [.bullet, .neck, .shoulder, .base, .belt, .rim, .caseLength, .overall])  // the belt is wider than the rim
        XCTAssertEqual(try layout(".22 SH (5.6/11)").dimensions.map(\.part), [.neck, .base, .rim, .overall])
        XCTAssertEqual(try layout("9 mm PA Blanc").dimensions.map(\.part), [.neck, .base, .rim, .overall])  // closed inside the case
        XCTAssertEqual(try layout(".32 S&W Long Wadcutter").dimensions.map(\.part), [.bullet, .neck, .base, .rim, .overall])
        XCTAssertEqual(try layout("6 mm Airsoft-BB").dimensions.map(\.part), [.bullet, .overall])
    }

    /// Each diameter's line crosses the drawing where it is that wide, on every calibre; a flush-seated
    /// bullet is inside the case, so its line is at the mouth.
    func testDiametersSitWhereTheDrawingIsThatWide() {
        XCTAssertGreaterThan(CartridgeCatalog.all.count, 400)
        for c in CartridgeCatalog.all {
            let whole = OutlineGeometry(c.outline), empty = OutlineGeometry(c.outline, includeBullet: false)
            let flush = c.hasCase && c.dimensions.overallLength - c.dimensions.caseLength < 0.1
            for mark in DimensionLayout.diameters(of: c) where mark.part != .rim && !(mark.part == .bullet && flush) {
                let width = (mark.part == .bullet ? whole : empty).width(at: mark.y)
                XCTAssertEqual(width, mark.mm, accuracy: 0.25, "\(c.id) \(mark.part)")
            }
        }
    }

    /// The base's line is on the body just in front of the extractor groove, rim or belt, not on the
    /// rim of a rimless case or on the ramp up to a belt.
    func testBaseLineIsInFrontOfTheHead() throws {
        for c in CartridgeCatalog.all where c.hasCase {
            XCTAssertNotNil(DimensionLayout.bodyStart(of: c, in: OutlineGeometry(c.outline, includeBullet: false)), c.id)
        }
        // A belt within 0.25 mm of the base (tester, 2026-11-14: «Shouldn't base measure above the belt?»): the
        // base's line is on the body in front of the belt, the belt's own line on the belt where the data has one.
        for id in ["7x73 mm Vom Hofe Belted", ".400/375 Belted Nitro Express", ".378 Weatherby Magnum", ".300 Winchester Magnum"] {
            let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
            let empty = OutlineGeometry(c.outline, includeBullet: false), d = c.dimensions, height = c.outline.height
            let body = try XCTUnwrap(DimensionLayout.bodyStart(of: c, in: empty), id)
            XCTAssertEqual(empty.width(at: height - body - 0.5), d.base, accuracy: 0.05, "\(id): on the body")
            XCTAssertGreaterThan(empty.width(at: height - body + 0.3), d.base + 0.1, "\(id): the belt is just below")
            let marks = DimensionLayout.diameters(of: c)
            XCTAssertEqual(marks.contains { $0.part == .belt }, d.belt != nil, id)
            if let belt = marks.first(where: { $0.part == .belt }) {
                XCTAssertEqual(empty.width(at: belt.y), try XCTUnwrap(d.belt), accuracy: 0.05, id)
                XCTAssertLessThan(try XCTUnwrap(marks.first { $0.part == .base }).y, belt.y, "\(id): the base's line above the belt's")
            }
        }
    }

    /// The lines are as long as their values at the drawing's scale, the diameters across the
    /// drawing's axis, the rim's below the base and the lengths ending on the base.
    func testLinesAreAsLongAsTheValues() throws {
        let gp11 = try layout("7.5x55 mm Swiss (GP 11)")
        let s = gp11.scale, axis = Double(gp11.origin.x) + 12.6 / 2 * s, base = Double(gp11.origin.y) + 77.5 * s
        for d in gp11.dimensions {
            XCTAssertEqual(Double(hypot(d.to.x - d.from.x, d.to.y - d.from.y)), d.mm * s, accuracy: 1e-6, "\(d.part)")
            if d.part.isDiameter {
                XCTAssertEqual(d.from.y, d.to.y, "\(d.part)")
                XCTAssertEqual(Double(d.from.x + d.to.x) / 2, axis, accuracy: 1e-6, "\(d.part)")
            } else {
                XCTAssertEqual(Double(d.to.y), base, accuracy: 1e-6, "\(d.part)")
            }
        }
        let rim = try XCTUnwrap(gp11.dimensions.first { $0.part == .rim })
        XCTAssertEqual(Double(rim.from.y), base + DimensionLayout.rimGap, accuracy: 1e-6)
        XCTAssertEqual(gp11.arrowheads.count, 2 * gp11.dimensions.count)
    }

    /// A rim on a foot («Mauser base», calibre-data #189): the rim's dimension line stays below the base, but its
    /// extension lines start at the rim's underside, not at the base under the narrower foot. Only the seven
    /// calibres with a foot have one; every other rim stands on the base.
    func testARimOnAFootIsDimensionedFromTheRim() throws {
        let feet = ["11x59 mm R Gras": 1.0, "10.4x38 mm R Vetterli Centrefire": 0.8, "9.5x60 mm R Turkish Mauser": 0.9,
                    "10.15x61 mm R Jarmann": 0.8, "10.15x63 mm R Serbian Mauser": 0.8, "11.15x58 mm R Werndl M77": 0.8,
                    "11x60 mm R Japanese Murata": 0.9]
        for c in CartridgeCatalog.all {
            XCTAssertEqual(DimensionLayout.rimUnderside(of: c), feet[c.name] ?? 0, accuracy: 1e-6, c.name)
        }
        let gras = try layout("11x59 mm R Gras"), height = try XCTUnwrap(CartridgeCatalog.cartridge(id: "11x59 mm R Gras")).outline.height
        let base = Double(gras.origin.y) + height * gras.scale
        let rim = try XCTUnwrap(gras.dimensions.first { $0.part == .rim })
        XCTAssertEqual(Double(rim.from.y), base + DimensionLayout.rimGap, accuracy: 1e-6)
        // The two vertical lines that end just above the rim's line: they start 1 mm (the foot) above the base, plus 2 pt.
        let extensions = gras.lines.filter { $0.count == 2 && $0[0].x == $0[1].x && abs(Double($0[1].y) - (Double(rim.from.y) + 4)) < 1e-6 }
        XCTAssertEqual(extensions.count, 2)
        for line in extensions {
            XCTAssertEqual(Double(line[0].y), base - 1.0 * gras.scale + 2, accuracy: 1e-6)
        }
        // The lengths' line along the base starts right of the rim's right extension line, not under the rim.
        let baseLine = try XCTUnwrap(gras.lines.first { $0.count == 2 && $0[0].y == $0[1].y && abs(Double($0[0].y) - base) < 1e-6 })
        let rightmost = try XCTUnwrap(extensions.map { $0[0].x }.max())
        XCTAssertGreaterThan(baseLine[0].x, rightmost)
    }

    /// On a phone every calibre fits, also with the largest labels (text size xxxLarge): lines and labels
    /// stay on screen, the diameter labels keep the order of their lines, and labels do not overlap.
    func testEveryCalibreFitsAPhone() {
        let slack: CGFloat = 1e-6
        for (size, asked) in [(phone, label), (small, label), (phone, largest), (small, largest)] {
            for c in CartridgeCatalog.all {
                let layout = DimensionLayout(cartridge: c, size: size, label: asked)
                let label = layout.labelSize
                // Labels give way down to `minScale`; a round too long for the screen at that scale (the
                // 150 mm 5.66x39 mm MPS dart) is bounded by the height alone.
                let tallest = (size.height - DimensionLayout.rimGap - asked.height) / c.outline.height
                XCTAssertGreaterThanOrEqual(layout.scale, min(DimensionLayout.minScale, tallest) - 1e-9, c.id)
                XCTAssertLessThanOrEqual(label.width, asked.width)
                let points = layout.dimensions.flatMap { [$0.from, $0.to] } + layout.lines.joined() + layout.arrowheads.joined()
                for p in points {
                    XCTAssertTrue(p.x >= -slack && p.x <= size.width + slack && p.y >= -slack && p.y <= size.height + slack, "\(c.id) \(p)")
                }
                let diameters = layout.dimensions.filter(\.trailing)
                for (a, b) in zip(diameters, diameters.dropFirst()) {
                    XCTAssertLessThan(a.from.y, b.from.y, "\(c.id) \(a.part) \(b.part)")
                    XCTAssertGreaterThanOrEqual(b.anchor.y - a.anchor.y, label.height - slack, "\(c.id) \(a.part) \(b.part)")
                }
                let lengths = layout.dimensions.filter { !$0.trailing }
                for (a, b) in zip(lengths, lengths.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(abs(b.anchor.y - a.anchor.y), label.height - slack, "\(c.id) lengths")
                }
                for d in layout.dimensions {
                    let left = d.trailing ? d.anchor.x - label.width : d.anchor.x
                    XCTAssertGreaterThanOrEqual(left, -slack, "\(c.id) \(d.part)")
                    XCTAssertLessThanOrEqual(left + label.width, size.width + slack, "\(c.id) \(d.part)")
                    XCTAssertGreaterThanOrEqual(d.anchor.y - label.height / 2, -slack, "\(c.id) \(d.part)")
                    XCTAssertLessThanOrEqual(d.anchor.y + label.height / 2, size.height + slack, "\(c.id) \(d.part)")
                }
            }
        }
    }

    /// Labels keep their asked width where they fit, even the largest on an iPhone SE, and give way on
    /// a narrower view (split screen); nothing breaks on a view that has no size yet.
    func testLabelsGiveWayOnlyWhenNeeded() throws {
        XCTAssertEqual(try layout("9x19 mm").labelSize, label)
        XCTAssertEqual(try layout(".700 Nitro Express", size: small, label: largest).labelSize, largest)
        let large = try layout("9x19 mm", size: CGSize(width: 260, height: 520), label: largest)
        XCTAssertLessThan(large.labelSize.width, largest.width)
        XCTAssertEqual(large.labelSize.height, largest.height)
        let empty = DimensionLayout(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm")), size: .zero, label: label)
        XCTAssertEqual(empty.scale, 0)
    }

    /// The overall length's line stands right next to the case length's, not beyond its label (Raven,
    /// 2026-11-09: it stuck out); both labels are right of it, the overall length's higher.
    func testLengthsStandSideBySide() throws {
        for id in ["9 mm Flobert Bosquette", "9x19 mm", "7.5x55 mm Swiss (GP 11)", ".38 Special Wadcutter"] {
            let drawing = try layout(id), width = try XCTUnwrap(CartridgeCatalog.cartridge(id: id)).outline.width
            let right = Double(drawing.origin.x) + width * drawing.scale
            let caseLength = try XCTUnwrap(drawing.dimensions.first { $0.part == .caseLength })
            let overall = try XCTUnwrap(drawing.dimensions.first { $0.part == .overall })
            XCTAssertEqual(Double(caseLength.from.x), right + DimensionLayout.lengthGap, accuracy: 1e-6, id)
            XCTAssertEqual(Double(overall.from.x - caseLength.from.x), DimensionLayout.lengthSpacing, accuracy: 1e-6, id)
            for d in [caseLength, overall] {
                XCTAssertEqual(Double(d.anchor.x), Double(overall.from.x) + DimensionLayout.labelInset, accuracy: 1e-6, id)
            }
            XCTAssertLessThan(overall.anchor.y, caseLength.anchor.y, id)
        }
    }

    /// Labels that would overlap move apart; when the last one reaches the bottom, the others move up.
    func testSpreadKeepsLabelsApart() {
        XCTAssertEqual(DimensionLayout.spread([100, 110, 300], spacing: 30, within: 15...685), [100, 130, 300])
        XCTAssertEqual(DimensionLayout.spread([660, 670, 680], spacing: 30, within: 15...685), [625, 655, 685])
        XCTAssertEqual(DimensionLayout.spread([0, 5], spacing: 30, within: 15...685), [15, 45])
    }

    /// Values follow the unit setting; diameters carry «Ø».
    func testValuesFollowTheUnit() throws {
        let nine = try layout("9x19 mm")
        let bullet = try XCTUnwrap(nine.dimensions.first { $0.part == .bullet })
        let overall = try XCTUnwrap(nine.dimensions.first { $0.part == .overall })
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(DimensionLayout.valueText(bullet, unit: .metric, locale: en), "Ø 9.0 mm")
        XCTAssertEqual(DimensionLayout.valueText(bullet, unit: .imperial, locale: en), "Ø 0.356 in")
        XCTAssertEqual(DimensionLayout.valueText(overall, unit: .metric, locale: en), "29.7 mm")
        XCTAssertEqual(DimensionLayout.valueText(overall, unit: .imperial, locale: en), "1.169 in")
        // A whole number keeps a decimal (Raven, 2026-11-09: «Show 9mm as 9.0mm»), everywhere since the 0.1 mm rounding.
        let two23 = try layout(".223 Remington")
        let shoulder = try XCTUnwrap(two23.dimensions.first { $0.part == .shoulder })
        XCTAssertEqual(DimensionLayout.valueText(shoulder, unit: .metric, locale: en), "Ø 9.0 mm")
        XCTAssertEqual(LengthUnit.metric.format(9, locale: en), "9.0 mm")
    }

    /// A ball's diameter is at its equator.
    func testBallDiameterIsAtTheEquator() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "6 mm Airsoft-BB"))
        let bullet = try XCTUnwrap(DimensionLayout.diameters(of: c).first)
        XCTAssertEqual(bullet.y, 3, accuracy: 0.15)
    }
}
