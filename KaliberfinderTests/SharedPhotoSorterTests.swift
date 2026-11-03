@testable import Kaliberfinder
import XCTest

/// Shared photos are told apart by their outline, not by the order they were shared in.
final class SharedPhotoSorterTests: XCTestCase {
    private func assign(_ views: [SharedPhotoSorter.View]) -> [Int?]? {
        SharedPhotoSorter.assign(views).map { [$0.side, $0.base] }
    }

    func testNoPhotos() {
        XCTAssertNil(assign([]))
    }

    func testSinglePhotoIsTheSidePhoto() {
        XCTAssertEqual(assign([.side]), [0, nil])
        XCTAssertEqual(assign([.end]), [0, nil])
        XCTAssertEqual(assign([.unknown]), [0, nil])
    }

    func testOrderDoesNotMatter() {
        XCTAssertEqual(assign([.side, .end]), [0, 1])
        XCTAssertEqual(assign([.end, .side]), [1, 0])
    }

    func testHeadstampCloseUpWithoutOutlineIsTheBase() {
        XCTAssertEqual(assign([.unknown, .side]), [1, 0])
        XCTAssertEqual(assign([.side, .unknown]), [0, 1])
    }

    func testRoundViewIsPreferredAsBase() {
        XCTAssertEqual(assign([.unknown, .end]), [0, 1])
        XCTAssertEqual(assign([.end, .unknown]), [1, 0])
    }

    func testTwoSideViewsGiveNoBasePhoto() {
        XCTAssertEqual(assign([.side, .side]), [0, nil])
    }

    func testTwoRoundViewsAreBothRead() {
        // A round first photo counts for its headstamp too (PhotoKind.readsText).
        XCTAssertEqual(assign([.end, .end]), [0, 1])
    }

    func testViewFromOutline() {
        let profile = ShapeMatcher.fractions.map { _ in 1.0 }
        XCTAssertEqual(SharedPhotoSorter.View(ShapeMeasurement(aspect: 3.5, profile: profile)), .side)
        XCTAssertEqual(SharedPhotoSorter.View(ShapeMeasurement(aspect: 1, profile: profile)), .end)
        XCTAssertEqual(SharedPhotoSorter.View(nil), .unknown)
    }
}
