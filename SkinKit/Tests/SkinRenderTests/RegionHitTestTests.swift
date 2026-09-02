import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// The pure point-in-region hit predicate used for click-through on shaped
/// windows. (The manual-drag clamp lives in `WindowDragMathTests`.)
final class RegionHitTestTests: XCTestCase {

    // MARK: - isInside(mask:)

    func testInsideAndOutsideOfMask() {
        // 4x3 canvas, a 2x2 block covered at (1,0)-(2,1).
        let w = 4, h = 3
        var mask = [Bool](repeating: false, count: w * h)
        mask[0 * w + 1] = true; mask[0 * w + 2] = true
        mask[1 * w + 1] = true; mask[1 * w + 2] = true

        XCTAssertTrue(RegionHitTest.isInside(mask: mask, width: w, height: h, skinX: 1, skinY: 0))
        XCTAssertTrue(RegionHitTest.isInside(mask: mask, width: w, height: h, skinX: 2, skinY: 1))
        XCTAssertFalse(RegionHitTest.isInside(mask: mask, width: w, height: h, skinX: 0, skinY: 0))
        XCTAssertFalse(RegionHitTest.isInside(mask: mask, width: w, height: h, skinX: 3, skinY: 2))
    }

    func testOutOfBoundsIsOutside() {
        let mask = [Bool](repeating: true, count: 4 * 3)
        XCTAssertFalse(RegionHitTest.isInside(mask: mask, width: 4, height: 3, skinX: -1, skinY: 0))
        XCTAssertFalse(RegionHitTest.isInside(mask: mask, width: 4, height: 3, skinX: 0, skinY: 3))
        XCTAssertFalse(RegionHitTest.isInside(mask: mask, width: 4, height: 3, skinX: 4, skinY: 0))
    }

    func testSizeMismatchMaskIsOutside() {
        // A short/garbled mask never traps; in-bounds indices past the array read false.
        let mask = [Bool](repeating: true, count: 2)
        XCTAssertFalse(RegionHitTest.isInside(mask: mask, width: 4, height: 3, skinX: 3, skinY: 2))
    }

    // MARK: - isInside(region:) matches the rendered silhouette

    func testRegionOverloadMatchesCoverage() {
        // A chamfered corner: (0,0) is cut out, the interior is inside.
        let region = SkinRegion(polygons: [
            SkinRegion.Polygon(points: [
                .init(x: 0, y: 3), .init(x: 3, y: 0), .init(x: 20, y: 0),
                .init(x: 20, y: 20), .init(x: 0, y: 20)
            ])
        ])
        XCTAssertFalse(RegionHitTest.isInside(region: region, width: 20, height: 20, skinX: 0, skinY: 0),
                       "chamfered corner is a cut-out (click-through)")
        XCTAssertTrue(RegionHitTest.isInside(region: region, width: 20, height: 20, skinX: 10, skinY: 10),
                      "interior is a hit")
    }

}
