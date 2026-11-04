import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionAndUnitsComeBeforeRealSize() {
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition, .units, .realSize])
    }
}
