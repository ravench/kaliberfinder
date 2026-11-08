import XCTest
import SwiftUI
@testable import Kaliberfinder

final class TrueScaleLayoutTests: XCTestCase {
    private func cartridges(_ ids: [String]) throws -> [Cartridge] {
        try ids.map { try XCTUnwrap(CartridgeCatalog.cartridge(id: $0)) }
    }

    func testBandIsAsTallAsTheRuler() throws {
        let layout = TrueScaleLayout(cartridges: try cartridges(["9x19 mm", "7.5x55 mm Swiss (GP 11)"]), unit: .metric, pointsPerMM: 6)
        // GP 11 is 77.5 mm: plus 5 mm, rounded up to whole centimetres.
        XCTAssertEqual(layout.rulerMM, 90)
        XCTAssertEqual(layout.bandHeight, 540, accuracy: 1e-9)
    }

    func testImperialRulerRoundsToWholeInches() throws {
        let layout = TrueScaleLayout(cartridges: try cartridges(["9x19 mm"]), unit: .imperial, pointsPerMM: 6)
        XCTAssertEqual(layout.rulerMM, 2 * 25.4, accuracy: 1e-9)
        XCTAssertEqual(layout.bandHeight, 2 * 25.4 * 6, accuracy: 1e-9)
    }

    func testEveryCartridgeFitsInTheBand() throws {
        for unit in LengthUnit.allCases {
            for c in CartridgeCatalog.all {
                let layout = TrueScaleLayout(cartridges: [c], unit: unit, pointsPerMM: 6.3)
                XCTAssertGreaterThanOrEqual(layout.rulerMM, c.outline.height + 5, "\(c.id) \(unit)")
                XCTAssertGreaterThanOrEqual(layout.bandHeight, c.outline.height * 6.3, "\(c.id) \(unit)")
            }
        }
    }

    func testTallestCartridgeSetsTheBand() throws {
        let small = TrueScaleLayout(cartridges: try cartridges(["9x19 mm"]), unit: .metric, pointsPerMM: 6)
        let both = TrueScaleLayout(cartridges: try cartridges(["9x19 mm", ".50 BMG"]), unit: .metric, pointsPerMM: 6)
        XCTAssertGreaterThan(both.bandHeight, small.bandHeight)
        XCTAssertEqual(TrueScaleLayout(cartridges: [], unit: .metric, pointsPerMM: 6).rulerMM, 10)
    }

    func testRulerIsPinnedToTheLeftEdgeAndTheBaseLine() throws {
        XCTAssertEqual(TrueScaleLayout.rulerLeadingInset, 0)
        let layout = TrueScaleLayout(cartridges: try cartridges(["9x19 mm"]), unit: .metric, pointsPerMM: 6)
        // The ruler is as tall as the band, so its zero is where the cartridge bases stand.
        XCTAssertEqual(RulerView.y(forMM: 0, height: layout.bandHeight, pointsPerMM: 6), layout.bandHeight)
        // The top of a 29.69 mm cartridge lines up with the 29.69 mm mark.
        let tip = layout.bandHeight - 29.69 * 6
        XCTAssertEqual(RulerView.y(forMM: 29.69, height: layout.bandHeight, pointsPerMM: 6), tip, accuracy: 1e-9)
    }

    func testRulerNumbersHaveRoomAtBothEnds() {
        // The 9 pt numbers are centred on the top and zero ticks: half their height sticks out.
        XCTAssertGreaterThanOrEqual(RulerView.labelOverhang, 6)
    }

    func testSingleCartridgeIsCentredWithTheRulerBesideIt() {
        let ppmm = 6.3
        let gap = TrueScaleLayout.singleGapMM * ppmm
        let offset = TrueScaleLayout.singleOffset(pointsPerMM: ppmm)
        // Group = ruler, gap, cartridge (width w), centred at 0, then shifted by the offset.
        for w in [10.0 * ppmm, 20.0 * ppmm] {
            let group = TrueScaleLayout.rulerWidth + gap + w
            let cartridgeCentre = -group / 2 + TrueScaleLayout.rulerWidth + gap + w / 2 + offset
            XCTAssertEqual(cartridgeCentre, 0, accuracy: 1e-9)
        }
        // The ruler is the same distance from the cartridge whatever its width.
        XCTAssertGreaterThan(gap, 0)
    }

    func testOneToOneHintsAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertEqual(en["Originalgrösse"], "Real size")
        XCTAssertNotNil(en["1:1 – Zoomen ist abgeschaltet, damit die Grösse stimmt."])
        XCTAssertEqual(en["Hülse %@"], "Case %@")
        XCTAssertEqual(en["Geschosse beim Vergleich mit leeren Hülsen zeigen"], "Show bullets when comparing empty cases")
    }

    func testEmptyCasesShowTheirCaseLength() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".308 Winchester"))
        XCTAssertEqual(TrueScaleView.caseLengthText(c, unit: .metric), String(format: "Hülse %@".loc, LengthUnit.metric.format(51.2)))
        XCTAssertEqual(TrueScaleView.caseLengthText(c, unit: .imperial), String(format: "Hülse %@".loc, LengthUnit.imperial.format(51.2)))
        // «L» is the length of what is drawn: the whole cartridge, or the case alone without its bullet.
        XCTAssertEqual(TrueScaleView.lengthText(c, caseOnly: false, unit: .metric), "L " + LengthUnit.metric.format(71.1))
        XCTAssertEqual(TrueScaleView.lengthText(c, caseOnly: true, unit: .metric), "L " + LengthUnit.metric.format(51.2))
    }

    /// With «Geschosse beim Vergleich mit leeren Hülsen zeigen» off, the case is drawn alone: where the bullet stood stays empty.
    @MainActor
    func testCaseOnlyLeavesOutTheBullet() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".308 Winchester"))
        let ppmm = 4.0, d = c.dimensions
        // On the axis, half way along the bullet in front of the case mouth, and half way up the case.
        let x = Int(c.outline.width * ppmm / 2)
        let bulletY = Int((d.overallLength - d.caseLength) / 2 * ppmm)
        let caseY = Int((d.overallLength - d.caseLength / 2) * ppmm)
        func alpha(caseOnly: Bool, y: Int) throws -> UInt8 {
            let renderer = ImageRenderer(content: CartridgeView(cartridge: c, pointsPerMM: ppmm, caseOnly: caseOnly))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                // Moves pixel (x, y), counted from the top, onto the context's only pixel.
                context?.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
            }
            return pixel[3]
        }
        XCTAssertEqual(try alpha(caseOnly: false, y: bulletY), 255)
        XCTAssertEqual(try alpha(caseOnly: true, y: bulletY), 0)
        XCTAssertEqual(try alpha(caseOnly: true, y: caseY), 255)
    }
}
