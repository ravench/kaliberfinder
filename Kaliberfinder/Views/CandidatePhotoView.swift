import SwiftUI

/// The photo with the frames of what was found: a numbered yellow box around each cartridge the
/// user can pick (tapping one picks it), and a green line along the measured silhouette: around the
/// case, its neck and shoulder, and the bullet if there is one. With the hidden developer switch
/// each edge has the colour of the detection it comes from.
struct CandidatePhotoView: View {
    let photo: UIImage
    /// Cartridges to pick from, as boxes in fractions of the whole photo; empty when there's no choice.
    var candidates: [CGRect] = []
    /// The measured silhouette's outline (or its rotated box's corners), as fractions of the whole photo.
    var measured: [CGPoint]?
    /// What found each edge of `measured` (see `ShapeContour.parts`); empty for a box.
    var parts: [ShapeContour.Part] = []
    /// The part of the photo `photo` shows, as fractions of the whole photo (all of it by default).
    var region = CGRect(x: 0, y: 0, width: 1, height: 1)
    var maxHeight: CGFloat = 220
    var onSelect: ((Int) -> Void)?
    @AppStorage(ShapeContour.partColoursKey) private var partColours = false

    var body: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    if let measured {
                        let corners = measured.map { Self.point($0, in: region, size: geo.size) }
                        if partColours && parts.count == corners.count {
                            ForEach(Self.coloured, id: \.part) { item in
                                Self.path(edges: parts.indices.filter { parts[$0] == item.part }, of: corners)
                                    .stroke(item.colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            }
                            .accessibilityHidden(true)
                        } else {
                            Self.path(through: corners)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                                .accessibilityHidden(true)
                        }
                    }
                    ForEach(candidates.indices, id: \.self) { i in
                        candidate(i, in: geo.size)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func candidate(_ i: Int, in size: CGSize) -> some View {
        let rect = Self.frame(of: Self.relative(candidates[i], to: region), in: size)
        return RoundedRectangle(cornerRadius: 6)
            .stroke(Color.yellow, lineWidth: 3)
            .background(Color.white.opacity(0.001))
            .overlay(alignment: .topLeading) {
                Text(verbatim: "\(i + 1)")
                    .font(.caption.bold())
                    .padding(4)
                    .background(.yellow, in: Circle())
                    .foregroundStyle(.black)
                    .offset(x: -8, y: -8)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture { onSelect?(i) }
            .accessibilityElement()
            .accessibilityLabel(String(format: "Patrone %lld".loc, i + 1))
            .accessibilityAddTraits(.isButton)
    }

    /// The colour of each part with the developer switch on: green for the ends as for the whole
    /// outline, the others as the neck and taper lines were drawn before (#62).
    static let coloured: [(part: ShapeContour.Part, colour: Color)] = [(.end, .green), (.bullet, .purple), (.neck, .orange), (.body, .cyan)]

    /// The edges `edges` of the closed outline through `corners`: edge `i` from corner `i` to the next.
    static func path(edges: [Int], of corners: [CGPoint]) -> Path {
        var path = Path()
        for i in edges where corners.count > 1 {
            path.move(to: corners[i])
            path.addLine(to: corners[(i + 1) % corners.count])
        }
        return path
    }

    /// A closed path through the points.
    static func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    /// A point in fractions of the whole photo, in a view of `size` that shows `region` of it.
    static func point(_ p: CGPoint, in region: CGRect, size: CGSize) -> CGPoint {
        guard region.width > 0, region.height > 0 else { return p }
        return CGPoint(x: (p.x - region.minX) / region.width * size.width,
                       y: (p.y - region.minY) / region.height * size.height)
    }

    /// A box given as fractions of the whole photo, as fractions of `region` instead.
    static func relative(_ box: CGRect, to region: CGRect) -> CGRect {
        guard region.width > 0, region.height > 0 else { return box }
        return CGRect(x: (box.minX - region.minX) / region.width, y: (box.minY - region.minY) / region.height,
                      width: box.width / region.width, height: box.height / region.height)
    }

    /// A candidate's outline in a view of `size`, a little wider than the box so it doesn't touch the cartridge.
    static func frame(of candidate: CGRect, in size: CGSize) -> CGRect {
        let rect = CGRect(x: candidate.minX * size.width, y: candidate.minY * size.height,
                          width: candidate.width * size.width, height: candidate.height * size.height)
        return rect.insetBy(dx: -6, dy: -6)
    }
}
