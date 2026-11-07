import SwiftUI

/// The floating "compare 1:1" button at the bottom of the results, measure and catalogue screens:
/// a large capsule as wide as its text, not edge to edge, so it reads as a button and covers less of the list.
struct CompareButton: View {
    let title: String
    let cartridges: [Cartridge]
    /// Calibres compared as empty cases (`TrueScaleView.emptyCases`).
    var emptyCases: Set<String> = []

    /// Two items side by side.
    static let symbol = "square.and.line.vertical.and.square"
    /// Comfortably above the 44 pt minimum touch target.
    static let height: CGFloat = 54
    /// Space to the screen edges and the bottom, so the capsule floats clear of them.
    static let margin: CGFloat = 24

    var body: some View {
        NavigationLink { TrueScaleView(cartridges: cartridges, emptyCases: emptyCases) } label: {
            Label(title, systemImage: Self.symbol)
                .font(.headline)
                .lineLimit(1)
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
