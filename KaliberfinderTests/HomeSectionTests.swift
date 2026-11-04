import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionComesBeforeRealSizeAndUnits() {
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition, .realSize, .units])
    }
}
