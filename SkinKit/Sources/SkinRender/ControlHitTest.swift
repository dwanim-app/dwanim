import Foundation
import SkinKit

// MARK: - ControlHitTest
//
// Pure point -> control hit-testing for the classic 275x116 main window. It
// needs NO graphics framework: a control's hit rect is just its draw position
// from `MainWindowLayout` plus the matching sprite's size from
// `SpriteCoordinates`, and hit-testing is a half-open bounds check. Both inputs
// stay top-left origin, x rightward / y downward, unscaled skin pixels.
//
// SINGLE SOURCE OF TRUTH: no coordinate is hardcoded here. Each rect is derived
// from `MainWindowLayout.elements` (the draw origin) + the matching
// `SpriteCoordinates.mainWindow` sprite (the size), so if those tables tune,
// hit-testing follows automatically.
//
// OVERLAP RESOLUTION: `control(atX:y:)` returns the FIRST control (in
// `SkinControl.allCases` order: previous, play, pause, stop, next,
// toggleShuffle, toggleRepeat) whose half-open rect contains the point. The
// classic transport buttons and toggles do not overlap (a test asserts this
// pairwise), so this rule only matters as a defined tie-break if a future layout
// edit introduces an overlap.

public enum ControlHitTest {

    // MARK: - Mapping
    //
    // Each control names the `MainWindowLayout` element (sheet + sprite) that
    // both positions it (element x/y) and sizes it (sprite width/height).

    /// The (sheet, sprite) that backs each control in `MainWindowLayout` /
    /// `SpriteCoordinates`. The sprite name is the control's default/static
    /// (released) state, taken from `SkinControl.spriteName(pressed:)` — the
    /// single source of truth shared with the interactive pressed-overlay, so the
    /// released/pressed name tables cannot drift.
    private static func layoutKey(for control: SkinControl) -> (sheet: String, sprite: String) {
        let key = control.spriteName(pressed: false)
        return (sheet: key.sheet, sprite: key.name)
    }

    // MARK: - Hit test (public)

    /// The control whose hit rect contains the point (skin space, top-left
    /// origin, unscaled), or `nil` if none. Rects are half-open: a point hits
    /// when `x in [rx, rx+rw)` and `y in [ry, ry+rh)`. If two rects overlapped,
    /// the first control in `SkinControl.allCases` order wins (see file header).
    public static func control(atX x: Int, y: Int) -> SkinControl? {
        for control in SkinControl.allCases {
            guard let rect = hitRect(for: control) else { continue }
            if x >= rect.x, x < rect.x + rect.width,
               y >= rect.y, y < rect.y + rect.height {
                return control
            }
        }
        return nil
    }

    // MARK: - View-space hit test (public)
    //
    // The interactive window draws the composed skin into a NON-flipped NSView
    // (origin bottom-left, y increasing UPWARD) scaled by an integer zoom, while
    // the skin image is top-left origin (y down). These pure functions undo that
    // mapping so click routing can be unit-tested without a window: they are the
    // inverse of the forward draw map and carry NO graphics framework.

    /// Convert a view-space point (the NSView's non-flipped, bottom-left origin,
    /// scaled coordinates) to a skin-space point (top-left origin, unscaled
    /// pixels). Undoes the integer `scale` and flips y from the view's
    /// bottom-left origin to the skin's top-left origin:
    ///   `x = floor(viewX / scale)`
    ///   `y = floor((viewHeight - viewY) / scale)`
    /// The result may land outside the skin bounds; the caller decides.
    ///
    /// A non-finite input (`NaN`/`±inf`, e.g. a degenerate AppKit event point or a
    /// zero scale yielding `inf`) is sanitised to `0` for that coordinate BEFORE
    /// the `Int` conversion — `Int(NaN.rounded(.down))` traps. This mirrors the
    /// project's finite-guard convention (`RegionCoverage`, `PlaybackMath`, the EQ
    /// `thumbGain`): a non-finite value yields a sane in-range default, never a
    /// crash.
    public static func skinPoint(
        viewX: Double,
        viewY: Double,
        viewHeight: Double,
        scale: Int
    ) -> (x: Int, y: Int) {
        let s = Double(scale)
        let rawX = viewX / s
        let rawY = (viewHeight - viewY) / s
        let x = rawX.isFinite ? Int(rawX.rounded(.down)) : 0
        let y = rawY.isFinite ? Int(rawY.rounded(.down)) : 0
        return (x, y)
    }

    /// The control under a view-space point: convenience that applies
    /// `skinPoint(...)` and then `control(atX:y:)`. Returns `nil` if no control's
    /// hit rect contains the mapped point.
    public static func control(
        atViewX viewX: Double,
        viewY: Double,
        viewHeight: Double,
        scale: Int
    ) -> SkinControl? {
        let point = skinPoint(viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale)
        return control(atX: point.x, y: point.y)
    }

    /// Convert a skin-space point (top-left origin, unscaled pixels) to a
    /// view/layer-space point (the NON-flipped, bottom-left origin, scaled
    /// coordinates the window draws into). This is the FORWARD draw map — the
    /// exact inverse of `skinPoint(...)`:
    ///   `x = skinX * scale`
    ///   `y = viewHeight - skinY * scale`
    ///
    /// The y-flip is REQUIRED and MUST match `skinPoint`'s flip. Click routing is
    /// verified correct with that flip (clicking the visible play button fires
    /// `.play`), so anything sharing this coordinate space — e.g. the region
    /// window mask — must use this same flip, or it lands vertically mirrored
    /// relative to where pixels and clicks actually go. (`CGContext.draw`
    /// auto-orients an image in a bottom-left context; a `CAShapeLayer` path does
    /// not, so the mask needs the flip applied explicitly here.)
    public static func viewPoint(
        skinX: Int,
        skinY: Int,
        viewHeight: Double,
        scale: Int
    ) -> (x: Double, y: Double) {
        let s = Double(scale)
        return (x: Double(skinX) * s, y: viewHeight - Double(skinY) * s)
    }

    // MARK: - Hit rect (public, for tests/debug)

    /// The hit rect for a control: its `MainWindowLayout` draw position plus the
    /// matching sprite's size from `SpriteCoordinates`. Returns `nil` if either
    /// the layout element or the sprite is absent (so the rect cannot be derived).
    public static func hitRect(
        for control: SkinControl
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        let key = layoutKey(for: control)

        guard let element = MainWindowLayout.elements.first(where: {
            $0.sheet == key.sheet && $0.sprite == key.sprite
        }) else {
            return nil
        }

        guard let sprite = SpriteCoordinates.mainWindow[key.sheet]?.first(where: {
            $0.name == key.sprite
        }) else {
            return nil
        }

        return (x: element.x, y: element.y, width: sprite.width, height: sprite.height)
    }

    // MARK: - Position / seek bar (public)
    //
    // The posbar is a slider, not a button, so it is NOT a `SkinControl` case and
    // has no entry in the `control(atX:y:)` button sweep. Its geometry is derived
    // from the SAME single-source-of-truth tables — `MainWindowLayout`'s
    // `posbar.bmp`/`track` draw origin plus the `track` sprite size from
    // `SpriteCoordinates` — so a layout/sprite tune follows automatically, exactly
    // like the button hit rects. The interactive controller checks this region on
    // a press/drag and maps the cursor x to a seek fraction via `posbarFraction`.

    /// The classic posbar track's rect (skin space, top-left origin, unscaled),
    /// derived from the `posbar.bmp`/`track` layout element + sprite size. `nil`
    /// when either the layout element or the sprite is absent.
    public static func posbarRect() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let element = MainWindowLayout.elements.first(where: {
            $0.sheet == "posbar.bmp" && $0.sprite == "track"
        }) else {
            return nil
        }
        guard let sprite = SpriteCoordinates.mainWindow["posbar.bmp"]?.first(where: {
            $0.name == "track"
        }) else {
            return nil
        }
        return (x: element.x, y: element.y, width: sprite.width, height: sprite.height)
    }

    /// The width of the posbar thumb (the draggable knob), from the
    /// `posbar.bmp`/`thumb` sprite. Used to bound thumb travel so the thumb's left
    /// edge never overruns the track's right edge. Falls back to the canonical 29
    /// when the sprite is absent, so the bar still behaves on a sparse skin.
    public static func posbarThumbWidth() -> Int {
        SpriteCoordinates.mainWindow["posbar.bmp"]?.first { $0.name == "thumb" }?.width ?? 29
    }

    /// Whether a skin-space point lands on the posbar track region. `false` when
    /// the region cannot be derived (missing layout/sprite). Half-open, like the
    /// button rects.
    public static func hitsPosbar(skinX: Int, skinY: Int) -> Bool {
        guard let rect = posbarRect() else { return false }
        return skinX >= rect.x && skinX < rect.x + rect.width
            && skinY >= rect.y && skinY < rect.y + rect.height
    }

    /// Map a skin-space x (a press/drag on the posbar) to a seek fraction in
    /// `0...1`, accounting for thumb width: a click positions the THUMB's left
    /// edge under the cursor, so the usable travel is `trackWidth - thumbWidth`
    /// (matching the classic slider, where dragging to the far right seats the
    /// thumb flush at the track's right edge rather than off it). Clamps to the
    /// endpoints so a drag past either edge maps to `0` / `1`.
    ///
    /// Returns `nil` when the posbar region cannot be derived or its usable travel
    /// is non-positive (so the caller does not seek). The fraction is intended to
    /// flow into the guarded `SeekMath.time(forFraction:duration:)`, which is the
    /// finite/zero-duration trap; this stays a pure integer/Double mapping.
    public static func posbarFraction(skinX: Int) -> Double? {
        guard let rect = posbarRect() else { return nil }
        let travel = rect.width - posbarThumbWidth()
        guard travel > 0 else { return nil }
        let offset = Double(skinX - rect.x)
        let fraction = offset / Double(travel)
        return min(max(fraction, 0), 1)
    }

    /// The thumb's draw origin (top-left, skin space) for a live seek `fraction`
    /// (`0...1`). The thumb's left edge travels `trackWidth - thumbWidth` across
    /// the track and shares the track's y. `nil` when the posbar region cannot be
    /// derived. A non-finite `fraction` is treated as `0`.
    ///
    /// This is the INVERSE of `posbarFraction` and the position the live thumb
    /// sprite is drawn at, so a press at fraction f draws the thumb where a press
    /// there would seat it.
    public static func posbarThumbOrigin(fraction: Double) -> (x: Int, y: Int)? {
        guard let rect = posbarRect() else { return nil }
        let travel = max(0, rect.width - posbarThumbWidth())
        let safeFraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let x = rect.x + Int((safeFraction * Double(travel)).rounded())
        return (x: x, y: rect.y)
    }
}
