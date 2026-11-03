@testable import Kaliberfinder
import XCTest

final class SharedInboxTests: XCTestCase {
    private var root: URL!
    private var inbox: SharedInbox!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        inbox = SharedInbox(directory: root.appendingPathComponent("Inbox", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEmptyInboxGivesNothing() {
        XCTAssertEqual(inbox.take(), [])
    }

    func testPhotosComeBackInSharedOrderOnce() throws {
        let side = Data("side".utf8), base = Data("base".utf8)
        try inbox.put([side, base])
        XCTAssertEqual(inbox.take(), [side, base])
        XCTAssertEqual(inbox.take(), [], "taking empties the inbox")
    }

    func testKeepsAtMostTwoPhotos() throws {
        try inbox.put((0..<5).map { Data("photo \($0)".utf8) })
        XCTAssertEqual(SharedInbox.maxPhotos, 2)
        XCTAssertEqual(inbox.take(), [Data("photo 0".utf8), Data("photo 1".utf8)])
    }

    func testNewShareReplacesWaitingPhotos() throws {
        try inbox.put([Data("old side".utf8), Data("old base".utf8)])
        try inbox.put([Data("new side".utf8)])
        XCTAssertEqual(inbox.take(), [Data("new side".utf8)])
    }

    func testOrderHoldsBeyondNinePhotosOnDisk() throws {
        // Numeric, not alphabetical order ("10" after "2"), should the limit ever grow.
        let dir = inbox.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in [10, 2, 0] { try Data("\(index)".utf8).write(to: dir.appendingPathComponent(String(index))) }
        try Data("junk".utf8).write(to: dir.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(inbox.take(), ["0", "2", "10"].map { Data($0.utf8) })
    }

    func testOpenURL() throws {
        XCTAssertTrue(SharedInbox.isOpenURL(SharedInbox.openURL))
        XCTAssertTrue(SharedInbox.isOpenURL(try XCTUnwrap(URL(string: "kaliberfinder://shared?x=1"))))
        XCTAssertFalse(SharedInbox.isOpenURL(try XCTUnwrap(URL(string: "kaliberfinder://other"))))
        XCTAssertFalse(SharedInbox.isOpenURL(try XCTUnwrap(URL(string: "https://shared"))))
    }

    func testAppGroupUsesBundlePrefix() {
        XCTAssertEqual(SharedInbox.appGroup, "group.ch.giotta.kaliberfinder")
    }

    func testShareSheetTextsAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let english = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertEqual(english["Foto übernommen. Öffne Kaliberfinder, um die Treffer zu sehen."], "Photo received. Open Kaliberfinder to see the matches.")
        XCTAssertNotNil(english["Das Foto konnte nicht übernommen werden."])
        XCTAssertNotNil(english["Fertig"])
    }
}
