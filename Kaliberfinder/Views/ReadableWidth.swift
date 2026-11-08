import SwiftUI

/// On an iPad a list across the whole screen reads badly: lines of a footer run 200 characters,
/// and a switch sits half a metre from its label. The app's lists keep to a column of this width,
/// centred, on the grouped background; phones are narrower and unaffected.
enum ReadableWidth {
    static let max: CGFloat = 700
}

extension View {
    /// Keeps the view in a readable column (`ReadableWidth.max`), centred on the grouped background.
    func readableWidth() -> some View {
        frame(maxWidth: ReadableWidth.max)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    /// A sheet the height of a page on an iPad, where a form sheet is too low for the calibration
    /// card (iOS 18); on a phone a sheet is as tall as the screen anyway.
    @ViewBuilder func pageSized() -> some View {
        if #available(iOS 18, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
