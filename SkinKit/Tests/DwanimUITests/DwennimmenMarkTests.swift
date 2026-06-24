import XCTest
import SwiftUI
@testable import DwanimUI

// MARK: - DwennimmenMarkTests

/// Light geometry checks for the `DwennimmenMark`. The mark is presentation,
/// but its design-space anchor points are load-bearing (the horns must meet at
/// the top centre and the two horns must be mirror images), so a few asserts
/// guard against the control points drifting.
final class DwennimmenMarkTests: XCTestCase {

    /// The path is non-empty and its bounds sit inside the 100x100 design space.
    func testDesignPathIsWithinDesignSpace() {
        let path = DwennimmenMark.designPath()
        XCTAssertFalse(path.isEmpty)

        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, 0)
        XCTAssertGreaterThanOrEqual(bounds.minY, 0)
        XCTAssertLessThanOrEqual(bounds.maxX, DwennimmenMark.designSize)
        XCTAssertLessThanOrEqual(bounds.maxY, DwennimmenMark.designSize)
    }

    /// Both horns start at the shared top-centre peak (50, 22), so the mark
    /// reads as a single emblem meeting at a peak rather than two stray strokes.
    /// The bounding box is therefore horizontally centred on x = 50.
    func testHornsAreHorizontallyCentred() {
        let bounds = DwennimmenMark.designPath().boundingRect
        let midX = bounds.midX
        XCTAssertEqual(midX, DwennimmenMark.designSize / 2, accuracy: 0.5)
    }

    /// The horns are mirror images about x = 50: the path's left and right
    /// extents are equidistant from the centre line.
    func testHornsAreMirroredAboutCentre() {
        let bounds = DwennimmenMark.designPath().boundingRect
        let centre = DwennimmenMark.designSize / 2
        let leftGap = centre - bounds.minX
        let rightGap = bounds.maxX - centre
        XCTAssertEqual(leftGap, rightGap, accuracy: 0.5)
    }

    /// Including the dot extends the bounds upward to cover the dot at (50, 10)
    /// with radius 5 (top edge at y = 5), above the horns' top reach (y ~ 16).
    func testDotExtendsBoundsUpward() {
        let withoutDot = DwennimmenMark.designPath().boundingRect
        let withDot = DwennimmenMark.designPath(includesDot: true).boundingRect
        XCTAssertLessThan(withDot.minY, withoutDot.minY)
        let expectedTop = DwennimmenMark.dotCenter.y - DwennimmenMark.dotRadius
        XCTAssertEqual(withDot.minY, expectedTop, accuracy: 0.5)
    }

    /// The mark fills a balanced, near-square region: the horns reach wide
    /// (left/right flanks well out from centre) and tall (peak area down to the
    /// bottom curl), so the silhouette reads as a pair of bold horns rather than a
    /// thin or lopsided squiggle. Guards against the geometry collapsing inward.
    func testHornsFillABalancedRegion() {
        let bounds = DwennimmenMark.designPath().boundingRect
        // Wide: each flank sits at least 30 units out from the x = 50 centre.
        XCTAssertLessThanOrEqual(bounds.minX, 20)
        XCTAssertGreaterThanOrEqual(bounds.maxX, 80)
        // Tall: the horns span a good fraction of the design height.
        XCTAssertGreaterThanOrEqual(bounds.height, 45)
        // Roughly square aspect, so it sits well in a square tile / icon.
        let aspect = bounds.width / bounds.height
        XCTAssertEqual(aspect, 1, accuracy: 0.45)
    }

    /// The fit transform maps the design space into a target rect as the largest
    /// centred square: equal scale on both axes, and a 200x100 rect gets a 100px
    /// square horizontally centred (x offset 50, y offset 0).
    func testFitTransformCentresLargestSquare() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let transform = DwennimmenMark.fitTransform(into: rect)
        XCTAssertEqual(transform.a, 1, accuracy: 1e-9)  // 100 / 100
        XCTAssertEqual(transform.d, 1, accuracy: 1e-9)
        XCTAssertEqual(transform.tx, 50, accuracy: 1e-9) // (200 - 100) / 2
        XCTAssertEqual(transform.ty, 0, accuracy: 1e-9)

        // The dot centre maps to the centre of the target rect's square.
        let mappedDot = DwennimmenMark.dotCenter.applying(transform)
        XCTAssertEqual(mappedDot.x, 100, accuracy: 1e-9) // 50 + 50 offset
        XCTAssertEqual(mappedDot.y, 10, accuracy: 1e-9)
    }
}
