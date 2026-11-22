import SwiftUI
import XCTest
@testable import Kaliberfinder

/// Each calibre is drawn with its original bullet and case (Raven, 2026-11-05): bare lead,
/// paper-patched lead, a soft point's lead tip, or a copper jacket; copper, steel or paper cases. Where calibre-data
/// names what is most commonly found today, that is drawn unless «Originalfarben zeigen» is on (Raven, 2026-11-22).
final class BulletMaterialTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    func testLeadBulletsAreDrawnInLead() throws {
        for id in [".22 LR", ".38 Special", ".45-70 Government"] {
            XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge(id)), CartridgeView.lead, id)
        }
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("9x19 mm")), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("7.5x53.5 mm Swiss (Patrone Modell 1890)")), CartridgeView.steel)
    }

    /// A jacket that is not copper-coloured is drawn in its metal: the silver cupronickel of the GP 11 and, since
    /// calibre-data #151, of other early service rounds like the 8x57 mm IS; steel on the 7.65x53 mm Argentine.
    func testSilverAndSteelJackets() throws {
        for id in ["7.5x55 mm Swiss (GP 11)", "8x57 mm IS", "6 mm Lee Navy"] {
            XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge(id), original: true), CartridgeView.nickel, id)
        }
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("7.65x53 mm Argentine"), original: true), CartridgeView.steel)
        // No longer made: the original jacket is what is found today too.
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("6 mm Lee Navy"), original: false), CartridgeView.nickel)
    }

    /// By default the app draws what is most commonly found today; the developer switch shows the original.
    func testTodaysColoursUnlessTheOriginalIsAskedFor() throws {
        for id in ["7.5x55 mm Swiss (GP 11)", "8x57 mm IS", "7.65x53 mm Argentine"] {
            XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge(id), original: false), CartridgeView.copper, id)
        }
        let r54 = try cartridge("7.62x54 mm R")
        XCTAssertEqual(CartridgeView.caseFill(for: r54, original: false), CartridgeView.lacqueredSteel)
        XCTAssertEqual(CartridgeView.caseFill(for: r54, original: true), CartridgeView.brass)
        XCTAssertEqual(CartridgeView.headFill(for: r54, original: false), CartridgeView.lacqueredSteel)
        let kurz = try cartridge("7.92x33 mm Kurz")
        XCTAssertEqual(CartridgeView.caseFill(for: kurz, original: false), CartridgeView.brass)
        XCTAssertEqual(CartridgeView.caseFill(for: kurz, original: true), CartridgeView.lacqueredSteel)
        let govt = try cartridge(".45-70 Government")
        XCTAssertEqual(CartridgeView.caseFill(for: govt, original: false), CartridgeView.brass)
        XCTAssertEqual(CartridgeView.caseFill(for: govt, original: true), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("9x19 mm"), original: true), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("9x19 mm"), original: false), CartridgeView.copper)
    }

    func testSoftPointHasALeadTipInsideTheSilhouette() throws {
        let c = try cartridge("9.3x62 mm")
        let tip = try XCTUnwrap(c.outline.tip.map(OutlineGeometry.parse)?.first, "lead tip")
        XCTAssertEqual(tip.map(\.y).min() ?? 1, 0, accuracy: 0.01, "the tip reaches the front of the bullet")
        XCTAssertEqual(CartridgeView.bulletFill(for: c), CartridgeView.copper, "the jacket stays copper")
        // The tip is not part of the shape the photo is matched against.
        XCTAssertEqual(OutlineGeometry(c.outline).polygons.count, OutlineGeometry(c.outline, includeBullet: false).polygons.count + 1)
        XCTAssertNil(try cartridge("7.62x51 mm NATO").outline.tip, "military ball is a full metal jacket")
    }

    func testPolymerTipIsRedAndHybridHeadIsSteel() throws {
        let hmr = try cartridge(".17 HMR")
        XCTAssertNotNil(hmr.outline.tip)
        XCTAssertEqual(hmr.outline.tipMaterial, "polymer")
        XCTAssertNil(try cartridge("9.3x62 mm").outline.tipMaterial, "a soft point's tip is lead")
        let fury = try cartridge(".277 SIG Fury")
        XCTAssertEqual(fury.outline.headMaterial, "steel")
        XCTAssertNotNil(fury.outline.head)
    }

    func testCaseMaterials() throws {
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge(".44 Henry"), original: true), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge("5.45x39 mm"), original: true), CartridgeView.lacqueredSteel)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge("7 mm Backcountry"), original: true), CartridgeView.nickel)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge(".577 Snider"), original: true), CartridgeView.paper)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge("9x19 mm"), original: true), CartridgeView.brass)
    }

    /// The case seen from below has the colour of the head in the side view (Raven, 2026-11-06).
    func testCaseBottomHasTheSideViewsHeadColour() throws {
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("5.45x39 mm"), original: true), CartridgeView.lacqueredSteel)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge(".44 Henry"), original: true), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("7 mm Backcountry"), original: true), CartridgeView.nickel)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge(".577 Snider"), original: true), CartridgeView.brass, "brass cup, paper body")
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("9x19 mm"), original: true), CartridgeView.brass)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge(".277 SIG Fury"), original: true), CartridgeView.steel, "steel head, brass body")
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("12/70"), original: true), CartridgeView.brass, "brass head, plastic hull")
        // Without a head part, the side view shows the case's colour down to the rim.
        for c in CartridgeCatalog.all where c.hasCase && c.outline.head == nil {
            for original in [false, true] {
                XCTAssertEqual(CartridgeView.headFill(for: c, original: original),
                               CartridgeView.caseFill(for: c, original: original), c.name)
            }
        }
    }

    func testSteelBBIsSteelAndAirsoftBBsArePlastic() throws {
        let steelBB = try cartridge("4.4 mm Stahl-BB (.177 BB)")
        XCTAssertEqual(steelBB.kind, "ball")
        XCTAssertEqual(CartridgeView.bulletFill(for: steelBB), CartridgeView.steel)
        for id in ["6 mm Airsoft-BB", "8 mm Airsoft-BB"] {
            XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge(id)), CartridgeView.plastic, id)
        }
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge(".44 Rundkugel (.454)")), CartridgeView.lead)
    }

    /// A hollow point's cavity reads at the detail page's size (Raven, 2026-11-17: the thin dashes were too fine):
    /// it is shaded, its line is bolder than the outline, and each side of a 2 mm deep cavity shows several dashes.
    func testHollowPointCavityIsBold() throws {
        XCTAssertNotNil(try cartridge(".357 SIG").outline.cavity)
        for pointsPerMM in [1.5, 3.0, 7.0, 12.0] {
            let style = CartridgeView.cavityStroke(pointsPerMM: pointsPerMM)
            XCTAssertGreaterThan(style.lineWidth, CartridgeView.lineWidth(pointsPerMM: pointsPerMM), "\(pointsPerMM)")
            // On the detail page (7 points per mm and up), a 2 mm side shows at least three dashes.
            if pointsPerMM >= 7 {
                XCTAssertGreaterThanOrEqual(2 * pointsPerMM / (style.dash[0] + style.dash[1]), 3, "\(pointsPerMM)")
            }
        }
        XCTAssertEqual(CartridgeView.cavityShade, Color.black.opacity(0.35))
        // The mouth lies on the bullet's front edge: the cavity's line leaves it to the outline.
        let open = PolygonShape(polygons: [[Point(x: 0, y: 0), Point(x: 1, y: 2), Point(x: 2, y: 0)]], scale: 1, closed: false)
        var closes = 0
        open.path(in: .zero).forEach { if case .closeSubpath = $0 { closes += 1 } }
        XCTAssertEqual(closes, 0, "no closing segment along the mouth")
    }
}
