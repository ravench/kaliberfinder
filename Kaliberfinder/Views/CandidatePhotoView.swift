import SwiftUI

/// The photo with an outline around each cartridge that could be meant; tapping one picks it.
struct CandidatePhotoView: View {
    let photo: UIImage
    /// Boxes as fractions of the photo.
    let candidates: [CGRect]
    /// The candidate being measured, drawn highlighted; nil while the user still has to choose.
    var selected: Int?
    var maxHeight: CGFloat = 220
    var onSelect: ((Int) -> Void)?

    var body: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    ForEach(candidates.indices, id: \.self) { i in
                        outline(i, in: geo.size)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func outline(_ i: Int, in size: CGSize) -> some View {
        let rect = Self.frame(of: candidates[i], in: size)
        let isSelected = selected == i
        if selected == nil || isSelected {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.green : Color.yellow, lineWidth: 3)
                .background(Color.white.opacity(0.001))
                .overlay(alignment: .topLeading) {
                    if selected == nil {
                        Text(verbatim: "\(i + 1)")
                            .font(.caption.bold())
                            .padding(4)
                            .background(.yellow, in: Circle())
                            .foregroundStyle(.black)
                            .offset(x: -8, y: -8)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .onTapGesture { onSelect?(i) }
                .accessibilityElement()
                .accessibilityLabel(String(format: "Patrone %lld".loc, i + 1))
                .accessibilityAddTraits(.isButton)
        }
    }

    /// A candidate's outline in a view of `size`, a little wider than the box so it doesn't touch the cartridge.
    static func frame(of candidate: CGRect, in size: CGSize) -> CGRect {
        let rect = CGRect(x: candidate.minX * size.width, y: candidate.minY * size.height,
                          width: candidate.width * size.width, height: candidate.height * size.height)
        return rect.insetBy(dx: -6, dy: -6)
    }
}
