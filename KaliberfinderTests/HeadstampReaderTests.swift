import XCTest
@testable import Kaliberfinder

final class HeadstampReaderTests: XCTestCase {
    private func first(_ lines: [String]) -> HeadstampReader.Hit? {
        HeadstampReader.hits(in: lines).first
    }

    func testReadsCommonHeadstamps() {
        let cases: [(String, String)] = [
            ("WIN 308", ".308 Winchester"),
            ("FC 223 REM", ".223 Remington"),
            ("GECO 9mm Luger", "9x19 mm"),
            ("9MM LUGER", "9x19 mm"),
            ("R-P 45 AUTO", ".45 ACP"),
            ("S&B 7.62x39", "7.62x39 mm"),
            ("38 SPL", ".38 Special"),
            ("RWS .22 l.r.", ".22 LR"),
            ("GP 11", "7.5x55 mm Swiss (GP 11)"),
        ]
        for (text, id) in cases {
            XCTAssertEqual(first([text])?.cartridgeID, id, text)
            XCTAssertEqual(first([text])?.strength, .strong, text)
        }
    }

    func testShortNumbersAreWeak() {
        let hits = HeadstampReader.hits(in: ["45"])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.strength == .weak })
        XCTAssertEqual(HeadstampReader.strength(of: "308"), .weak)
        XCTAssertEqual(HeadstampReader.strength(of: "308win"), .strong)
    }

    func testStrongBeatsWeakForTheSameCalibre() throws {
        let hit = try XCTUnwrap(HeadstampReader.hits(in: ["308", "WIN 308"]).first { $0.cartridgeID == ".308 Winchester" })
        XCTAssertEqual(hit.strength, .strong)
        XCTAssertEqual(hit.text, "WIN 308")
    }

    func testStrongHitsComeFirst() {
        let hits = HeadstampReader.hits(in: ["R-P 45 AUTO"])
        XCTAssertEqual(hits.first?.cartridgeID, ".45 ACP")
        XCTAssertTrue(hits.dropFirst().allSatisfy { $0.strength == .weak })
    }

    func testIgnoresUnrelatedText() {
        XCTAssertTrue(HeadstampReader.hits(in: ["T 15", "2019", "Hello world", ""]).isEmpty)
    }

    func testIndexHasNoDuplicateIDs() {
        for (key, ids) in HeadstampReader.index {
            XCTAssertEqual(Set(ids).count, ids.count, key)
        }
    }
}
