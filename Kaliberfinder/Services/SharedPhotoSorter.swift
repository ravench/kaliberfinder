import Foundation

/// Tells apart the photos shared together: which one shows the cartridge from the side
/// (shape and size) and which one the case head (headstamp). The order they were shared in
/// does not count.
enum SharedPhotoSorter {
    enum View: Equatable {
        /// A long silhouette: the cartridge lying on its side.
        case side
        /// A round silhouette: the base (or tip) seen end on.
        case end
        /// No silhouette found, e.g. a close-up of the headstamp filling the frame.
        case unknown

        init(_ shape: ShapeMeasurement?) {
            guard let shape else { self = .unknown; return }
            self = shape.isEndView ? .end : .side
        }
    }

    /// Indexes of the side photo and of the base photo (nil if none of the others can be one).
    /// Prefers a side view as the side photo and a round view as the base photo; a second
    /// side view is not used as the base photo.
    static func assign(_ views: [View]) -> (side: Int, base: Int?)? {
        guard !views.isEmpty else { return nil }
        let side = views.firstIndex(of: .side) ?? views.firstIndex(of: .unknown) ?? 0
        let others = views.indices.filter { $0 != side }
        let base = others.first { views[$0] == .end } ?? others.first { views[$0] == .unknown }
            ?? (views[side] == .side ? nil : others.first)
        return (side, base)
    }
}
