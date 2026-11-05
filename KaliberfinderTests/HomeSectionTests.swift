import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionStaysOnHomeAndSettingsRowComesLast() {
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition, .settings])
    }

    func testSettingsPageHoldsUnitsRealSizeAndCopyright() {
        XCTAssertEqual(SettingsSection.allCases, [.units, .realSize, .copyright])
    }

    func testSettingsSummaryShowsUnitAndScreenSource() {
        XCTAssertEqual(SettingsView.summary(unit: .metric, source: .model),
                       LengthUnit.metric.title.loc + " · " + ScreenScale.Source.model.title.loc)
        XCTAssertTrue(SettingsView.summary(unit: .imperial, source: .calibrated).contains(LengthUnit.imperial.title.loc))
    }
}
