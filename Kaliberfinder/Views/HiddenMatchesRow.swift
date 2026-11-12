import SwiftUI

/// The last row of the results when a switch hides matching calibres, e.g.
/// «3 weitere Treffer: 3 veraltete · Einblenden». Tapping shows them in place, just for this result.
struct HiddenMatchesRow: View {
    let summary: String
    @Binding var revealed: Bool

    var body: some View {
        Button {
            withAnimation { revealed.toggle() }
        } label: {
            HStack {
                // In the button's own tint, like «Einblenden» (TestFlight 1175: not the tinted grey).
                Label { Text(verbatim: summary) } icon: { Image(systemName: revealed ? "eye" : "eye.slash") }
                    .font(.subheadline)
                Spacer()
                if revealed { Text("Ausblenden") } else { Text("Einblenden").fontWeight(.semibold) }
            }
        }
    }
}
