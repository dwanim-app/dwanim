import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure control hit-testing for the classic main window. Expected
/// hit rects are derived in-test from `MainWindowLayout` (where a control draws)
/// plus `SpriteCoordinates` (the sprite's size), so a layout/sprite tune updates
/// the test's premise automatically rather than silently invalidating a baked-in
/// magic number. No graphics framework is touched.
final class ControlHitTestTests: XCTestCase {

    // MARK: - Helpers

    /// The (sheet, sprite) layout key + sprite name backing each control, mirrored
    /// from `ControlHitTest`'s mapping. Used only to DERIVE expected rects from the
    /// SkinKit data — the test does not hardcode pixel coordinates.
    private static let mapping: [SkinControl: (sheet: String, sprite: String)] = [
        .previous:      ("cbuttons.bmp", "previous"),
        .play:          ("cbuttons.bmp", "play"),
        .pause:         ("cbuttons.bmp", "pause"),
        .stop:          ("cbuttons.bmp", "stop"),
        .next:          ("cbuttons.bmp", "next"),
        .toggleShuffle: ("shufrep.bmp", "shuffleOff"),
        .toggleRepeat:  ("shufrep.bmp", "repeatOff")
    ]

    /// Expected hit rect for a control, derived from the layout element (x, y) and
    /// the matching sprite's (width, height) — the single source of truth.
    private func expectedRect(
        for control: SkinControl
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let key = Self.mapping[control]!
        let element = MainWindowLayout.elements.first {
            $0.sheet == key.sheet && $0.sprite == key.sprite
        }
        guard let element else {
            XCTFail("No layout element for \(control) (\(key))")
            return (0, 0, 0, 0)
        }
        let rects = SpriteCoordinates.mainWindow[key.sheet]
        let sprite = rects?.first { $0.name == key.sprite }
        guard let sprite else {
            XCTFail("No sprite \(key.sprite) in \(key.sheet)")
            return (0, 0, 0, 0)
        }
        return (element.x, element.y, sprite.width, sprite.height)
    }

    // MARK: - Center of each control hits it

    func testCenterOfEachControlReturnsThatControl() {
        for control in SkinControl.allCases {
            let rect = expectedRect(for: control)
            let cx = rect.x + rect.width / 2
            let cy = rect.y + rect.height / 2
            XCTAssertEqual(
                ControlHitTest.control(atX: cx, y: cy),
                control,
                "center (\(cx),\(cy)) of \(control) should hit \(control)"
            )
        }
    }

    // MARK: - Half-open boundary
    //
    // Boundary checks against a control's OWN rect via `ControlHitTest.hitRect`
    // (the rect under test), so we assert the half-open containment rule directly
    // without depending on `control(atX:)`'s cross-control resolution — see
    // `testToggleOverlapResolvesToFirstInOrder` for the one provisional overlap.

    func testTopLeftCornerIsInsideAndPixelLeftOrAboveIsOutside() {
        for control in SkinControl.allCases {
            let rect = ControlHitTest.hitRect(for: control)!

            // Top-left corner is inside (half-open lower bound is inclusive).
            XCTAssertTrue(contains(rect, x: rect.x, y: rect.y),
                          "top-left (\(rect.x),\(rect.y)) of \(control) should be inside its rect")

            // One pixel to the left of the top-left corner is outside.
            XCTAssertFalse(contains(rect, x: rect.x - 1, y: rect.y),
                           "pixel left of \(control)'s top-left should be outside its rect")

            // One pixel above the top-left corner is outside.
            XCTAssertFalse(contains(rect, x: rect.x, y: rect.y - 1),
                           "pixel above \(control)'s top-left should be outside its rect")
        }
    }

    /// Half-open containment test against a single rect.
    private func contains(
        _ rect: (x: Int, y: Int, width: Int, height: Int),
        x: Int,
        y: Int
    ) -> Bool {
        x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
    }

    func testRightAndBottomEdgesAreExclusive() {
        for control in SkinControl.allCases {
            let rect = expectedRect(for: control)

            // The pixel at the right edge (x + width) is outside (half-open).
            XCTAssertNotEqual(
                ControlHitTest.control(atX: rect.x + rect.width, y: rect.y),
                control,
                "right edge x+width of \(control) should be exclusive"
            )

            // The pixel at the bottom edge (y + height) is outside (half-open).
            XCTAssertNotEqual(
                ControlHitTest.control(atX: rect.x, y: rect.y + rect.height),
                control,
                "bottom edge y+height of \(control) should be exclusive"
            )

            // The last inside pixel (x+width-1, y+height-1) IS this control.
            XCTAssertEqual(
                ControlHitTest.control(atX: rect.x + rect.width - 1, y: rect.y + rect.height - 1),
                control,
                "last inside pixel of \(control) should hit it"
            )
        }
    }

    // MARK: - View-space coordinate transform (click routing)
    //
    // The interactive window draws the composed skin into a NON-flipped NSView
    // (origin bottom-left, y UP) scaled by an integer zoom; the skin image is
    // top-left origin (y DOWN). `ControlHitTest.skinPoint(...)` is the inverse of
    // that draw map. These tests pin click routing so a future y-flip or scale
    // regression FAILS here — it cannot be caught by clicking a real window.
    //
    // Forward map (the click point a press on a skin pixel CENTER produces), the
    // exact inverse of `skinPoint`:
    //   viewX = (skinX + 0.5) * scale
    //   viewY = viewHeight - (skinY + 0.5) * scale       (y-flip)
    //   viewHeight = MainWindowLayout.windowHeight * scale  (= 116 * scale)
    // Feeding that point back through `control(atViewX:...)` must return the
    // control whose rect center we started from.

    /// The view-space click point that lands on the CENTER of skin pixel
    /// `(skinX, skinY)` at this `scale` — the forward map (inverse of `skinPoint`).
    private func viewPoint(
        skinX: Int,
        skinY: Int,
        scale: Int
    ) -> (viewX: Double, viewY: Double, viewHeight: Double) {
        let viewHeight = Double(MainWindowLayout.windowHeight * scale)
        let viewX = (Double(skinX) + 0.5) * Double(scale)
        let viewY = viewHeight - (Double(skinY) + 0.5) * Double(scale)
        return (viewX, viewY, viewHeight)
    }

    /// For a representative spread of controls — `.play`, `.next` (same row) and
    /// `.toggleShuffle` (a different row, lower-right) — take the control's hit
    /// rect CENTER in skin space, map it forward to the view-space point a click
    /// there would produce, feed that back through `control(atViewX:...)`, and
    /// assert it round-trips to the same control. Exercised at scale 1 and 2.
    func testViewSpaceClickRoundTripsToControlCenter() {
        let controls: [SkinControl] = [.play, .next, .toggleShuffle]
        for scale in [1, 2] {
            for control in controls {
                let rect = expectedRect(for: control)
                let centerX = rect.x + rect.width / 2
                let centerY = rect.y + rect.height / 2

                let point = viewPoint(skinX: centerX, skinY: centerY, scale: scale)

                // Sanity: the forward map's view point inverts back to the skin
                // pixel we started from (no off-by-one in the transform itself).
                let backToSkin = ControlHitTest.skinPoint(
                    viewX: point.viewX,
                    viewY: point.viewY,
                    viewHeight: point.viewHeight,
                    scale: scale
                )
                XCTAssertEqual(backToSkin.x, centerX, "scale \(scale): skinPoint x for \(control)")
                XCTAssertEqual(backToSkin.y, centerY, "scale \(scale): skinPoint y for \(control)")

                // The whole click route resolves to the control we aimed at.
                XCTAssertEqual(
                    ControlHitTest.control(
                        atViewX: point.viewX,
                        viewY: point.viewY,
                        viewHeight: point.viewHeight,
                        scale: scale
                    ),
                    control,
                    "scale \(scale): view-space click on \(control)'s center should route to it"
                )
            }
        }
    }

    /// A direct check of the y-flip and scale undo against hand-worked values, so
    /// a regression in the formula (not just the round-trip) is caught. At scale
    /// 2 with a 232-tall view (116 * 2): a click near the top of the view maps to
    /// a small skin y; a click near the bottom maps to a large skin y.
    func testSkinPointUndoesScaleAndFlipsY() {
        // viewHeight = 116 * 2 = 232.
        let viewHeight = 232.0

        // Bottom-left of the view (viewY small) is the BOTTOM of the skin (large y).
        let bottomLeft = ControlHitTest.skinPoint(viewX: 0, viewY: 0, viewHeight: viewHeight, scale: 2)
        XCTAssertEqual(bottomLeft.x, 0)
        XCTAssertEqual(bottomLeft.y, 116, "viewY 0 (bottom) flips to skin bottom row")

        // Top-left of the view (viewY == viewHeight) is the TOP of the skin (y 0).
        let topLeft = ControlHitTest.skinPoint(
            viewX: 0, viewY: viewHeight, viewHeight: viewHeight, scale: 2
        )
        XCTAssertEqual(topLeft.x, 0)
        XCTAssertEqual(topLeft.y, 0, "viewY == height (top) flips to skin top row")

        // A point 10 view-pts right and 10 down-from-top, scale 2: x = floor(10/2) = 5,
        // y = floor((232 - 222)/2) = floor(10/2) = 5.
        let inner = ControlHitTest.skinPoint(
            viewX: 10, viewY: viewHeight - 10, viewHeight: viewHeight, scale: 2
        )
        XCTAssertEqual(inner.x, 5, "x = floor(viewX/scale)")
        XCTAssertEqual(inner.y, 5, "y = floor((viewHeight - viewY)/scale)")
    }

    // MARK: - skinPoint finite guard (non-finite input must not trap)
    //
    // `skinPoint` converts external Doubles (an AppKit event point, a view height)
    // to Int via `Int((v/scale).rounded(.down))`, which TRAPS on a non-finite
    // value (`Int(NaN.rounded(.down))` is a fatal error). A degenerate event point
    // (NaN/±inf) must yield a sane in-range coordinate, never a crash — mirroring
    // the project's finite-guard convention elsewhere.

    /// A non-finite `viewX`, `viewY`, or `viewHeight` (NaN, +inf, -inf) returns a
    /// sane finite skin point (0 for the affected coordinate) instead of trapping.
    func testSkinPointWithNonFiniteInputDoesNotTrap() {
        let viewHeight = 232.0
        let nonFinite: [Double] = [.nan, .infinity, -.infinity]

        for bad in nonFinite {
            // Bad viewX -> x sanitised to 0; the finite y is still computed normally.
            let px = ControlHitTest.skinPoint(
                viewX: bad, viewY: 0, viewHeight: viewHeight, scale: 2
            )
            XCTAssertEqual(px.x, 0, "non-finite viewX (\(bad)) -> x 0")
            XCTAssertEqual(px.y, 116, "the finite y is still computed (viewY 0 -> bottom)")

            // Bad viewY -> y sanitised to 0; the finite x is still computed.
            let py = ControlHitTest.skinPoint(
                viewX: 10, viewY: bad, viewHeight: viewHeight, scale: 2
            )
            XCTAssertEqual(py.x, 5, "the finite x is still computed (floor(10/2))")
            XCTAssertEqual(py.y, 0, "non-finite viewY (\(bad)) -> y 0")

            // Bad viewHeight feeds the y term -> y sanitised to 0.
            let ph = ControlHitTest.skinPoint(
                viewX: 10, viewY: 0, viewHeight: bad, scale: 2
            )
            XCTAssertEqual(ph.x, 5, "x unaffected by a bad viewHeight")
            XCTAssertEqual(ph.y, 0, "non-finite viewHeight (\(bad)) -> y 0")
        }

        // All three non-finite at once still returns a finite (0,0), no trap.
        let all = ControlHitTest.skinPoint(
            viewX: .nan, viewY: .infinity, viewHeight: -.infinity, scale: 2
        )
        XCTAssertEqual(all.x, 0)
        XCTAssertEqual(all.y, 0)
    }

    // MARK: - viewPoint (forward map; region-mask orientation guard)

    /// `viewPoint` is the FORWARD draw map and MUST be the exact inverse of
    /// `skinPoint` (including the y-flip). The region window mask relies on this:
    /// if it didn't flip while clicks do, the silhouette would be vertically
    /// mirrored. Skin row 0 must map to the visual TOP (high y in the bottom-left
    /// view), and a skin pixel must round-trip back through `skinPoint`.
    func testViewPointIsInverseOfSkinPointWithYFlip() {
        let viewHeight = 232.0 // 116px window at scale 2

        // Skin top (row 0) -> visual top -> HIGH y (== viewHeight), not 0.
        let top = ControlHitTest.viewPoint(skinX: 0, skinY: 0, viewHeight: viewHeight, scale: 2)
        XCTAssertEqual(top.x, 0, accuracy: 1e-9)
        XCTAssertEqual(top.y, viewHeight, accuracy: 1e-9, "skin row 0 maps to the visual top (high y)")

        // Skin bottom (row 116) -> view y 0.
        let bottom = ControlHitTest.viewPoint(skinX: 0, skinY: 116, viewHeight: viewHeight, scale: 2)
        XCTAssertEqual(bottom.y, 0, accuracy: 1e-9)

        // Round-trip interior skin pixels: viewPoint(corner) then sample inside the
        // pixel cell (+1 view-pt) and map back with skinPoint.
        for (sx, sy) in [(10, 5), (137, 58), (274, 115)] {
            let vp = ControlHitTest.viewPoint(skinX: sx, skinY: sy, viewHeight: viewHeight, scale: 2)
            let back = ControlHitTest.skinPoint(
                viewX: vp.x + 1, viewY: vp.y - 1, viewHeight: viewHeight, scale: 2
            )
            XCTAssertEqual(back.x, sx, "x round-trip for (\(sx),\(sy))")
            XCTAssertEqual(back.y, sy, "y round-trip for (\(sx),\(sy))")
        }
    }

    // MARK: - Misses

    func testPointOutsideEveryControlReturnsNil() {
        // (0,0) is in the title bar, where no transport/toggle control lives.
        XCTAssertNil(ControlHitTest.control(atX: 0, y: 0))

        // The middle of the song-title display area (upper strip) is not a control.
        XCTAssertNil(
            ControlHitTest.control(
                atX: MainWindowLayout.titleTextOrigin.x + 10,
                y: MainWindowLayout.titleTextOrigin.y
            )
        )

        // A point far below the window is not a control.
        XCTAssertNil(ControlHitTest.control(atX: 0, y: MainWindowLayout.windowHeight + 50))

        // Negative coordinates are not a control.
        XCTAssertNil(ControlHitTest.control(atX: -5, y: -5))
    }

    // MARK: - hitRect(for:)

    func testHitRectMatchesDerivedRectForEachControl() {
        for control in SkinControl.allCases {
            let expected = expectedRect(for: control)
            let actual = ControlHitTest.hitRect(for: control)
            XCTAssertNotNil(actual, "hitRect for \(control) should be non-nil")
            guard let actual else { continue }
            XCTAssertEqual(actual.x, expected.x, "x for \(control)")
            XCTAssertEqual(actual.y, expected.y, "y for \(control)")
            XCTAssertEqual(actual.width, expected.width, "width for \(control)")
            XCTAssertEqual(actual.height, expected.height, "height for \(control)")
        }
    }

    func testHitRectsHavePositiveSizeAndFitWindow() {
        for control in SkinControl.allCases {
            guard let rect = ControlHitTest.hitRect(for: control) else {
                XCTFail("hitRect for \(control) should be non-nil")
                continue
            }
            XCTAssertGreaterThan(rect.width, 0, "width > 0 for \(control)")
            XCTAssertGreaterThan(rect.height, 0, "height > 0 for \(control)")
            XCTAssertGreaterThanOrEqual(rect.x, 0, "x >= 0 for \(control)")
            XCTAssertGreaterThanOrEqual(rect.y, 0, "y >= 0 for \(control)")
            XCTAssertLessThanOrEqual(
                rect.x + rect.width,
                MainWindowLayout.windowWidth,
                "right edge within window for \(control)"
            )
            XCTAssertLessThanOrEqual(
                rect.y + rect.height,
                MainWindowLayout.windowHeight,
                "bottom edge within window for \(control)"
            )
        }
    }

    // MARK: - Overlaps

    /// Whether two half-open rects overlap (on both axes).
    private func rectsOverlap(
        _ a: (x: Int, y: Int, width: Int, height: Int),
        _ b: (x: Int, y: Int, width: Int, height: Int)
    ) -> Bool {
        let xOverlap = a.x < b.x + b.width && b.x < a.x + a.width
        let yOverlap = a.y < b.y + b.height && b.y < a.y + a.height
        return xOverlap && yOverlap
    }

    /// The transport-button row (previous/play/pause/stop/next) must never
    /// overlap — guards against a future `cbuttons.bmp` layout edit. The brief
    /// states these classic buttons don't overlap.
    func testTransportButtonsDoNotOverlap() {
        let transport: [SkinControl] = [.previous, .play, .pause, .stop, .next]
        for i in 0..<transport.count {
            for j in (i + 1)..<transport.count {
                let a = ControlHitTest.hitRect(for: transport[i])!
                let b = ControlHitTest.hitRect(for: transport[j])!
                XCTAssertFalse(
                    rectsOverlap(a, b),
                    "\(transport[i]) \(a) overlaps \(transport[j]) \(b)"
                )
            }
        }
    }

    /// In the current PROVISIONAL `shufrep.bmp` layout the shuffle (x 164, w 47)
    /// and repeat (x 210, w 28) toggles overlap by a single pixel column at
    /// x = 210 (164 + 47 = 211 > 210). This is the documented overlap-resolution
    /// path: `control(atX:y:)` returns the FIRST control in `SkinControl.allCases`
    /// order, so the shared column resolves to `.toggleShuffle`. If the layout is
    /// later tuned so the toggles no longer overlap, this test should be revisited
    /// (and `testTransportButtonsDoNotOverlap` extended to all controls).
    // MARK: - Posbar (seek bar) region + fraction mapping
    //
    // The posbar is a slider, not a button: it is NOT in `control(atX:y:)`. Its
    // geometry is derived from the SAME tables as the button rects (the
    // `posbar.bmp`/`track` element + sprite), so these tests derive the expected
    // rect rather than hardcoding it, and pin the pure x<->fraction mapping that
    // feeds `SeekMath`.

    /// The posbar track rect, derived from the layout element + `track` sprite —
    /// the single source of truth the production code uses.
    private func expectedPosbarRect() -> (x: Int, y: Int, width: Int, height: Int) {
        let element = MainWindowLayout.elements.first {
            $0.sheet == "posbar.bmp" && $0.sprite == "track"
        }
        guard let element else {
            XCTFail("No posbar.bmp/track layout element")
            return (0, 0, 0, 0)
        }
        let sprite = SpriteCoordinates.mainWindow["posbar.bmp"]?.first { $0.name == "track" }
        guard let sprite else {
            XCTFail("No posbar.bmp/track sprite")
            return (0, 0, 0, 0)
        }
        return (element.x, element.y, sprite.width, sprite.height)
    }

    func testPosbarRectMatchesDerivedRect() {
        let expected = expectedPosbarRect()
        let actual = ControlHitTest.posbarRect()
        XCTAssertNotNil(actual, "posbarRect should be non-nil")
        guard let actual else { return }
        XCTAssertEqual(actual.x, expected.x, "posbar x")
        XCTAssertEqual(actual.y, expected.y, "posbar y")
        XCTAssertEqual(actual.width, expected.width, "posbar width")
        XCTAssertEqual(actual.height, expected.height, "posbar height")
    }

    func testPosbarRectHasPositiveSizeAndFitsWindow() {
        guard let rect = ControlHitTest.posbarRect() else {
            XCTFail("posbarRect should be non-nil")
            return
        }
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertGreaterThanOrEqual(rect.x, 0)
        XCTAssertGreaterThanOrEqual(rect.y, 0)
        XCTAssertLessThanOrEqual(rect.x + rect.width, MainWindowLayout.windowWidth)
        XCTAssertLessThanOrEqual(rect.y + rect.height, MainWindowLayout.windowHeight)
    }

    /// The thumb width is the real `thumb` sprite width (29 canonical), and the
    /// usable travel (`trackWidth - thumbWidth`) must be positive so a drag spans
    /// a real range.
    func testPosbarThumbWidthAndTravelArePositive() {
        let rect = expectedPosbarRect()
        let thumbW = ControlHitTest.posbarThumbWidth()
        XCTAssertGreaterThan(thumbW, 0, "thumb width > 0")
        XCTAssertGreaterThan(rect.width - thumbW, 0, "usable travel (track - thumb) > 0")
    }

    func testHitsPosbarInsideAndOutside() {
        let rect = expectedPosbarRect()
        // Inside: top-left corner and the center.
        XCTAssertTrue(ControlHitTest.hitsPosbar(skinX: rect.x, skinY: rect.y),
                      "top-left corner is inside the posbar")
        XCTAssertTrue(
            ControlHitTest.hitsPosbar(skinX: rect.x + rect.width / 2, skinY: rect.y + rect.height / 2),
            "center is inside the posbar"
        )
        // Half-open: right and bottom edges are exclusive; a pixel left/above is out.
        XCTAssertFalse(ControlHitTest.hitsPosbar(skinX: rect.x + rect.width, skinY: rect.y),
                       "right edge x+width is exclusive")
        XCTAssertFalse(ControlHitTest.hitsPosbar(skinX: rect.x, skinY: rect.y + rect.height),
                       "bottom edge y+height is exclusive")
        XCTAssertFalse(ControlHitTest.hitsPosbar(skinX: rect.x - 1, skinY: rect.y),
                       "a pixel left of the track is outside")
        // A transport button row (y=88) is well below the posbar (y=72), so the
        // posbar and buttons do not collide.
        XCTAssertFalse(ControlHitTest.hitsPosbar(skinX: 16, skinY: 88),
                       "the play-button row is not the posbar")
    }

    /// `posbarFraction` clamps to `0...1` at the endpoints and is monotonic in x:
    /// the left edge maps to 0, a full thumb-width past the right of travel maps to
    /// 1, and a drag past either edge clamps rather than running off the track.
    func testPosbarFractionEndpointsAndClamping() {
        let rect = expectedPosbarRect()
        let travel = rect.width - ControlHitTest.posbarThumbWidth()

        // Left edge -> 0.
        XCTAssertEqual(ControlHitTest.posbarFraction(skinX: rect.x)!, 0, accuracy: 1e-9)
        // Far end of usable travel -> 1.
        XCTAssertEqual(ControlHitTest.posbarFraction(skinX: rect.x + travel)!, 1, accuracy: 1e-9)
        // Midpoint of travel -> ~0.5.
        XCTAssertEqual(
            ControlHitTest.posbarFraction(skinX: rect.x + travel / 2)!, 0.5, accuracy: 0.02,
            "midpoint of travel is ~half"
        )
        // Past the left -> clamps to 0; past the right -> clamps to 1.
        XCTAssertEqual(ControlHitTest.posbarFraction(skinX: rect.x - 100)!, 0, accuracy: 1e-9)
        XCTAssertEqual(ControlHitTest.posbarFraction(skinX: rect.x + rect.width + 100)!, 1, accuracy: 1e-9)
    }

    /// `posbarThumbOrigin` is the inverse of `posbarFraction`: a fraction maps to a
    /// thumb x within the track, 0 seats at the track left, 1 seats the thumb flush
    /// at the track's right edge (its left edge at `trackRight - thumbWidth`), and
    /// the y equals the track y. A non-finite fraction is treated as 0.
    func testPosbarThumbOriginInverse() {
        let rect = expectedPosbarRect()
        let thumbW = ControlHitTest.posbarThumbWidth()

        let atZero = ControlHitTest.posbarThumbOrigin(fraction: 0)
        XCTAssertEqual(atZero?.x, rect.x, "fraction 0 seats the thumb at the track left")
        XCTAssertEqual(atZero?.y, rect.y, "thumb shares the track y")

        let atOne = ControlHitTest.posbarThumbOrigin(fraction: 1)
        XCTAssertEqual(atOne?.x, rect.x + (rect.width - thumbW),
                       "fraction 1 seats the thumb flush at the track right")
        // The thumb's right edge never overruns the track's right edge.
        XCTAssertLessThanOrEqual((atOne?.x ?? 0) + thumbW, rect.x + rect.width,
                                 "thumb right edge stays within the track")

        // Non-finite fraction is treated as 0 (no trap, sane default).
        let nan = ControlHitTest.posbarThumbOrigin(fraction: .nan)
        XCTAssertEqual(nan?.x, rect.x, "non-finite fraction -> thumb at left")

        // Out-of-range fractions clamp.
        XCTAssertEqual(ControlHitTest.posbarThumbOrigin(fraction: -5)?.x, rect.x)
        XCTAssertEqual(ControlHitTest.posbarThumbOrigin(fraction: 5)?.x, rect.x + (rect.width - thumbW))
    }

    /// Round-trip: a thumb origin produced for a fraction, read back through
    /// `posbarFraction` at that thumb-left x, returns approximately the same
    /// fraction (within one travel pixel of rounding).
    func testPosbarFractionThumbOriginRoundTrip() {
        let rect = expectedPosbarRect()
        let travel = Double(rect.width - ControlHitTest.posbarThumbWidth())
        for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
            guard let origin = ControlHitTest.posbarThumbOrigin(fraction: f),
                  let back = ControlHitTest.posbarFraction(skinX: origin.x) else {
                XCTFail("posbar round-trip nil for fraction \(f)")
                continue
            }
            XCTAssertEqual(back, f, accuracy: 1.0 / travel + 1e-9, "round-trip fraction \(f)")
        }
    }

    func testToggleOverlapResolvesToFirstInOrder() {
        let shuffle = ControlHitTest.hitRect(for: .toggleShuffle)!
        let repeatRect = ControlHitTest.hitRect(for: .toggleRepeat)!

        guard rectsOverlap(shuffle, repeatRect) else {
            // Layout was tuned apart: nothing to resolve. Treat as informational.
            return
        }

        // The overlap is the column at repeat's left edge, shared with shuffle.
        let overlapX = repeatRect.x
        XCTAssertTrue(
            contains(shuffle, x: overlapX, y: repeatRect.y),
            "expected the overlap column to lie inside the shuffle rect"
        )
        // `.toggleShuffle` precedes `.toggleRepeat` in allCases order, so it wins.
        XCTAssertEqual(
            ControlHitTest.control(atX: overlapX, y: repeatRect.y),
            .toggleShuffle,
            "overlap column should resolve to the first control in order"
        )
    }
}
