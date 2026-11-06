import SwiftUI
import XCTest
@testable import Kaliberfinder

/// The home screen scrolls only when it does not fit: on a screen that fits, a drag would only
/// stretch and shrink the large title.
@MainActor
final class HomeScrollTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    func testHomeFitsAnIPhone17ProAndDoesNotScroll() throws {
        let list = try homeList()
        // Raven's phone and the simulator CI tests on.
        let screen = try XCTUnwrap(window).bounds.size
        try XCTSkipIf(screen.height < 874, "Needs an iPhone 17 Pro or larger, this is \(screen)")
        XCTAssertLessThanOrEqual(list.contentSize.height, room(in: list), "The home screen no longer fits: it scrolls again")
        XCTAssertFalse(canDrag(list))
    }

    func testHomeStillScrollsWithLargeText() throws {
        let list = try homeList(textSize: .accessibility3)
        XCTAssertGreaterThan(list.contentSize.height, room(in: list))
        XCTAssertTrue(canDrag(list))
    }

    /// Lays out the home screen in German, as on a phone with a camera, and returns its list.
    private func homeList(textSize: DynamicTypeSize = .large) throws -> UIScrollView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let home = NavigationStack { HomeView(canTakePhoto: true) }
            .environmentObject(ScaleModel())
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.locale, Locale(identifier: "de_CH"))
        window.rootViewController = UIHostingController(rootView: home)
        window.makeKeyAndVisible()
        self.window = window
        // SwiftUI builds the list and sizes its rows over the next run loop passes.
        var list: UIScrollView?
        for _ in 0..<50 where list == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            list = scrollViews(in: window).first { $0.contentSize.height > 0 }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        window.layoutIfNeeded()
        return try XCTUnwrap(list, "No list on the home screen")
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }

    /// The height between the navigation bar, with its large title, and the bottom edge.
    private func room(in list: UIScrollView) -> CGFloat {
        list.bounds.height - list.adjustedContentInset.top - list.adjustedContentInset.bottom
    }

    private func canDrag(_ list: UIScrollView) -> Bool {
        list.isScrollEnabled && (list.contentSize.height > room(in: list) || (list.alwaysBounceVertical && list.bounces))
    }
}
