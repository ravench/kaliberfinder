import SwiftUI
import XCTest
@testable import Kaliberfinder

/// The lists keep to a readable column on an iPad and fill a phone's screen (Raven, 2026-11-08).
@MainActor
final class ReadableWidthTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    func testHomeListKeepsToAColumnOnAnIPadInLandscape() throws {
        // iPad Pro 11" in landscape.
        let list = try homeList(size: CGSize(width: 1210, height: 834))
        let frame = try XCTUnwrap(window).convert(list.bounds, from: list)
        XCTAssertLessThanOrEqual(frame.width, ReadableWidth.max)
        XCTAssertGreaterThan(frame.width, 600)
        // Centred.
        XCTAssertEqual(frame.midX, 605, accuracy: 1)
    }

    func testHomeListFillsAPhone() throws {
        // iPhone 13 mini, the smallest phone tested against.
        let list = try homeList(size: CGSize(width: 375, height: 812))
        XCTAssertEqual(try XCTUnwrap(window).convert(list.bounds, from: list).width, 375)
    }

    func testColumnIsReadable() {
        // Two to three times a phone, as Apple's readable content width.
        XCTAssertGreaterThanOrEqual(ReadableWidth.max, 600)
        XCTAssertLessThanOrEqual(ReadableWidth.max, 800)
    }

    /// Lays out the home screen in a window of `size` and returns its list.
    private func homeList(size: CGSize) throws -> UIScrollView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let home = NavigationStack { HomeView(canTakePhoto: true) }
            .environmentObject(ScaleModel())
            .environment(\.locale, Locale(identifier: "de_CH"))
        window.rootViewController = UIHostingController(rootView: home)
        window.makeKeyAndVisible()
        self.window = window
        var list: UIScrollView?
        for _ in 0..<50 where list == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            list = scrollViews(in: window).first { $0.contentSize.height > 0 }
        }
        window.layoutIfNeeded()
        return try XCTUnwrap(list, "No list on the home screen")
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}
