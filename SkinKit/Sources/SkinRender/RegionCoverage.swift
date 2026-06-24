import Foundation
import SkinKit

// MARK: - RegionCoverage
//
// Pure polygon→pixel coverage math for non-rectangular window shapes. Given a
// `SkinRegion` (a set of polygons in top-left-origin pixel coordinates), it
// produces a row-major `[Bool]` visibility mask and can stamp that mask into a
// `DecodedBitmap`'s alpha channel.
//
// This is PURE Foundation index math — no graphics framework. The mask it
// produces is what a platform layer turns into an actual shaped window; the
// alpha-zeroing path lets a PNG (or a CGImage) carry the same shape as
// transparency. The `compose` step stays rectangular and opaque; masking is a
// separate, later step applied to its output.
//
// Fill rule: even-odd, evaluated at each pixel's CENTER `(x + 0.5, y + 0.5)`.
// Sampling centers (rather than corners) removes the boundary ambiguity of
// integer edges, so an axis-aligned rectangle from `(x0, y0)` to `(x1, y1)`
// covers exactly the half-open pixel span `x0..<x1`, `y0..<y1`. The mask is the
// UNION of all polygons: a pixel is inside if it is inside an odd number of
// crossings for ANY single polygon (each polygon is filled independently, then
// OR-ed), which gives correct union behavior for disjoint shapes.

public enum RegionCoverage {

    // MARK: - Mask

    /// A row-major `[Bool]` of size `width * height`: `true` = inside the region
    /// (visible), `false` = outside. Top-left origin.
    ///
    /// The result is the union of all polygons, each filled by an even-odd
    /// scanline test at pixel centers. An empty region (no polygons, or no
    /// polygon with at least 3 points) yields an all-`true` mask, i.e. the
    /// window stays fully visible / rectangular.
    public static func mask(_ region: SkinRegion, width: Int, height: Int) -> [Bool] {
        let count = max(0, width) * max(0, height)

        // No usable shape → fully visible (rectangular). A polygon needs at least
        // 3 vertices to enclose any area; degenerate polygons contribute nothing.
        let fillable = region.polygons.filter { $0.points.count >= 3 }
        guard !fillable.isEmpty else {
            return [Bool](repeating: true, count: count)
        }

        var mask = [Bool](repeating: false, count: count)
        guard width > 0, height > 0 else { return mask }

        for polygon in fillable {
            fill(polygon, into: &mask, width: width, height: height)
        }
        return mask
    }

    // MARK: - Apply mask

    /// Sets the alpha byte to `0` for every pixel OUTSIDE the mask (RGB
    /// untouched); pixels inside the mask are left unchanged.
    ///
    /// `mask.count` must equal `width * height`; otherwise the bitmap is left
    /// unchanged (fault tolerant), matching the size-consistency guards used
    /// elsewhere in the compositing seam.
    public static func applyMask(_ mask: [Bool], to bitmap: inout DecodedBitmap) {
        let pixelCount = bitmap.width * bitmap.height
        guard mask.count == pixelCount else { return }
        guard bitmap.pixels.count == pixelCount * 4 else { return }

        var pixels = bitmap.pixels
        for index in 0..<pixelCount where !mask[index] {
            // Alpha is the trailing (4th) byte of each RGBA8 pixel; RGB untouched.
            pixels[index * 4 + 3] = 0
        }
        bitmap = DecodedBitmap(
            width: bitmap.width,
            height: bitmap.height,
            pixels: pixels
        )
    }

    // MARK: - Private: scanline fill

    /// Fills one polygon into `mask` (OR semantics) using an even-odd scanline
    /// test at each pixel center. For each row `y`, the polygon's edges are
    /// intersected with the horizontal line `y + 0.5`; the intersection x's are
    /// sorted and paired, and every pixel whose center x falls between a pair is
    /// marked inside.
    private static func fill(
        _ polygon: SkinRegion.Polygon,
        into mask: inout [Bool],
        width: Int,
        height: Int
    ) {
        let points = polygon.points
        let count = points.count

        for y in 0..<height {
            let scanY = Double(y) + 0.5
            var crossings: [Double] = []

            // Walk each edge (p[i] -> p[i+1], wrapping the last to the first).
            for i in 0..<count {
                let a = points[i]
                let b = points[(i + 1) % count]
                let ay = Double(a.y)
                let by = Double(b.y)

                // Edge straddles the scanline if exactly one endpoint is on each
                // side. The half-open `min <= scanY < max` test counts a vertex
                // shared by two edges exactly once, avoiding double-counting.
                let lowerY = min(ay, by)
                let upperY = max(ay, by)
                guard scanY >= lowerY, scanY < upperY else { continue }

                let ax = Double(a.x)
                let bx = Double(b.x)
                // x where the edge meets the scanline (linear interpolation).
                let t = (scanY - ay) / (by - ay)
                crossings.append(ax + t * (bx - ax))
            }

            guard crossings.count >= 2 else { continue }
            crossings.sort()

            // Even-odd: fill spans between consecutive crossing pairs.
            var pair = 0
            while pair + 1 < crossings.count {
                let xStart = crossings[pair]
                let xEnd = crossings[pair + 1]
                markSpan(xStart: xStart, xEnd: xEnd, y: y, into: &mask, width: width)
                pair += 2
            }
        }
    }

    /// Marks every pixel in row `y` whose center x falls within `[xStart, xEnd)`.
    /// Pixel `x` has center `x + 0.5`, so the inclusive column range is
    /// `ceil(xStart - 0.5) ... floor(xEnd - 0.5)`, clamped to the canvas.
    private static func markSpan(
        xStart: Double,
        xEnd: Double,
        y: Int,
        into mask: inout [Bool],
        width: Int
    ) {
        let firstCenter = xStart - 0.5
        let lastCenter = xEnd - 0.5
        let first = max(0, Int(firstCenter.rounded(.up)))
        let last = min(width - 1, Int(lastCenter.rounded(.down)))
        guard first <= last else { return }

        let rowStart = y * width
        for x in first...last {
            mask[rowStart + x] = true
        }
    }
}
