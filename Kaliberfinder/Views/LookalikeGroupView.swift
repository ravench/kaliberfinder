import SwiftUI

/// The calibres of a lookalike group (`LookalikeGroup`): each opens its page, and all of them compare
/// at 1:1, calibres that look exactly the same from the side once (Raven, 2026-11-08).
struct LookalikeGroupView: View {
    let group: LookalikeGroup

    var body: some View {
        let members = group.members
        List {
            Section {
                ForEach(members) { c in
                    NavigationLink { CartridgeDetailView(cartridge: c) } label: { CartridgeRow(cartridge: c) }
                }
            } footer: {
                Text(String(format: "Unterscheiden sich in: %@".loc, group.differs.map { LookalikeGroup.title($0).loc }.joined(separator: ", ")))
            }
        }
        .readableWidth()
        .navigationTitle(String(format: "Gruppe %@".loc, group.calibres[0]))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            let compared = Self.compared(members)
            CompareButton(title: String(format: "1:1 vergleichen (%lld)".loc, compared.count), cartridges: compared)
        }
    }

    /// Identical-looking calibres once, standing by the length setting; the 1:1 screen names the others under the drawing.
    static func compared(_ members: [Cartridge], by: CompareLength = .current) -> [Cartridge] {
        CartridgeCatalog.groupedByProfile(members, cartridge: { $0 }).map { $0[0] }.byLength(by)
    }
}
