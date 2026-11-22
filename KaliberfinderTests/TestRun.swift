import XCTest

/// The test bundle's principal class (`NSPrincipalClass` in project.yml), made before the first test:
/// on the simulator it clears the app's saved settings, so every run starts from the shipped defaults.
/// CI erases the simulator anyway; a simulator that was used keeps whatever was switched in the app
/// (local builds). Never on a phone or a Mac: the tests share the installed app's data there.
@objc(KaliberfinderTestRun)
final class TestRun: NSObject {
    private(set) static var clearedSettings = false

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        if let app = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: app) }
        Self.clearedSettings = true
        #endif
    }
}

final class TestRunTests: XCTestCase {
    func testTheRunStartsFromTheShippedSettings() throws {
        #if targetEnvironment(simulator)
        XCTAssertTrue(TestRun.clearedSettings, "NSPrincipalClass of KaliberfinderTests is not KaliberfinderTestRun")
        #else
        throw XCTSkip("Settings are cleared on the simulator only")
        #endif
    }
}
