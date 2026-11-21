import XCTest

/// The test bundle's principal class (`NSPrincipalClass` in project.yml), made before the first test:
/// it clears the app's saved settings, so every run starts from the shipped defaults. CI erases the
/// simulator anyway; a simulator that was used keeps whatever was switched in the app (local builds).
@objc(KaliberfinderTestRun)
final class TestRun: NSObject {
    private(set) static var clearedSettings = false

    override init() {
        super.init()
        if let app = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: app) }
        Self.clearedSettings = true
    }
}

final class TestRunTests: XCTestCase {
    func testTheRunStartsFromTheShippedSettings() {
        XCTAssertTrue(TestRun.clearedSettings, "NSPrincipalClass of KaliberfinderTests is not KaliberfinderTestRun")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "ch.giotta.kaliberfinder", "the settings cleared are the app's")
    }
}
