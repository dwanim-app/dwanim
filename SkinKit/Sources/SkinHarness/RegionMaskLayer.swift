import AppKit
import CoreGraphics
import Foundation
import SkinKit
import SkinRender

// MARK: - RegionMaskLayer
//
// Builds a WINDOW/LAYER-LEVEL mask for a non-rectangular skin window from the
// skin's `region.polygons`. This is the shell-side (AppKit / CoreGraphics)
// counterpart to the pure `RegionCoverage` math: rather than baking alpha into
// the displayed bitmap, the content stays OPAQUE and the SHAPE is carried by a
// `CAShapeLayer` set as the content view layer's `mask`. Geometry is kept
// separate from pixels — needed for future hit-testing.
//
// Coordinate mapping (the careful part — this is the project's highest-risk
// bug class, so the flip lives in ONE tested place):
//   - Region vertices are in the skin's NATURAL pixel space (e.g. 275x116),
//     TOP-LEFT origin, x rightward / y downward.
//   - The content view shows the composed image at an integer `scale` in a
//     NON-flipped `NSView` (origin bottom-left, y UP). `SkinImageView` draws the
//     top-left-origin CGImage via `context.draw(image, in: bounds)`, and
//     CoreGraphics AUTO-ORIENTS the image in that bottom-left context, so skin
//     row 0 appears at the visual TOP (high y).
//   - A `CAShapeLayer` mask path, however, is RAW layer geometry — it gets no
//     such auto-orientation. So to land the mask where each skin row actually
//     draws, y MUST be flipped: skin row 0 -> high y. This is the exact inverse
//     of the (verified-correct) click transform `ControlHitTest.skinPoint`; if
//     this used no flip while clicks use a flip, the silhouette would be
//     vertically mirrored relative to where clicks/pixels go. The flip is
//     therefore delegated to `ControlHitTest.viewPoint` (pure + unit-tested as
//     skinPoint's inverse) so the two can never disagree again.
//
// A skin pixel `(px, py)` maps to layer point (viewHeight = skinHeight * scale):
//     x = px * scale
//     y = viewHeight - py * scale
//
// Each `Polygon` becomes a sub-path: move to the first vertex, line to the rest,
// then close. The mask path is the union of all polygons, filled with the
// NON-ZERO winding rule so overlapping polygons OR together (true union),
// matching `RegionCoverage`'s union semantics for the visible region.

enum RegionMaskLayer {

    /// Builds the mask path for `region` in the content view's coordinate space,
    /// where the view shows the image at integer `scale`.
    ///
    /// `skinHeight` is the image's pixel height; it is load-bearing — it sets the
    /// view height used to flip y (skin top-left origin -> the non-flipped view's
    /// bottom-left origin), so the mask aligns with where each skin row draws.
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

        let viewHeight = Double(skinHeight * scale)
        let path = CGMutablePath()

        for polygon in fillable {
            let points = polygon.points
            // Map skin (top-left, y-down) -> content-layer space (bottom-left,
            // y-up), scaled. The y-flip is delegated to ControlHitTest.viewPoint
            // (the tested inverse of the click transform) so the mask and click
            // routing can never disagree on orientation. See the type-level note.
            func mapped(_ p: SkinRegion.Point) -> CGPoint {
                let vp = ControlHitTest.viewPoint(
                    skinX: p.x,
                    skinY: p.y,
                    viewHeight: viewHeight,
                    scale: scale
                )
                return CGPoint(x: vp.x, y: vp.y)
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
