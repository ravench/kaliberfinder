import SwiftUI

/// The floating "compare 1:1" button at the bottom of the results, measure and catalogue screens:
/// a large capsule as wide as its text, not edge to edge, so it reads as a button and covers less of the list.
struct CompareButton: View {
    let title: String
    let cartridges: [Cartridge]
    /// Calibres compared as empty cases (`TrueScaleView.emptyCases`).
    var emptyCases: Set<String> = []
    /// Matches that fit well, with the reason (`TrueScaleView.goodMatches`).
    var goodMatches: [String: String] = [:]
    @Environment(\.dynamicTypeSize) private var textSize

    /// Two items side by side.
    static let symbol = "square.and.line.vertical.and.square"
    /// Comfortably above the 44 pt minimum touch target.
    static let height: CGFloat = 54
    /// Space to the screen edges and the bottom, so the capsule floats clear of them.
    static let margin: CGFloat = 24

    /// One line, shrunk a little when it is long; at the accessibility text sizes it wraps instead of being cut short.
    static func titleLines(_ textSize: DynamicTypeSize) -> Int { textSize.isAccessibilitySize ? 3 : 1 }

    var body: some View {
        NavigationLink { TrueScaleView(cartridges: cartridges, emptyCases: emptyCases, goodMatches: goodMatches) } label: {
            Label(title, systemImage: Self.symbol)
                .font(.headline)
                .lineLimit(Self.titleLines(textSize))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minHeight: Self.height)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .padding(.horizontal, Self.margin)
        .padding(.bottom, 8)
    }
}
