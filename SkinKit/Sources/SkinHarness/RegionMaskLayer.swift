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
//   - AppKit / CoreAnimation layers are BOTTOM-LEFT origin by default (y upward).
//     So the y axis must be FLIPPED about the (scaled) skin height.
//
// A skin pixel `(px, py)` therefore maps to layer point:
//     x = px * scale
//     y = (skinHeight - py) * scale
//
// Each `Polygon` becomes a sub-path: move to the first vertex, line to the rest,
// then close. The mask path is the union of all polygons (even-odd fill), which
// matches `RegionCoverage`'s union semantics for the visible region.

enum RegionMaskLayer {

    /// Builds the mask path for `region` in the content view's coordinate space,
    /// where the view shows a `skinWidth x skinHeight` image at integer `scale`.
    ///
    /// Returns `nil` if the region has no fillable polygon (fewer than 3 points
    /// in every polygon), so the caller can fall back to an unshaped window.
    static func maskPath(
        for region: SkinRegion,
        skinHeight: Int,
        scale: Int
    ) -> CGPath? {
        let fillable = region.polygons.filter { $0.points.count >= 3 }
        guard !fillable.isEmpty else { return nil }

        let scaleD = CGFloat(scale)
        let heightD = CGFloat(skinHeight)
        let path = CGMutablePath()

        for polygon in fillable {
            let points = polygon.points
            // Map skin (top-left, y-down) -> layer (bottom-left, y-up), scaled.
            func mapped(_ p: SkinRegion.Point) -> CGPoint {
                CGPoint(
                    x: CGFloat(p.x) * scaleD,
                    y: (heightD - CGFloat(p.y)) * scaleD
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
    /// is built in that same (bottom-left origin) space; assigning it to the
    /// content view layer's `mask` clips the OPAQUE content to the region outline.
    /// Even-odd fill matches the union semantics of the pure coverage math.
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
        layer.fillRule = .evenOdd
        // Any opaque fill color works: the shape layer is used purely as a mask;
        // CoreAnimation uses the rendered shape's alpha as the mask coverage.
        layer.fillColor = NSColor.white.cgColor
        return layer
    }
}
