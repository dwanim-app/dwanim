import Foundation
import SkinKit

// MARK: - RegionHitTest
//
// Pure point-in-region hit-testing for a shaped classic window, so a click in a
// transparent CUT-OUT (outside the region silhouette) can be passed THROUGH to
// whatever is behind, while a click inside the silhouette hits the window
// normally. It needs NO graphics framework.
//
// The predicate is defined against the SAME `RegionCoverage` mask the window's
// visual shape is built from (`RegionMaskGeometry.coverageSpans`), so "what you
// can click" is exactly "what you can see" — the hit region can never drift from
// the rendered silhouette. Callers precompute the mask once at window setup and
// feed it here per event (a cheap array lookup), after mapping the view-space
// event point to skin space with the shared `ControlHitTest.skinPoint` flip.

public enum RegionHitTest {

    /// Whether the skin-pixel `(skinX, skinY)` is INSIDE the region — i.e. its
    /// coverage cell is `true`. Points outside the canvas, or an inconsistent mask,
    /// read as OUTSIDE (so an out-of-bounds event never traps and is treated as a
    /// cut-out). `mask` is the row-major `[Bool]` from
    /// `RegionCoverage.mask` / `RegionMaskGeometry`.
    public static func isInside(
        mask: [Bool],
        width: Int,
        height: Int,
        skinX: Int,
        skinY: Int
    ) -> Bool {
        guard skinX >= 0, skinX < width, skinY >= 0, skinY < height else { return false }
        let index = skinY * width + skinX
        guard index >= 0, index < mask.count else { return false }
        return mask[index]
    }

    /// Convenience that builds the coverage mask from `region` and tests one skin
    /// point. Prefer the `mask:`-based overload at runtime (build the mask once and
    /// reuse it); this variant is for simple callers and tests.
    public static func isInside(
        region: SkinRegion,
        width: Int,
        height: Int,
        skinX: Int,
        skinY: Int
    ) -> Bool {
        let mask = RegionCoverage.mask(region, width: width, height: height)
        return isInside(mask: mask, width: width, height: height, skinX: skinX, skinY: skinY)
    }
}
