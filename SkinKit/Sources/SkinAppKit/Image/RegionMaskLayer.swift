import AppKit
import CoreGraphics
import Foundation
import SkinKit
import SkinRender

// MARK: - RegionMaskLayer
//
// Builds the WINDOW/LAYER-LEVEL mask for a non-rectangular skin window. This is
// the shell-side (AppKit / CoreGraphics) counterpart to the pure
// `RegionMaskGeometry`: rather than baking alpha into the displayed bitmap, the
// content stays OPAQUE and the SHAPE is carried by a `CAShapeLayer` set as the
// content view layer's `mask`. Geometry is kept separate from pixels — needed
// for hit-testing (`RegionHitTest`).
//
// This type is deliberately THIN: every decision lives in `SkinRender` and is
// unit-tested there.
//   • WHETHER the window is shaped at all — and the fill rule (even-odd per
//     polygon, unioned) — is `RegionMaskGeometry.shape(for:width:height:)`. It
//     answers `nil` for an empty region AND for a full-window rectangle, so an
//     inert `[Normal] 0,0 275,0 275,116 0,116` never reaches this file.
//   • WHERE each covered pixel-run lands in the NON-flipped content view (the
//     y-flip, the scale, the row grid) is `RegionMaskGeometry.viewRects`, built
//     on the same `ControlHitTest.viewPoint` flip click routing uses.
// All that is left here is turning those rects into a `CGPath` and a layer.
//
// FILL RULE: a `CAShapeLayer.fillRule` is a single per-path setting and can
// express neither `.evenOdd` nor `.nonZero` correctly for the classic rule, so
// the mask is NOT built from the raw polygons — it is built from the coverage
// spans, whose rects are disjoint per row and OR cleanly across rows, so a plain
// `.nonZero` fill reproduces the coverage exactly (see `RegionMaskGeometry`).
//
// PIXEL GRID: every rect edge lands on a skin-pixel boundary times the
// presentation `scale`. The app presents at 1x (one point per skin pixel), so
// on a 2x backing each skin pixel is exactly 2 device pixels — an integer —
// and the mask edges coincide with device-pixel boundaries: no fractional
// coverage to antialias, a hard-edged silhouette on the SAME grid as the
// nearest-neighbor sprite bitmap. The mask is rasterized at DEVICE resolution
// (`contentsScale`), which `RegionWindowBuilder` sets from the window's actual
// `backingScaleFactor` once the window exists.

public enum RegionMaskLayer {

    /// The mask path for `shape` in the content view's coordinate space, where
    /// the view shows the skin at the presentation `scale` (points per skin
    /// pixel, possibly fractional). A union of one axis-aligned rect per covered
    /// pixel-run, placed by the pure `RegionMaskGeometry.viewRects`.
    public static func maskPath(for shape: RegionMaskGeometry.Shape, scale: Double) -> CGPath {
        let viewHeight = Double(shape.height) * scale
        let path = CGMutablePath()
        for rect in RegionMaskGeometry.viewRects(spans: shape.spans, viewHeight: viewHeight, scale: scale) {
            path.addRect(CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
        }
        return path
    }

    /// A `CAShapeLayer` that masks a content view of `shape.width * scale` x
    /// `shape.height * scale` POINTS to `shape`'s silhouette. `.nonZero` simply
    /// OR-s the disjoint rects. `contentsScale` is left for the window builder to
    /// set from the real `backingScaleFactor`.
    public static func make(for shape: RegionMaskGeometry.Shape, scale: Double) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(
            x: 0, y: 0,
            width: Double(shape.width) * scale,
            height: Double(shape.height) * scale
        )
        layer.path = maskPath(for: shape, scale: scale)
        layer.fillRule = .nonZero
        // Any opaque fill color works: the layer is used purely as a mask; Core
        // Animation uses the rendered shape's alpha as the mask coverage.
        layer.fillColor = NSColor.white.cgColor
        return layer
    }
}
