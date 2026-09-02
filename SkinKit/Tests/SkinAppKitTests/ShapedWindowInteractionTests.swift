import AppKit
import Foundation
import XCTest
import PlayerCore
import SkinKit
import SkinRender
@testable import SkinAppKit

// MARK: - ShapedWindowInteractionTests
//
// Closes the last verification gap on the region-shaping work WITHOUT a mouse or
// accessibility permission. Every test here builds a REAL classic main window
// through the production `showInteractiveWindow` seam — the exact path the app and
// the harness use — so the window is a genuine borderless `NSWindow` hosting a
// genuine `ScaledImageView`, wired with the genuine shaped-window predicates
// (`shouldManuallyDragWindow`, `regionContainsPoint`, the `CAShapeLayer` mask).
//
// The interactive behaviours are then driven by SYNTHESIZED `NSEvent`s handed
// straight to the view's real handlers (`mouseDown/Dragged/Up`, `hitTest`). No
// event is posted through CGEvent, so no input-monitoring or accessibility
// permission is needed and the tests are deterministic.
//
// TDD POSTURE: these assert the CURRENT behaviour is correct (a regression net),
// not a change. Where a test surfaced a genuine design nuance rather than a bug,
// it is pinned and documented (see `testB2_*`).
//
// KNOWN GEOMETRY: the classic main window is 275 x 116. All tests present at
// scale 1.0, so 1 skin pixel == 1 point and the view is 116 pt tall. The shaped
// fixture is that rectangle with the TOP-LEFT 40 x 40 corner notched out — a real
// silhouette with a cut-out that overlaps the title-bar strip (y < 14), which is
// exactly what makes the drag / click-through behaviours interesting.
//
// LIVE, WINDOW-SERVER-ONLY ITEM: cross-window alpha click-through (a click landing
// in a cut-out passing to the window BEHIND) cannot be proven in-process — it is a
// window-server behaviour. `testS5_*` asserts every necessary + sufficient
// PRECONDITION for it; the single remaining check is a live two-window click, an
// owner eyeball, called out there and in the final report.
@MainActor
final class ShapedWindowInteractionTests: XCTestCase {

    // MARK: - Constants

    private let winW = 275
    private let winH = 116
    private let scale: Double = 1.0
    private var viewHeight: CGFloat { CGFloat(winH) * CGFloat(scale) }

    // MARK: - Region fixtures

    /// The 275 x 116 window MINUS its top-left 40 x 40 corner (a notched
    /// rectangle). A single simple polygon traced around that outline; even-odd
    /// fill (per `RegionCoverage`) yields the notched interior. Covered columns on
    /// a title-bar row (y in 0..<40) are 40..<275, so x < 40 there is a cut-out.
    private func cornerCutRegion() -> SkinRegion {
        SkinRegion(polygons: [SkinRegion.Polygon(points: [
            SkinRegion.Point(x: 40, y: 0),
            SkinRegion.Point(x: 275, y: 0),
            SkinRegion.Point(x: 275, y: 116),
            SkinRegion.Point(x: 0, y: 116),
            SkinRegion.Point(x: 0, y: 40),
            SkinRegion.Point(x: 40, y: 40)
        ])])
    }

    /// The inert `[Normal] 0,0 275,0 275,116 0,116` full-window rectangle. Its
    /// coverage is the whole canvas, so per M1 it must be treated as UNSHAPED.
    private func fullRectRegion() -> SkinRegion {
        SkinRegion(polygons: [SkinRegion.Polygon(points: [
            SkinRegion.Point(x: 0, y: 0),
            SkinRegion.Point(x: 275, y: 0),
            SkinRegion.Point(x: 275, y: 116),
            SkinRegion.Point(x: 0, y: 116)
        ])])
    }

    // MARK: - Real window build (production path)

    /// Build a real classic main window through `showInteractiveWindow` for the
    /// given shaping `region` (`nil` = no region.txt at all). A minimal in-process
    /// `Skin` (just a 275 x 116 `main.bmp/background`) is enough for the composer;
    /// an inert engine backs a real `PlayerCore`. `tap`/`format` are `nil`, so no
    /// audio tap is installed. The redraw loop is torn down immediately (its timer
    /// is irrelevant to these tests and must not linger), leaving the fully wired
    /// window + view intact.
    private func makeWindow(region: SkinRegion?) throws -> InteractiveWindowHandle {
        _ = NSApplication.shared // bootstrap AppKit before creating an NSWindow
        let pixels = [UInt8](repeating: 0, count: winW * winH * 4)
        let background = DecodedBitmap(width: winW, height: winH, pixels: pixels)
        let skin = Skin(
            sprites: ["main.bmp": ["background": background]],
            visColors: [], playlist: nil, region: nil
        )
        let core = PlayerCore(engine: InertPlaybackEngine())
        let handle = try showInteractiveWindow(
            skin: skin, core: core, tap: nil, format: nil,
            region: region, scale: scale, title: "ShapedWindowTest",
            terminatesAppOnClose: false
        )
        handle.controller.tearDown() // stop the redraw timer; window/view wiring persists
        return handle
    }

    // MARK: - Coordinate + event helpers

    /// Forward map a skin pixel to the view's bottom-left-origin point space,
    /// matching `ControlHitTest.viewPoint` (x = skinX*scale, y = viewHeight -
    /// skinY*scale).
    private func viewPoint(skinX: Int, skinY: Int) -> NSPoint {
        NSPoint(x: CGFloat(skinX) * CGFloat(scale),
                y: viewHeight - CGFloat(skinY) * CGFloat(scale))
    }

    /// A synthesized mouse event whose `locationInWindow` is `windowLocation`
    /// (window base coords — what the view's handlers convert from `nil`).
    private func mouseEvent(
        _ type: NSEvent.EventType, at windowLocation: NSPoint, window: NSWindow
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type, location: windowLocation, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) else {
            fatalError("NSEvent.mouseEvent returned nil for \(type)")
        }
        return event
    }

    /// Reproduce `ScaledImageView.moveWindowDuringManualDrag` EXACTLY so the manual
    /// drag's resulting frame origin can be asserted deterministically. The handler
    /// tracks the LIVE cursor (`NSEvent.mouseLocation`) rather than the event delta,
    /// and clamps to the union of the screens' visible frames, so this reads the
    /// same two inputs (mouse + screens) and runs the same pure `WindowDragMath`.
    /// `anchor` is the grab point recorded at mouse-down (the view's
    /// `event.locationInWindow`).
    private func expectedManualDragOrigin(
        anchor: NSPoint, view: ScaledImageView, window: NSWindow
    ) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let proposedX = Double(mouse.x - anchor.x)
        let proposedY = Double(mouse.y - anchor.y)
        let rects = NSScreen.screens.map { screen -> WindowDragMath.Rect in
            let f = screen.visibleFrame
            return WindowDragMath.Rect(
                x: Double(f.origin.x), y: Double(f.origin.y),
                width: Double(f.width), height: Double(f.height)
            )
        }
        guard let union = WindowDragMath.union(of: rects) else {
            return NSPoint(x: proposedX, y: proposedY) // no screens -> unclamped
        }
        let clamped = WindowDragMath.clampedOrigin(
            proposedX: proposedX, proposedY: proposedY,
            windowWidth: Double(window.frame.width),
            windowHeight: Double(window.frame.height),
            allowedArea: union, grabStripHeight: view.manualDragGrabStripHeight
        )
        return NSPoint(x: clamped.x, y: clamped.y)
    }

    private func contentView(_ handle: InteractiveWindowHandle) -> ScaledImageView {
        guard let view = handle.window.contentView as? ScaledImageView else {
            fatalError("content view is not a ScaledImageView")
        }
        return view
    }

    // MARK: - A. Shaped-window title-bar drag MOVES the window

    func testA_titlebarDragMovesWindow_andMouseUpClearsLatch() throws {
        let handle = try makeWindow(region: cornerCutRegion())
        let window = handle.window
        let view = contentView(handle)
        XCTAssertEqual(view.bounds.height, viewHeight, "view is the 275x116 content at scale 1")

        // The grab point: skin (130, 6) — inside the region, inside the title-bar
        // strip (y < 14), and NOT on any control. Precondition-pinned.
        XCTAssertTrue(
            ControlHitTest.hitsTitleBarDragArea(skinX: 130, skinY: 6),
            "chosen point must be a real title-bar drag point"
        )
        XCTAssertTrue(
            RegionHitTest.isInside(region: cornerCutRegion(), width: winW, height: winH, skinX: 130, skinY: 6),
            "chosen title-bar point is inside the region (a click would be delivered there)"
        )
        let anchor = view.convert(viewPoint(skinX: 130, skinY: 6), to: nil)

        // A drag with NO preceding mouse-down does nothing (no latch).
        window.setFrameOrigin(NSPoint(x: 500, y: 400))
        let restOrigin = window.frame.origin
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: anchor, window: window))
        XCTAssertEqual(window.frame.origin, restOrigin, "drag without a latched down must not move the window")

        // Reproduce the destination the manual drag will compute (same live cursor +
        // screen union the handler reads). A real NSWindow snaps its frame origin to
        // the backing-pixel grid, so use the window ITSELF as the snapping oracle:
        // set it to the raw target and read back the snapped value the handler will
        // also store for the same input.
        let rawExpected = expectedManualDragOrigin(anchor: anchor, view: view, window: window)
        window.setFrameOrigin(rawExpected)
        let expected = window.frame.origin

        // Start the window a known 123 x 77 away so the drag produces a real move.
        window.setFrameOrigin(NSPoint(x: expected.x + 123, y: expected.y + 77))
        let startOrigin = window.frame.origin
        XCTAssertNotEqual(startOrigin, expected, "window starts away from the drag destination")

        // mouse-DOWN in the title-bar strip latches the manual drag; the drag then
        // repositions the window to the tracked (backing-aligned) origin.
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: anchor, window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: anchor, window: window))
        XCTAssertEqual(window.frame.origin.x, expected.x, accuracy: 0.5, "manual drag moved X to the tracked origin")
        XCTAssertEqual(window.frame.origin.y, expected.y, accuracy: 0.5, "manual drag moved Y to the tracked origin")
        XCTAssertNotEqual(window.frame.origin, startOrigin, "the window actually moved")

        // mouse-UP clears the latch; a further drag must NOT keep moving it.
        let afterUp = window.frame.origin
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: anchor, window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: anchor, window: window))
        XCTAssertEqual(window.frame.origin, afterUp, "after mouse-up the latch is cleared: no further move")
    }

    // MARK: - B. Press in a CUT-OUT does NOT move the window

    func testB_pressInCutOutBelowTitlebarDoesNotMoveWindow() throws {
        let handle = try makeWindow(region: cornerCutRegion())
        let window = handle.window
        let view = contentView(handle)
        window.setFrameOrigin(NSPoint(x: 600, y: 500))
        let before = window.frame.origin

        // Skin (10, 30): OUTSIDE the region (transparent cut-out) AND below the
        // title-bar strip, so the manual-drag gate rejects it by geometry.
        XCTAssertFalse(
            RegionHitTest.isInside(region: cornerCutRegion(), width: winW, height: winH, skinX: 10, skinY: 30),
            "point is a cut-out"
        )
        XCTAssertFalse(
            ControlHitTest.hitsTitleBarDragArea(skinX: 10, skinY: 30),
            "cut-out below the strip is not a drag point"
        )
        let loc = view.convert(viewPoint(skinX: 10, skinY: 30), to: nil)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: loc, window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: loc, window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: loc, window: window))
        XCTAssertEqual(window.frame.origin, before, "a press-drag in a hole must never move the window")
    }

    // MARK: - B2. FINDING: a title-bar-band hole is guarded by hitTest, not the predicate

    /// Documented nuance surfaced by this exercise (NOT a defect). The manual-drag
    /// gate `hitsTitleBarDragArea` is region-AGNOSTIC: a cut-out that lands inside
    /// the title-bar y-band still satisfies it. So the guarantee that a drag can
    /// never START in such a hole is enforced UPSTREAM by `hitTest` (click-through
    /// returns nil there, so AppKit never delivers the mouse-down), not by the drag
    /// predicate. In real usage the event never reaches `mouseDown`; only a test
    /// calling `mouseDown` directly could bypass that gate. This pins the contract
    /// so a future change to either layer can't silently drop the guarantee.
    func testB2_titlebarBandHole_guardedByHitTestClickThrough() throws {
        let handle = try makeWindow(region: cornerCutRegion())
        let view = contentView(handle)

        // Skin (10, 6): a cut-out that lies INSIDE the title-bar y-band.
        XCTAssertFalse(
            RegionHitTest.isInside(region: cornerCutRegion(), width: winW, height: winH, skinX: 10, skinY: 6),
            "the hole is outside the region"
        )
        // The drag predicate alone would ACCEPT it as draggable (region-agnostic):
        XCTAssertTrue(
            ControlHitTest.hitsTitleBarDragArea(skinX: 10, skinY: 6),
            "the predicate is region-agnostic and would accept this hole"
        )
        // ...therefore the ONLY thing preventing a drag-in-hole is hitTest -> nil.
        let p = view.convert(viewPoint(skinX: 10, skinY: 6), to: view.superview)
        XCTAssertNil(view.hitTest(p), "click-through: the event is intercepted before it can start a drag")
    }

    // MARK: - C. hitTest: cut-out -> nil (click-through), interior -> the view

    func testC_hitTest_cutOutNil_interiorNonNil() throws {
        let handle = try makeWindow(region: cornerCutRegion())
        let view = contentView(handle)

        // Cut-out (top-left hole) -> nil so the click passes through.
        let cut = view.convert(viewPoint(skinX: 10, skinY: 6), to: view.superview)
        XCTAssertNil(view.hitTest(cut), "a cut-out point hit-tests to nil (click-through)")

        // Interior background -> the view itself (normal routing).
        let inside = view.convert(viewPoint(skinX: 130, skinY: 100), to: view.superview)
        XCTAssertIdentical(view.hitTest(inside), view, "an interior point routes to the view normally")
    }

    // MARK: - D. Unshaped window (no region.txt) regression

    func testD_unshapedWindow_regression() throws {
        let handle = try makeWindow(region: nil)
        let window = handle.window
        let view = contentView(handle)

        // The ~90% common rectangular path: default shadow + opaque backing, no mask.
        XCTAssertTrue(window.hasShadow, "unshaped keeps the default window shadow")
        XCTAssertTrue(window.isOpaque, "unshaped keeps the opaque backing")
        XCTAssertNil(view.layer?.mask, "unshaped installs no region mask layer")

        // No hitTest override -> every in-bounds point routes normally (non-nil).
        XCTAssertNil(view.regionContainsPoint, "unshaped installs no click-through override")
        for (x, y) in [(10, 6), (260, 110), (0, 0), (274, 115)] {
            let p = view.convert(viewPoint(skinX: x, skinY: y), to: view.superview)
            XCTAssertIdentical(view.hitTest(p), view, "in-bounds (\(x),\(y)) routes to the view")
        }

        // No manual-drag path; the unshaped title-bar drag uses AppKit's performDrag.
        XCTAssertNil(view.shouldManuallyDragWindow, "unshaped never wires the manual drag")
        XCTAssertNotNil(view.shouldDragWindow, "unshaped keeps the performDrag title-bar gate")
    }

    // MARK: - E. M1: a full-window rectangle region is treated as UNSHAPED

    func testE_fullRectRegion_treatedAsUnshaped() throws {
        // The shape decision itself: full coverage -> not a shape.
        XCTAssertNil(
            RegionMaskGeometry.shape(for: fullRectRegion(), width: winW, height: winH),
            "[Normal] 0,0 275,0 275,116 0,116 is full coverage -> unshaped"
        )

        let handle = try makeWindow(region: fullRectRegion())
        let window = handle.window
        let view = contentView(handle)

        XCTAssertTrue(window.hasShadow, "full-rect region keeps the default shadow")
        XCTAssertTrue(window.isOpaque, "full-rect region leaves isOpaque untouched")
        XCTAssertNil(view.layer?.mask, "full-rect region installs no mask layer")
        XCTAssertNil(view.shouldManuallyDragWindow, "full-rect region uses the unshaped drag path")
        XCTAssertNotNil(view.shouldDragWindow, "full-rect region keeps the performDrag gate")
        XCTAssertNil(view.regionContainsPoint, "full-rect region installs no click-through override")
    }

    // MARK: - S5. Click-through PRECONDITIONS (window-server behaviour, documented)

    /// Cross-window alpha click-through cannot be proven in-process — it is a
    /// window-server behaviour. This asserts the full set of necessary + sufficient
    /// PRECONDITIONS macOS alpha hit-testing needs, so the only remaining check is a
    /// live two-window click (owner eyeball):
    ///   1. `window.isOpaque == false`         — non-opaque backing;
    ///   2. `window.ignoresMouseEvents == false` AND the code never sets it true
    ///      (verified separately: `git grep ignoresMouseEvents` has no matches);
    ///   3. the backing/mask makes cut-out pixels alpha 0 — the coverage the
    ///      `CAShapeLayer` mask is built from EXCLUDES the cut-out and INCLUDES the
    ///      interior;
    ///   4. (from `testC`) `hitTest` returns nil in the cut-out.
    /// Combined, a click in a cut-out is caught by no part of this window and its
    /// pixels are transparent — the two conditions the window server needs to route
    /// the click to the window behind. The LIVE two-window pass-through is the one
    /// item that still needs the owner's eyeball.
    func testS5_clickThroughPreconditions_shapedWindow() throws {
        let region = cornerCutRegion()
        let handle = try makeWindow(region: region)
        let window = handle.window

        XCTAssertFalse(window.isOpaque, "precondition 1: non-opaque backing")
        XCTAssertFalse(window.ignoresMouseEvents, "precondition 2: mouse events are still delivered")
        XCTAssertFalse(window.hasShadow, "shaped window drops the rectangular shadow around cut-outs")

        // Precondition 3: the mask the shape is built from zeroes the cut-out.
        guard let shape = RegionMaskGeometry.shape(for: region, width: winW, height: winH) else {
            return XCTFail("corner-cut region must produce a shape")
        }
        XCTAssertEqual(shape.mask.count, winW * winH, "mask is the full canvas")
        XCTAssertFalse(shape.mask[6 * winW + 10], "cut-out pixel (10,6) is masked out -> alpha 0")
        XCTAssertTrue(shape.mask[100 * winW + 130], "interior pixel (130,100) is covered -> opaque")
    }
}
