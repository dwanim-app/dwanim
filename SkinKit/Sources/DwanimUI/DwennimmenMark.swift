import SwiftUI

// MARK: - DwennimmenMark

/// The Dwennimmen ("ram's horns") mark, our app's original heritage emblem,
/// rendered purely as **imagery** — never as the word. It is two mirrored
/// ram's-horn curves meeting at a top-centre point, each sweeping out and
/// curling inward into a spiral, plus a small dot at the top centre.
///
/// The geometry is authored in a fixed 100x100 design space (the same control
/// points the approved mockup uses) and scaled to fit the view's bounds while
/// preserving aspect ratio, so the mark stays crisp at any tile size. The path
/// is exposed both as a SwiftUI `Shape` (for stroking/filling in a view) and as
/// a pure `CGPath` builder (`designPath(in:)`) so its anchor geometry can be
/// unit-tested without SwiftUI.
///
/// Adinkra symbols are part of a living cultural tradition and are not a
/// trademark; this is our own drawing of the motif, not a copy of any
/// proprietary artwork.
public struct DwennimmenMark: Shape {

    /// Whether to include the small top-centre dot in the stroked path. The dot
    /// is a separate filled element in the view, so the default omits it here.
    private let includesDot: Bool

    public init(includesDot: Bool = false) {
        self.includesDot = includesDot
    }

    // MARK: - Design space

    /// The square design space the control points are authored in. The mirror
    /// axis is x = `designSize / 2`.
    public static let designSize: CGFloat = 100

    /// Centre of the top dot in design space, and its radius.
    public static let dotCenter = CGPoint(x: 50, y: 10)
    public static let dotRadius: CGFloat = 5

    // MARK: - Shape

    public func path(in rect: CGRect) -> Path {
        Path(DwennimmenMark.designPath(includesDot: includesDot).cgPath)
            .applying(DwennimmenMark.fitTransform(into: rect))
    }

    // MARK: - Pure geometry

    /// The two-horn path in the fixed 100x100 design space (top-left origin,
    /// y down), optionally including the top dot as a sub-path. Pure CoreGraphics
    /// so the anchor points can be asserted in tests without a view.
    ///
    /// Each horn is ONE bold sweep: from the shared top-centre peak (50, 22) it
    /// arcs up and OUT over the shoulder to the outer flank, runs down the
    /// outside, then curls across the bottom and spirals UP-AND-IN to a single
    /// clean inner terminus — one loop, not a stack of over-curls, so it stays
    /// legible as a ram's horn down to small sizes. The right horn is the exact
    /// mirror about x = 50 (x' = 100 - x).
    public static func designPath(includesDot: Bool = false) -> Path {
        var path = Path()

        // Left horn: peak -> outer flank -> bottom curl -> inner spiral terminus.
        path.move(to: CGPoint(x: 50, y: 22))
        path.addCurve(
            to: CGPoint(x: 16, y: 44),
            control1: CGPoint(x: 30, y: 16),
            control2: CGPoint(x: 16, y: 24)
        )
        path.addCurve(
            to: CGPoint(x: 44, y: 70),
            control1: CGPoint(x: 16, y: 66),
            control2: CGPoint(x: 30, y: 72)
        )
        path.addCurve(
            to: CGPoint(x: 38, y: 48),
            control1: CGPoint(x: 54, y: 68),
            control2: CGPoint(x: 52, y: 50)
        )

        // Right horn: mirror of the left about x = 50 (x' = 100 - x).
        path.move(to: CGPoint(x: 50, y: 22))
        path.addCurve(
            to: CGPoint(x: 84, y: 44),
            control1: CGPoint(x: 70, y: 16),
            control2: CGPoint(x: 84, y: 24)
        )
        path.addCurve(
            to: CGPoint(x: 56, y: 70),
            control1: CGPoint(x: 84, y: 66),
            control2: CGPoint(x: 70, y: 72)
        )
        path.addCurve(
            to: CGPoint(x: 62, y: 48),
            control1: CGPoint(x: 46, y: 68),
            control2: CGPoint(x: 48, y: 50)
        )

        if includesDot {
            path.addEllipse(in: CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }

        return path
    }

    /// The aspect-preserving transform that fits the 100x100 design space
    /// centred into `rect` (the largest centred square). Exposed so tests can map
    /// design points into a known target rect and check the fit.
    public static func fitTransform(into rect: CGRect) -> CGAffineTransform {
        let side = min(rect.width, rect.height)
        let scale = side / designSize
        let offsetX = rect.minX + (rect.width - side) / 2
        let offsetY = rect.minY + (rect.height - side) / 2
        return CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
    }
}
