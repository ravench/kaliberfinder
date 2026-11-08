import XCTest
@testable import Kaliberfinder

/// The app and its share extension run on iPhone and iPad (Raven, 2026-11-08). Phones stay in
/// portrait; an iPad turns as it likes. Read from the built Info.plists, which project.yml generates.
final class DeviceFamilyTests: XCTestCase {
    private static let allOrientations: Set<String> = [
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
    ]

    /// The app's Info.plist as written: `infoDictionary` would resolve the `~ipad` keys on an iPad.
    private func info() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Info", withExtension: "plist"))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
    }

    func testAppRunsOnIPhoneAndIPad() throws {
        XCTAssertEqual(Set(try info()["UIDeviceFamily"] as? [Int] ?? []), [1, 2])
    }

    func testShareExtensionRunsOnIPhoneAndIPad() throws {
        let url = try XCTUnwrap(Bundle.main.builtInPlugInsURL).appendingPathComponent("KaliberfinderShare.appex")
        let share = try XCTUnwrap(Bundle(url: url), "share extension missing from the app")
        XCTAssertEqual(Set(share.infoDictionary?["UIDeviceFamily"] as? [Int] ?? []), [1, 2])
    }

    func testPhonesStayInPortrait() throws {
        XCTAssertEqual(try info()["UISupportedInterfaceOrientations"] as? [String], ["UIInterfaceOrientationPortrait"])
    }

    func testIPadTurnsFreely() throws {
        XCTAssertEqual(Set(try info()["UISupportedInterfaceOrientations~ipad"] as? [String] ?? []), Self.allOrientations)
    }
}
