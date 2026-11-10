import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionIsTheLastHomeSection() {
        // Settings open from the gear button in the navigation bar, not from a row.
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition])
    }

    func testSettingsPageHoldsUnitsRealSizeAndCopyright() {
        XCTAssertEqual(SettingsSection.allCases, [.units, .realSize, .compare, .photo, .info])
    }

    func testSettingsShowVersionAndBuild() {
        let text = Bundle.main.versionText
        XCTAssertNotNil(text.range(of: #"^\d+(\.\d+)+ \(\d+\)$"#, options: .regularExpression), text)
    }

    func testOnlyOneLibraryPhotoLoadsAtATime() {
        var loading = PhotoLoading()
        XCTAssertFalse(loading.isLoading)
        XCTAssertTrue(loading.start())
        XCTAssertTrue(loading.isLoading)
        // A second pick while the first photo loads must not start another load.
        XCTAssertFalse(loading.start())
        XCTAssertTrue(loading.isLoading)
        // Matches opened or load failed: the screen is free again.
        loading.finish()
        XCTAssertFalse(loading.isLoading)
        XCTAssertTrue(loading.start())
    }
}
