import SwiftUI
import XCTest
@testable import Kaliberfinder

/// Each calibre is drawn with its original bullet and case (Raven, 2026-11-05): bare lead,
/// paper-patched lead, a soft point's lead tip, or a copper jacket; copper, steel or paper cases.
final class BulletMaterialTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    func testLeadBulletsAreDrawnInLead() throws {
        for id in [".22 LR", ".38 Special", ".45-70 Government"] {
            XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge(id)), CartridgeView.lead, id)
        }
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("9x19 mm")), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.bulletFill(for: try cartridge("7.5x53.5 mm Swiss (GP 1890)")), CartridgeView.steel)
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
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge(".44 Henry")), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge("5.45x39 mm")), CartridgeView.lacqueredSteel)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge("7 mm Backcountry")), CartridgeView.nickel)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge(".577 Snider")), CartridgeView.paper)
        XCTAssertEqual(CartridgeView.caseFill(for: try cartridge("9x19 mm")), CartridgeView.brass)
    }

    /// The case seen from below has the colour of the head in the side view (Raven, 2026-11-06).
    func testCaseBottomHasTheSideViewsHeadColour() throws {
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("5.45x39 mm")), CartridgeView.lacqueredSteel)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge(".44 Henry")), CartridgeView.copper)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("7 mm Backcountry")), CartridgeView.nickel)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge(".577 Snider")), CartridgeView.brass, "brass cup, paper body")
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("9x19 mm")), CartridgeView.brass)
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge(".277 SIG Fury")), CartridgeView.steel, "steel head, brass body")
        XCTAssertEqual(CartridgeView.headFill(for: try cartridge("12/70")), CartridgeView.brass, "brass head, plastic hull")
        // Without a head part, the side view shows the case's colour down to the rim.
        for c in CartridgeCatalog.all where c.hasCase && c.outline.head == nil {
            XCTAssertEqual(CartridgeView.headFill(for: c), CartridgeView.caseFill(for: c), c.name)
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
}
