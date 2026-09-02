import Foundation
import SkinKit

// MARK: - RegionMaskGeometry
//
// Pure geometry that turns a `SkinRegion` into the SHAPE a window-level mask must
// fill. It needs NO graphics framework: it reduces the region to row-major
// horizontal PIXEL SPANS whose union is EXACTLY `RegionCoverage.mask`, and maps
// those spans into the content view's (bottom-left origin) point space.
//
// WHY spans (and not the raw polygons): the classic `region.txt` fill rule is
// EVEN-ODD within each polygon, UNIONED across polygons (see `RegionCoverage`). A
// `CAShapeLayer.fillRule` is a SINGLE per-path setting — `.nonZero` OR `.evenOdd`
// for the whole path — and can express neither:
//   • `.evenOdd` on the combined path turns the nested-rectangle "rounded corners"
//     idiom (overlapping slabs) into concentric RINGS (each overlap toggles the
//     hole);
//   • `.nonZero` on the combined path fills a self-intersecting "hairline border"
//     polygon SOLID instead of leaving the 1px outline the even-odd rule intends,
//     and turns a reverse-wound sub-polygon into a subtracted hole rather than a
//     union.
// Deriving the mask from `RegionCoverage` (which already implements the correct
// per-polygon-even-odd + union rule) and emitting one rect per covered pixel-run
// BAKES that rule into plain axis-aligned geometry, so a single `.nonZero` fill of
// the resulting rectilinear path reproduces the coverage exactly. The AppKit tier
// (`RegionMaskLayer`) is only a thin `CGPath` builder over `viewRects`.
//
// WHAT COUNTS AS A SHAPE: `shape(for:width:height:)` is the ONE decision point for
// "does this region shape the window?". It answers `nil` — a plain opaque
// rectangular window, exactly as if `region.txt` were absent — for an empty /
// degenerate region AND for a region whose coverage is the FULL canvas. The
// archetypal inert `[Normal]` `0,0 275,0 275,116 0,116` (the most common region.txt
// content by far) is such a full-window rectangle: it declares a shape that is
// identical to no shape, and must not push the window onto the shaped path (which
// drops the shadow, goes non-opaque, switches to the manual drag and installs the
// hit-test override).

public enum RegionMaskGeometry {

    // MARK: - Span

    /// A horizontal run of covered pixels on one row, in the skin's top-left-origin
    /// pixel space: columns `[x, x + width)` of row `y`.
    public struct Span: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let width: Int
        public init(x: Int, y: Int, width: Int) {
            self.x = x
            self.y = y
            self.width = width
        }
    }

    // MARK: - Shape (mask + spans, computed once)

    /// The resolved shape of a region on a canvas: the coverage `mask` (what the
    /// click-through hit test reads, via `RegionHitTest`) and its `spans` (what the
    /// layer mask fills). Both come from ONE `RegionCoverage.mask` computation, so
    /// "what you can click" and "what you can see" can never disagree.
    public struct Shape: Equatable, Sendable {
        public let width: Int
        public let height: Int
        /// Row-major `[Bool]` of size `width * height`, `true` = inside.
        public let mask: [Bool]
        /// The covered pixel runs of `mask` (see `spans(from:width:height:)`).
        public let spans: [Span]

        public init(width: Int, height: Int, mask: [Bool], spans: [Span]) {
            self.width = width
            self.height = height
            self.mask = mask
            self.spans = spans
        }
    }

    /// The shape `region` gives a `width` x `height` window, or `nil` when the
    /// region does NOT shape it:
    ///   • the region is empty / degenerate (no polygon with >= 3 vertices);
    ///   • its coverage is FULL — every pixel inside (the inert full-window
    ///     rectangle, or a union of slabs that happens to cover everything);
    ///   • its coverage is EMPTY — nothing inside (e.g. every polygon lies
    ///     off-canvas); an invisible window is never what a skin intends, so it
    ///     stays a plain rectangle rather than vanishing.
    /// A non-`nil` result always has at least one span and at least one uncovered
    /// pixel — a real silhouette worth a mask.
    public static func shape(for region: SkinRegion, width: Int, height: Int) -> Shape? {
        guard !region.isEmpty, width > 0, height > 0 else { return nil }
        let mask = RegionCoverage.mask(region, width: width, height: height)
        guard !isFullCoverage(mask) else { return nil }
        let runs = spans(from: mask, width: width, height: height)
        guard !runs.isEmpty else { return nil }
        return Shape(width: width, height: height, mask: mask, spans: runs)
    }

    /// `true` when `mask` covers EVERY pixel (all cells `true`). An empty mask is
    /// not "full" — there is nothing it covers.
    public static func isFullCoverage(_ mask: [Bool]) -> Bool {
        !mask.isEmpty && mask.allSatisfy { $0 }
    }

    // MARK: - Region -> spans

    /// The covered-pixel spans for `region` on a `width` x `height` canvas. Their
    /// union equals `RegionCoverage.mask(region, width:height:)` cell-for-cell, so
    /// filling them (nonzero) reproduces the region's exact visible coverage.
    ///
    /// An empty / degenerate region (no polygon with >= 3 vertices) makes
    /// `RegionCoverage.mask` all-true, so this returns full-width spans for every
    /// row — a rectangular "shape". This is the raw reduction; window code goes
    /// through `shape(for:width:height:)`, which folds the "is it a shape at all"
    /// decision in.
    public static func coverageSpans(for region: SkinRegion, width: Int, height: Int) -> [Span] {
        let mask = RegionCoverage.mask(region, width: width, height: height)
        return spans(from: mask, width: width, height: height)
    }

    /// Reduces a row-major `[Bool]` coverage mask to its horizontal runs. Returns
    /// `[]` when the mask size is inconsistent with `width * height` (fault
    /// tolerant, matching the coverage seam's size guards).
    public static func spans(from mask: [Bool], width: Int, height: Int) -> [Span] {
        guard width > 0, height > 0, mask.count == width * height else { return [] }
        var result: [Span] = []
        for y in 0..<height {
            let rowStart = y * width
            var x = 0
            while x < width {
                guard mask[rowStart + x] else { x += 1; continue }
                let start = x
                while x < width, mask[rowStart + x] { x += 1 }
                result.append(Span(x: start, y: y, width: x - start))
            }
        }
        return result
    }

    // MARK: - Spans -> view rects (the y-flip, pure)

    /// An axis-aligned rect in the content view's coordinate space: a NON-flipped
    /// view (bottom-left origin, y up) showing the skin at the presentation
    /// `scale`. `(x, y)` is the LOWER-left corner; all values are points.
    public struct ViewRect: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Maps skin-space pixel spans into view-space rects at the presentation
    /// `scale` (points per skin pixel, possibly fractional — e.g. 1.5), flipping y
    /// from the skin's top-left origin to the view's bottom-left origin. Skin row
    /// `y` occupies view-y `[viewHeight - (y + 1) * scale, viewHeight - y * scale)`,
    /// so skin row 0 sits at the visual TOP (high view y). The lower-left corner is
    /// therefore the `ControlHitTest.viewPoint` of the pixel one row BELOW the
    /// span (`skinY + 1`) — the SAME flip click routing uses, so the mask, the
    /// clicks and the drawn pixels can never disagree on orientation.
    ///
    /// Every edge lands on a skin-pixel boundary times `scale`; on an integer
    /// device-pixels-per-skin-pixel ratio the rects coincide with device pixels and
    /// a shape-layer fill of them has no fractional coverage to antialias. Because
    /// the spans are exact half-open pixel runs, there is no "+1px" overhang to
    /// correct.
    public static func viewRects(spans: [Span], viewHeight: Double, scale: Double) -> [ViewRect] {
        spans.map { span in
            let lowerLeft = ControlHitTest.viewPoint(
                skinX: span.x, skinY: span.y + 1, viewHeight: viewHeight, scale: scale
            )
            return ViewRect(
                x: lowerLeft.x,
                y: lowerLeft.y,
                width: Double(span.width) * scale,
                height: scale
            )
        }
    }

    // MARK: - Spans -> mask (verification / tests)

    /// Rasterizes `spans` back into a row-major `[Bool]` of size `width * height`.
    /// The inverse of `spans(from:width:height:)`: for any coverage mask,
    /// `rasterize(spans(from: m, …), …) == m`. Used to CROSS-CHECK that the mask
    /// geometry and `RegionCoverage` agree.
    public static func rasterize(_ spans: [Span], width: Int, height: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: max(0, width) * max(0, height))
        guard width > 0, height > 0 else { return mask }
        for span in spans {
            guard span.y >= 0, span.y < height else { continue }
            let rowStart = span.y * width
            let end = min(width, max(0, span.x) + max(0, span.width))
            var x = max(0, span.x)
            while x < end {
                mask[rowStart + x] = true
                x += 1
            }
        }
        return mask
    }
}
