import UIKit

/// The bottom of the case from the side as an outline, one per «Randform» choice (`RoundFacts.head`;
/// Raven, TestFlight 1174): a stretch of body open at the top, the extractor groove or the belt where
/// the type has one, the rim below. Rendered as template images, since a picker's menu takes images only.
enum HeadIcon {
    /// Half-widths of the case down its axis on a 16 × 16 grid, top to bottom; two entries with
    /// the same y make a step. Mirrored about the centre line when drawn.
    static func profile(_ token: String) -> [(y: CGFloat, halfWidth: CGFloat)]? {
        switch token {
        case "rimless": [(0, 5), (8, 5), (8, 3.6), (11, 3.6), (11, 5), (15, 5)]
        case "semi": [(0, 5), (8, 5), (8, 3.6), (11, 3.6), (11, 6.2), (15, 6.2)]
        case "rimmed": [(0, 5), (11, 5), (11, 7.3), (15, 7.3)]
        case "rebated": [(0, 5), (8, 5), (8, 3), (11, 3), (11, 4), (15, 4)]
        case "belted": [(0, 5), (2.5, 5), (2.5, 6.6), (6, 6.6), (6, 3.6), (11, 3.6), (11, 5), (15, 5)]
        default: nil
        }
    }

    static let size: CGFloat = 22

    private static let images: [String: UIImage] = Dictionary(uniqueKeysWithValues: RoundFacts.head.compactMap { option in
        render(option.token).map { (option.token, $0) }
    })

    /// The outline for a head token in the current tint, nil for a token without one.
    static func image(_ token: String) -> UIImage? { images[token] }

    private static func render(_ token: String) -> UIImage? {
        guard let profile = profile(token) else { return nil }
        let s = size / 16
        // Down the left side, across the rim's bottom, up the right side: the top stays open.
        let path = UIBezierPath()
        path.move(to: CGPoint(x: (8 - profile[0].halfWidth) * s, y: 0))
        for p in profile.dropFirst() { path.addLine(to: CGPoint(x: (8 - p.halfWidth) * s, y: p.y * s)) }
        for p in profile.reversed() { path.addLine(to: CGPoint(x: (8 + p.halfWidth) * s, y: p.y * s)) }
        path.lineWidth = 1.3 * s
        path.lineJoinStyle = .round
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            UIColor.black.setStroke()
            path.stroke()
        }
        .withRenderingMode(.alwaysTemplate)
    }
}
