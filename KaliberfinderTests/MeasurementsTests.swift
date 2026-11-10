import XCTest
@testable import Kaliberfinder

/// The dimensioned drawing (MeasurementsView): where its dimension lines and labels go.
final class MeasurementsTests: XCTestCase {
    /// An iPhone 17 Pro and an iPhone SE, inside the screen's margins.
    private let phone = CGSize(width: 370, height: 700)
    private let small = CGSize(width: 343, height: 520)
    private let label = CGSize(width: 74, height: 30)
    /// The labels at text size xxxLarge (MeasurementsView.largestLabel).
    private let largest = CGSize(width: 111, height: 45)

    /// The training series' calliper values (`TrainingPackageView`), in its list row on a 17 Pro and an SE.
    private let calliper = Set(Measurements.drawn.keys)
    private let rows = [CGSize(width: 322, height: 300), CGSize(width: 311, height: 300)]

    private func layout(_ id: String, size: CGSize? = nil, label: CGSize? = nil, parts: Set<DimensionLayout.Part> = DimensionLayout.Part.catalogue) throws -> DimensionLayout {
        DimensionLayout(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: id)), size: size ?? phone, label: label ?? self.label, parts: parts)
    }

    /// The drawing shows what the detail screen lists: no bullet on blanks and shot shells, no neck on
    /// shot shells, a shoulder only on bottleneck cases, and one length where the case is the whole round.
    func testPartsFollowTheDetailScreen() throws {
        XCTAssertEqual(try layout("9x19 mm").dimensions.map(\.part), [.bullet, .neck, .base, .rim, .caseLength, .overall])
        XCTAssertEqual(try layout("7.5x55 mm Swiss (GP 11)").dimensions.map(\.part),
                       [.bullet, .neck, .shoulder, .base, .rim, .caseLength, .overall])
        XCTAssertEqual(try layout("12/70").dimensions.map(\.part), [.base, .rim, .overall])
        XCTAssertEqual(try layout(".22 Blank (6.8/11)").dimensions.map(\.part), [.neck, .base, .rim, .overall])
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
                // Above a belt the body is drawn 1.5 % narrower than the base diameter.
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
        // From the generated outlines: 9x19 mm's body starts 2.98 mm above the base, .300 Win Mag's
        // in front of the belt, 5.59 mm up.
        for (id, start) in [("9x19 mm", 2.98), (".300 Winchester Magnum", 5.59)] {
            let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: id))
            let found = try XCTUnwrap(DimensionLayout.bodyStart(of: c, in: OutlineGeometry(c.outline, includeBullet: false)))
            XCTAssertEqual(found, start, accuracy: 0.3, id)
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

    /// On a phone every calibre fits, also with the largest labels (text size xxxLarge): lines and labels
    /// stay on screen, the diameter labels keep the order of their lines, and labels do not overlap.
    func testEveryCalibreFitsAPhone() {
        for (size, asked) in [(phone, label), (small, label), (phone, largest), (small, largest)] {
            for c in CartridgeCatalog.all {
                let layout = DimensionLayout(cartridge: c, size: size, label: asked)
                XCTAssertGreaterThanOrEqual(layout.scale, DimensionLayout.minScale - 1e-9, c.id)
                XCTAssertLessThanOrEqual(layout.labelSize.width, asked.width)
                assertFits(layout, in: size, c.id)
            }
        }
    }

    /// The training series' drawing fits its row too, for every calibre and both label sizes.
    func testEveryCalibreFitsTheTrainingSeries() {
        for size in rows {
            for asked in [label, largest] {
                for c in CartridgeCatalog.all {
                    assertFits(DimensionLayout(cartridge: c, size: size, label: asked, parts: calliper), in: size, c.id)
                }
            }
        }
    }

    /// Lines and labels stay inside `size`, the diameter labels keep the order of their lines, and labels
    /// do not overlap.
    private func assertFits(_ layout: DimensionLayout, in size: CGSize, _ id: String) {
        let slack: CGFloat = 1e-6, label = layout.labelSize
        let points = layout.dimensions.flatMap { [$0.from, $0.to] } + layout.lines.joined() + layout.arrowheads.joined()
        for p in points {
            XCTAssertTrue(p.x >= -slack && p.x <= size.width + slack && p.y >= -slack && p.y <= size.height + slack, "\(id) \(p)")
        }
        let diameters = layout.dimensions.filter(\.trailing)
        for (a, b) in zip(diameters, diameters.dropFirst()) {
            XCTAssertLessThan(a.from.y, b.from.y, "\(id) \(a.part) \(b.part)")
            XCTAssertGreaterThanOrEqual(b.anchor.y - a.anchor.y, label.height - slack, "\(id) \(a.part) \(b.part)")
        }
        let lengths = layout.dimensions.filter { !$0.trailing }
        for (a, b) in zip(lengths, lengths.dropFirst()) {
            XCTAssertGreaterThanOrEqual(abs(b.anchor.y - a.anchor.y), label.height - slack, "\(id) lengths")
        }
        for d in layout.dimensions {
            let left = d.trailing ? d.anchor.x - label.width : d.anchor.x
            XCTAssertGreaterThanOrEqual(left, -slack, "\(id) \(d.part)")
            XCTAssertLessThanOrEqual(left + label.width, size.width + slack, "\(id) \(d.part)")
            XCTAssertGreaterThanOrEqual(d.anchor.y - label.height / 2, -slack, "\(id) \(d.part)")
            XCTAssertLessThanOrEqual(d.anchor.y + label.height / 2, size.height + slack, "\(id) \(d.part)")
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
        XCTAssertEqual(DimensionLayout.valueText(bullet.part, mm: bullet.mm, unit: .metric, locale: en), "Ø 9.01 mm")
        XCTAssertEqual(DimensionLayout.valueText(bullet.part, mm: bullet.mm, unit: .imperial, locale: en), "Ø 0.355 in")
        XCTAssertEqual(DimensionLayout.valueText(overall.part, mm: overall.mm, unit: .metric, locale: en), "29.7 mm")
        XCTAssertEqual(DimensionLayout.valueText(overall.part, mm: overall.mm, unit: .imperial, locale: en), "1.169 in")
        // A whole number keeps a decimal in the drawing (Raven, 2026-11-09: «Show 9mm as 9.0mm»).
        let two23 = try layout(".223 Remington")
        let shoulder = try XCTUnwrap(two23.dimensions.first { $0.part == .shoulder })
        XCTAssertEqual(DimensionLayout.valueText(shoulder.part, mm: shoulder.mm, unit: .metric, locale: en), "Ø 9.0 mm")
        XCTAssertEqual(LengthUnit.metric.format(9, locale: en), "9 mm", "elsewhere the number stays as it was")
        // A calliper value not measured yet.
        XCTAssertEqual(DimensionLayout.valueText(.rim, mm: nil, unit: .metric), "Ø –")
        XCTAssertEqual(DimensionLayout.valueText(.shoulderLength, mm: nil, unit: .metric), "–")
        XCTAssertEqual(DimensionLayout.valueText(.shoulderLength, mm: 44.65, unit: .metric, locale: en), "44.65 mm")
    }

    /// The training series draws only what the calliper measures (Raven 2026-11-10): on a bottleneck case
    /// also the base to where the shoulder starts, level with the shoulder's diameter, as the inner length.
    func testTrainingSeriesDrawsTheCalliperValues() throws {
        let gp11 = try layout("7.5x55 mm Swiss (GP 11)", parts: calliper)
        XCTAssertEqual(gp11.dimensions.map(\.part), [.bullet, .shoulder, .rim, .shoulderLength, .caseLength, .overall])
        XCTAssertEqual(try layout("9x19 mm", parts: calliper).dimensions.map(\.part), [.bullet, .rim, .caseLength, .overall], "no shoulder")
        let toShoulder = try XCTUnwrap(gp11.dimensions.first { $0.part == .shoulderLength })
        let shoulder = try XCTUnwrap(gp11.dimensions.first { $0.part == .shoulder })
        // GP 11's generated outline: the shoulder meets the body 32.92 mm below the tip; the 0.1 mm search
        // reaches the shoulder's width (less 0.15 mm) at 32.8 mm, 44.7 mm above the base.
        XCTAssertEqual(toShoulder.mm, 44.7, accuracy: 0.05)
        XCTAssertEqual(Double(shoulder.from.y - toShoulder.from.y), 0.5 * gp11.scale, accuracy: 1e-6, "the shoulder's line is 0.5 mm lower, on the body")
        let caseLength = try XCTUnwrap(gp11.dimensions.first { $0.part == .caseLength })
        XCTAssertEqual(Double(caseLength.from.x - toShoulder.from.x), DimensionLayout.lengthSpacing, accuracy: 1e-6)
        XCTAssertNil(DimensionLayout.lengths(of: try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))).first { $0.part == .shoulderLength })
    }

    /// A ball's diameter is at its equator.
    func testBallDiameterIsAtTheEquator() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "6 mm Airsoft-BB"))
        let bullet = try XCTUnwrap(DimensionLayout.diameters(of: c).first)
        XCTAssertEqual(bullet.y, 3, accuracy: 0.15)
    }
}
