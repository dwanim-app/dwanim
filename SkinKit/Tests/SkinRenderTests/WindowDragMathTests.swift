import Foundation
import XCTest
@testable import SkinRender

/// The pure clamp behind a shaped window's MANUAL title-bar drag. The AppKit view
/// gathers the union of every screen's visible frame; the math here keeps the
/// window's top under that union's top (the menu bar) AND keeps at least a
/// grab-strip's worth of the window on-screen at the bottom and both sides, so a
/// shaped window can never be dragged somewhere it cannot be grabbed again.
final class WindowDragMathTests: XCTestCase {

    // MARK: - Fixtures

    /// A single 1440x900 display whose visible frame excludes a 25pt menu bar.
    private let singleScreen = WindowDragMath.Rect(x: 0, y: 0, width: 1440, height: 875)

    /// The same display plus a second one arranged ABOVE it (its own menu bar
    /// excluded): the union spans both.
    private let stacked: [WindowDragMath.Rect] = [
        WindowDragMath.Rect(x: 0, y: 0, width: 1440, height: 875),
        WindowDragMath.Rect(x: 0, y: 900, width: 1440, height: 1055)
    ]

    private let strip = 14.0

    // MARK: - Union of screens

    func testUnionOfScreensIsTheirBoundingBox() {
        let union = WindowDragMath.union(of: stacked)
        XCTAssertEqual(union, WindowDragMath.Rect(x: 0, y: 0, width: 1440, height: 1955))
        XCTAssertEqual(union?.maxY, 1955)
    }

    func testUnionOfNoScreensIsNil() {
        XCTAssertNil(WindowDragMath.union(of: []))
    }

    func testUnionSpansSideBySideScreensWithDifferentOrigins() {
        let side = [
            WindowDragMath.Rect(x: 0, y: 0, width: 1440, height: 875),
            WindowDragMath.Rect(x: -1920, y: -100, width: 1920, height: 1080)
        ]
        XCTAssertEqual(WindowDragMath.union(of: side),
                       WindowDragMath.Rect(x: -1920, y: -100, width: 3360, height: 1080))
    }

    // MARK: - Top clamp (menu bar)

    func testTopClampKeepsWindowBelowMenuBar() {
        // visibleTop = 875, window 174 tall -> max origin.y = 701.
        let clamped = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: 800, windowWidth: 275, windowHeight: 174,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(clamped.y, 701, accuracy: 1e-9, "an origin pushing the top above the menu bar is clamped")
        XCTAssertEqual(clamped.x, 100, accuracy: 1e-9, "x inside the area passes through")
    }

    func testWindowWellInsideTheAreaPassesThroughUnchanged() {
        let clamped = WindowDragMath.clampedOrigin(
            proposedX: 300, proposedY: 100, windowWidth: 275, windowHeight: 174,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(clamped.x, 300, accuracy: 1e-9)
        XCTAssertEqual(clamped.y, 100, accuracy: 1e-9)
    }

    // MARK: - Union of screens: a display ABOVE is reachable

    func testTopClampUsesTheUnionTopSoTheWindowCanMoveOntoAScreenAbove() {
        let area = WindowDragMath.union(of: stacked)!
        // Well inside the upper screen: passes through (the single-screen clamp
        // would have pinned this at 875 - 116 = 759).
        let up = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: 1500, windowWidth: 275, windowHeight: 116,
            allowedArea: area, grabStripHeight: strip
        )
        XCTAssertEqual(up.y, 1500, accuracy: 1e-9)
        // Above the UPPER screen's menu bar: clamped to 1955 - 116.
        let tooHigh = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: 1900, windowWidth: 275, windowHeight: 116,
            allowedArea: area, grabStripHeight: strip
        )
        XCTAssertEqual(tooHigh.y, 1839, accuracy: 1e-9)
    }

    // MARK: - Bottom clamp: the grab strip stays on-screen

    func testBottomClampKeepsTheTitleBarStripVisible() {
        // Dragged far below the bottom edge: the window's TOP strip (14pt) must
        // stay above y = 0 -> origin.y >= 0 + 14 - 116 = -102.
        let clamped = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: -400, windowWidth: 275, windowHeight: 116,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(clamped.y, -102, accuracy: 1e-9)
        // Exactly at the limit passes through.
        let atLimit = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: -102, windowWidth: 275, windowHeight: 116,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(atLimit.y, -102, accuracy: 1e-9)
    }

    // MARK: - Side clamps: a grab handle stays on-screen

    func testSideClampsKeepAGrabHandleOnScreen() {
        // Off the LEFT: at least 14pt of the window's width stays on-screen ->
        // origin.x >= 0 + 14 - 275 = -261.
        let left = WindowDragMath.clampedOrigin(
            proposedX: -1000, proposedY: 100, windowWidth: 275, windowHeight: 116,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(left.x, -261, accuracy: 1e-9)
        // Off the RIGHT: origin.x <= 1440 - 14 = 1426.
        let right = WindowDragMath.clampedOrigin(
            proposedX: 2000, proposedY: 100, windowWidth: 275, windowHeight: 116,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(right.x, 1426, accuracy: 1e-9)
    }

    func testSideClampsHonorTheUnionEdgesNotTheMainScreens() {
        let area = WindowDragMath.union(of: [
            WindowDragMath.Rect(x: 0, y: 0, width: 1440, height: 875),
            WindowDragMath.Rect(x: -1920, y: 0, width: 1920, height: 1080)
        ])!
        let left = WindowDragMath.clampedOrigin(
            proposedX: -1500, proposedY: 100, windowWidth: 275, windowHeight: 116,
            allowedArea: area, grabStripHeight: strip
        )
        XCTAssertEqual(left.x, -1500, accuracy: 1e-9, "inside the left display: not clamped")
    }

    // MARK: - Top wins when the area is shorter than the window

    func testTopClampWinsWhenTheWindowIsTallerThanTheArea() {
        let tiny = WindowDragMath.Rect(x: 0, y: 0, width: 400, height: 50)
        let clamped = WindowDragMath.clampedOrigin(
            proposedX: 0, proposedY: 500, windowWidth: 275, windowHeight: 116,
            allowedArea: tiny, grabStripHeight: strip
        )
        // Top clamp: 50 - 116 = -66 (the menu-bar rule is the one that must hold).
        XCTAssertEqual(clamped.y, -66, accuracy: 1e-9)
    }

    // MARK: - Non-finite inputs pass through (never trap)

    func testNonFiniteInputsPassTheProposedOriginThrough() {
        let nanY = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: .nan, windowWidth: 275, windowHeight: 116,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertTrue(nanY.y.isNaN)
        XCTAssertEqual(nanY.x, 100, accuracy: 1e-9, "the finite axis is still clamped normally")

        let infHeight = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: 500, windowWidth: 275, windowHeight: .infinity,
            allowedArea: singleScreen, grabStripHeight: strip
        )
        XCTAssertEqual(infHeight.y, 500, accuracy: 1e-9)

        let infStrip = WindowDragMath.clampedOrigin(
            proposedX: 100, proposedY: 500, windowWidth: 275, windowHeight: 116,
            allowedArea: singleScreen, grabStripHeight: .infinity
        )
        XCTAssertEqual(infStrip.x, 100, accuracy: 1e-9)
        XCTAssertEqual(infStrip.y, 500, accuracy: 1e-9)
    }
}
