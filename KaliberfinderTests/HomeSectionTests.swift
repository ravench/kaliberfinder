import XCTest
@testable import Kaliberfinder

final class HomeSectionTests: XCTestCase {
    func testRecognitionIsTheLastHomeSection() {
        // Settings open from the gear button in the navigation bar, not from a row.
        XCTAssertEqual(HomeSection.allCases, [.photo, .withoutPhoto, .recognition])
    }

    func testSettingsPageHoldsUnitsRealSizeAndCopyright() {
        XCTAssertEqual(SettingsSection.allCases, [.units, .compare, .results, .photo, .info, .developer])  // the developer options last (Raven, 2026-11-14)
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
        // Matches opened: the screen is free again, with nothing to report.
        loading.finish(loaded: true)
        XCTAssertFalse(loading.isLoading)
        XCTAssertFalse(loading.failed)
        XCTAssertTrue(loading.start())
    }

    /// A photo that could not be loaded (iCloud without reception) is said, not passed over (review 2026-11-18);
    /// the next pick clears it.
    func testAFailedLoadIsReported() {
        var loading = PhotoLoading()
        XCTAssertTrue(loading.start())
        loading.finish(loaded: false)
        XCTAssertFalse(loading.isLoading)
        XCTAssertTrue(loading.failed)
        XCTAssertTrue(loading.start())
        XCTAssertFalse(loading.failed)
    }
}
