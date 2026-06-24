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

    /// Both horns start at the shared top-centre point (50, 27), so the mark
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

    /// Including the dot extends the bounds upward to cover the dot at (50, 12)
    /// with radius 5 (top edge at y = 7), above the horns' top point (y ~ 27).
    func testDotExtendsBoundsUpward() {
        let withoutDot = DwennimmenMark.designPath().boundingRect
        let withDot = DwennimmenMark.designPath(includesDot: true).boundingRect
        XCTAssertLessThan(withDot.minY, withoutDot.minY)
        let expectedTop = DwennimmenMark.dotCenter.y - DwennimmenMark.dotRadius
        XCTAssertEqual(withDot.minY, expectedTop, accuracy: 0.5)
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
        XCTAssertEqual(mappedDot.y, 12, accuracy: 1e-9)
    }
}
