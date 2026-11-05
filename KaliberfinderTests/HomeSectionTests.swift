import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionIsTheLastHomeSection() {
        // Settings open from the gear button in the navigation bar, not from a row.
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition])
    }

    func testSettingsPageHoldsUnitsRealSizeAndCopyright() {
        XCTAssertEqual(SettingsSection.allCases, [.units, .realSize, .copyright])
    }
}
