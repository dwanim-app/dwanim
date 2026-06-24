import AppKit
import CoreGraphics
import Foundation
import SkinKit

// MARK: - RegionMaskLayer
//
// Builds a WINDOW/LAYER-LEVEL mask for a non-rectangular skin window from the
// skin's `region.polygons`. This is the shell-side (AppKit / CoreGraphics)
// counterpart to the pure `RegionCoverage` math: rather than baking alpha into
// the displayed bitmap, the content stays OPAQUE and the SHAPE is carried by a
// `CAShapeLayer` set as the content view layer's `mask`. Geometry is kept
// separate from pixels — needed for future hit-testing.
//
// Coordinate mapping (the careful part):
//   - Region vertices are in the skin's NATURAL pixel space (e.g. 275x116),
//     TOP-LEFT origin, x rightward / y downward.
//   - The content view shows the composed image at an integer `scale`, so a skin
//     pixel spans `scale` view points.
//   - The displayed content is NOT vertically flipped: `CGImageConversion`
//     produces a top-left-origin CGImage and `SkinImageView` draws it
//     right-side-up in a non-flipped `NSView`, so skin row 0 appears at the
//     visual TOP. The `CAShapeLayer` mask shares that same layer space, so the
//     mask must use the SAME (no-flip) y mapping to align with where each skin
//     row actually draws. (An earlier vertical flip masked the mirrored shape.)
//
// A skin pixel `(px, py)` therefore maps to layer point:
//     x = px * scale
//     y = py * scale
//
// Each `Polygon` becomes a sub-path: move to the first vertex, line to the rest,
// then close. The mask path is the union of all polygons, filled with the
// NON-ZERO winding rule so overlapping polygons OR together (true union),
// matching `RegionCoverage`'s union semantics for the visible region.

enum RegionMaskLayer {

    /// Builds the mask path for `region` in the content view's coordinate space,
    /// where the view shows the image at integer `scale`.
    ///
    /// `skinHeight` is the image's pixel height; it is accepted for call-site
    /// stability but is NOT used to flip the y axis (the displayed content is not
    /// flipped, so the mask must not be either — see the type-level note).
    ///
    /// Returns `nil` if the region has no fillable polygon (fewer than 3 points
    /// in every polygon), so the caller can fall back to an unshaped window.
    static func maskPath(
        for region: SkinRegion,
        skinHeight _: Int,
        scale: Int
    ) -> CGPath? {
        let fillable = region.polygons.filter { $0.points.count >= 3 }
        guard !fillable.isEmpty else { return nil }

        let scaleD = CGFloat(scale)
        let path = CGMutablePath()

        for polygon in fillable {
            let points = polygon.points
            // Map skin (top-left, y-down) -> content-layer space, scaled. The
            // displayed content is NOT flipped, so the mask uses the same y (no
            // vertical mirror) to align with where each skin row actually draws.
            func mapped(_ p: SkinRegion.Point) -> CGPoint {
                CGPoint(
                    x: CGFloat(p.x) * scaleD,
                    y: CGFloat(p.y) * scaleD
                )
            }
            path.move(to: mapped(points[0]))
            for point in points.dropFirst() {
                path.addLine(to: mapped(point))
            }
            path.closeSubpath()
        }
        return path
    }

    /// Builds a `CAShapeLayer` that masks a content view of size
    /// `scaledWidth x scaledHeight` (in points) to `region`'s shape, or `nil` if
    /// the region declares no fillable polygon.
    ///
    /// The shape layer's frame matches the content view's bounds and its `path`
    /// is built in that same (no-flip) content-layer space; assigning it to the
    /// content view layer's `mask` clips the OPAQUE content to the region outline.
    /// The NON-ZERO winding fill OR-s overlapping polygons, matching the union
    /// semantics of the pure coverage math.
    static func make(
        for region: SkinRegion,
        skinHeight: Int,
        scale: Int,
        scaledWidth: Int,
        scaledHeight: Int
    ) -> CAShapeLayer? {
        guard let path = maskPath(for: region, skinHeight: skinHeight, scale: scale) else {
            return nil
        }
        let layer = CAShapeLayer()
        layer.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        layer.path = path
        layer.fillRule = .nonZero
        // Any opaque fill color works: the shape layer is used purely as a mask;
        // CoreAnimation uses the rendered shape's alpha as the mask coverage.
        layer.fillColor = NSColor.white.cgColor
        return layer
    }
}
