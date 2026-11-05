import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionStaysOnHomeAndSettingsRowComesLast() {
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition, .settings])
    }

    func testSettingsPageHoldsUnitsRealSizeAndCopyright() {
        XCTAssertEqual(SettingsSection.allCases, [.units, .realSize, .copyright])
    }
}
