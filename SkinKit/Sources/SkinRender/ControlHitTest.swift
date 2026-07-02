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
    // (origin bottom-left, y increasing UPWARD) scaled by the PRESENTATION scale
    // (points per skin pixel — an integer like 1/2 or a fractional 1.5), while
    // the skin image is top-left origin (y down). These pure functions undo that
    // mapping so click routing can be unit-tested without a window: they are the
    // inverse of the forward draw map and carry NO graphics framework.

    /// Convert a view-space point (the NSView's non-flipped, bottom-left origin,
    /// scaled coordinates) to a skin-space point (top-left origin, unscaled
    /// pixels). Undoes the presentation `scale` (points per skin pixel, possibly
    /// fractional — e.g. 1.5) and flips y from the view's bottom-left origin to
    /// the skin's top-left origin:
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
        scale: Double
    ) -> (x: Int, y: Int) {
        let rawX = viewX / scale
        let rawY = (viewHeight - viewY) / scale
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
        scale: Double
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
        scale: Double
    ) -> (x: Double, y: Double) {
        (x: Double(skinX) * scale, y: viewHeight - Double(skinY) * scale)
    }

    // MARK: - Hit rect (public, for tests/debug)

    /// The hit rect for a control: its draw origin plus the matching sprite's size
    /// from `SpriteCoordinates`. Returns `nil` if either the origin or the sprite is
    /// absent (so the rect cannot be derived).
    ///
    /// ORIGIN SOURCE: TRANSPORT controls (and the two toggles) draw a composited
    /// sprite, so their origin is read from `MainWindowLayout.elements` (the static
    /// composite table). HOST-ACTION controls (EQ / PL / eject / minimize) read
    /// their origin from the standalone origins on `MainWindowLayout`
    /// (`eqButtonOrigin`, …). EQ / PL / eject ALSO have `elements` entries now
    /// (their OFF art is composited because real `main.bmp` faces are often blank
    /// there) — the element origins match the standalone origins, so either source
    /// yields the same rect; minimize stays hit-only (its art is part of the
    /// title-bar strip). Both flavors take the sprite SIZE from
    /// `SpriteCoordinates`, so the rect still follows a sprite tune in one place.
    public static func hitRect(
        for control: SkinControl
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        let key = layoutKey(for: control)

        guard let origin = origin(for: control, key: key) else {
            return nil
        }

        guard let sprite = SpriteCoordinates.mainWindow[key.sheet]?.first(where: {
            $0.name == key.sprite
        }) else {
            return nil
        }

        return (x: origin.x, y: origin.y, width: sprite.width, height: sprite.height)
    }

    /// The draw origin for a control. Transport/toggle controls read their origin
    /// from `MainWindowLayout.elements` (they are composited); host-action controls
    /// read it from the standalone origins on `MainWindowLayout` (kept equal to
    /// their `elements` entries where those exist — EQ / PL / eject). `nil` when a
    /// transport control has no `elements` entry (a sparse layout).
    private static func origin(
        for control: SkinControl,
        key: (sheet: String, sprite: String)
    ) -> (x: Int, y: Int)? {
        switch control.kind {
        case .transport:
            guard let element = MainWindowLayout.elements.first(where: {
                $0.sheet == key.sheet && $0.sprite == key.sprite
            }) else {
                return nil
            }
            return (x: element.x, y: element.y)
        case .hostAction:
            switch control {
            case .eqButton:  return MainWindowLayout.eqButtonOrigin
            case .plButton:  return MainWindowLayout.plButtonOrigin
            case .eject:     return MainWindowLayout.ejectOrigin
            case .minimize:  return MainWindowLayout.minimizeOrigin
            case .close:     return MainWindowLayout.closeOrigin
            default:         return nil // unreachable: all host actions handled above
            }
        }
    }

    // MARK: - Title-bar drag band (public)
    //
    // The classic main window is BORDERLESS (no OS chrome), so the skin's own
    // title-bar strip is the window's drag handle. The band's height derives from
    // the `titlebar.bmp`/`titleBarActive` sprite (the strip `MainWindowLayout`
    // composites at (0, 0)), so a sprite tune follows automatically. Buttons in
    // the strip (minimize, close) win over drag: a point on ANY control's hit
    // rect is NOT drag area — routing future title-bar controls out of the drag
    // band automatically.

    /// Height of the main window's title-bar strip, from the
    /// `titlebar.bmp/titleBarActive` sprite. Falls back to the canonical 14 when
    /// the sprite is absent so the band stays well-formed.
    public static func titleBarHeight() -> Int {
        SpriteCoordinates.mainWindow["titlebar.bmp"]?
            .first { $0.name == "titleBarActive" }?
            .height ?? 14
    }

    /// Whether a skin-space point lands in the title-bar DRAG band: inside the
    /// top strip (y in `0..<titleBarHeight()`, x on-window) and NOT on any
    /// control's hit rect (the minimize / close buttons win over drag).
    public static func hitsTitleBarDragArea(skinX: Int, skinY: Int) -> Bool {
        guard skinY >= 0, skinY < titleBarHeight(),
              skinX >= 0, skinX < MainWindowLayout.windowWidth else {
            return false
        }
        return control(atX: skinX, y: skinY) == nil
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

    // MARK: - Volume slider (public)
    //
    // The volume slider, like the posbar, is a SCRUBBABLE REGION, not a button:
    // it is NOT a `SkinControl` case and not in `control(atX:y:)`. Its geometry is
    // derived from the SAME single-source-of-truth tables — `MainWindowLayout`'s
    // `volume.bmp`/`level27` static element (the draw origin) plus the `level27`
    // sprite size from `SpriteCoordinates` — so a layout/sprite tune follows
    // automatically. The 28 stacked frames (`level0`..`level27`) bake the knob into
    // each frame, so there is no separate thumb sprite: the value is reflected by
    // SWAPPING which level frame is drawn (`volumeLevelFrame(forVolume:)`), and a
    // press/drag maps the cursor x to a `0...1` volume (`volumeFraction`).

    /// Number of volume level frames (`level0`..`level(count-1)`). The 28-frame
    /// classic volume sheet.
    public static let volumeLevelCount = 28

    /// The volume slider's track rect (skin space, top-left origin, unscaled),
    /// derived from the `volume.bmp`/`level27` static layout element + that
    /// sprite's size. `nil` when either the element or the sprite is absent.
    /// `level27` is the frame `MainWindowLayout` pins as the static default, so it
    /// is the canonical footprint (all 28 frames share the same 68x13 box).
    public static func volumeRect() -> (x: Int, y: Int, width: Int, height: Int)? {
        sliderRect(sheet: "volume.bmp", frame: "level27")
    }

    /// Whether a skin-space point lands on the volume slider region. `false` when
    /// the region cannot be derived. Half-open, like the posbar.
    public static func hitsVolume(skinX: Int, skinY: Int) -> Bool {
        hits(rect: volumeRect(), skinX: skinX, skinY: skinY)
    }

    /// Map a skin-space x (a press/drag on the volume slider) to a volume in
    /// `0...1`: the left edge of the track is `0` (silent) and the right edge is
    /// `1` (full). Clamps to the endpoints so a drag past either edge maps to
    /// `0` / `1`. `nil` when the region cannot be derived or has non-positive
    /// usable travel. The fraction is intended to flow into the finite-guarded
    /// `PlayerCore.setVolume`; this stays a pure integer/Double mapping.
    public static func volumeFraction(skinX: Int) -> Double? {
        sliderFraction(rect: volumeRect(), skinX: skinX)
    }

    /// The level frame name (`level0`..`level27`) to draw for a `0...1` volume:
    /// `round(volume * (count - 1))`, clamped, so `0` -> `level0`, `1` -> `level27`,
    /// `0.5` -> the middle frame. A non-finite volume is treated as `0`. This is the
    /// render-side inverse of `volumeFraction` — the controller swaps the composited
    /// frame to this one so the baked knob reflects the live volume.
    public static func volumeLevelFrame(forVolume volume: Double) -> String {
        "level\(levelIndex(forFraction: volume, count: volumeLevelCount))"
    }

    // MARK: - Balance slider (public)
    //
    // The balance slider mirrors the volume slider's baked-frame model, but its
    // value is a stereo PAN in `-1...1` centered at `0`, not a `0...1` magnitude.
    // 28 frames map across the range with the CENTER frame (`level13`/`level14`)
    // representing balanced; the left edge is full-left (`-1`), the right edge
    // full-right (`+1`). Geometry derives from the `balance.bmp`/`level13` static
    // element + the `level13` sprite size (38 wide, 13 tall — narrower than volume).

    /// Number of balance level frames. Same 28-frame shape as volume.
    public static let balanceLevelCount = 28

    /// The balance slider's track rect, derived from the `balance.bmp`/`level13`
    /// static layout element + that sprite's size. `level13` is the centered frame
    /// `MainWindowLayout` pins as the static default. `nil` when absent.
    public static func balanceRect() -> (x: Int, y: Int, width: Int, height: Int)? {
        sliderRect(sheet: "balance.bmp", frame: "level13")
    }

    /// Whether a skin-space point lands on the balance slider region. Half-open.
    public static func hitsBalance(skinX: Int, skinY: Int) -> Bool {
        hits(rect: balanceRect(), skinX: skinX, skinY: skinY)
    }

    /// Map a skin-space x (a press/drag on the balance slider) to a pan in
    /// `-1...1`: the left edge is `-1` (hard left), the CENTER is `0` (balanced),
    /// the right edge is `+1` (hard right). Computed as `2 * fraction - 1` over the
    /// `0...1` track fraction, clamped. `nil` when the region cannot be derived.
    /// Intended to flow into the finite-guarded `PlayerCore.setBalance`.
    public static func balanceFraction(skinX: Int) -> Double? {
        guard let fraction = sliderFraction(rect: balanceRect(), skinX: skinX) else {
            return nil
        }
        return min(max(2 * fraction - 1, -1), 1)
    }

    /// The level frame name (`level0`..`level27`) to draw for a `-1...1` pan: the
    /// pan is mapped back to a `0...1` fraction (`(pan + 1) / 2`) and then to a
    /// frame index, so `0` (centered) -> the middle frame, `-1` -> `level0`, `+1` ->
    /// `level27`. A non-finite pan is treated as centered (`0`). Render-side inverse
    /// of `balanceFraction`.
    public static func balanceLevelFrame(forBalance pan: Double) -> String {
        let safePan = pan.isFinite ? min(max(pan, -1), 1) : 0
        let fraction = (safePan + 1) / 2
        return "level\(levelIndex(forFraction: fraction, count: balanceLevelCount))"
    }

    // MARK: - Slider helpers (private, shared by volume + balance)

    /// A slider's track rect from its static layout element (draw origin) + the
    /// matching sprite size. `nil` when either is absent.
    private static func sliderRect(
        sheet: String, frame: String
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let element = MainWindowLayout.elements.first(where: {
            $0.sheet == sheet && $0.sprite == frame
        }) else {
            return nil
        }
        guard let sprite = SpriteCoordinates.mainWindow[sheet]?.first(where: {
            $0.name == frame
        }) else {
            return nil
        }
        return (x: element.x, y: element.y, width: sprite.width, height: sprite.height)
    }

    /// Half-open containment against an optional rect.
    private static func hits(
        rect: (x: Int, y: Int, width: Int, height: Int)?, skinX: Int, skinY: Int
    ) -> Bool {
        guard let rect else { return false }
        return skinX >= rect.x && skinX < rect.x + rect.width
            && skinY >= rect.y && skinY < rect.y + rect.height
    }

    /// Map a skin-space x to a `0...1` fraction across a slider rect's width. The
    /// left edge is `0`, the right edge is `1`; the usable travel is `width - 1` so
    /// the last in-bounds column maps to `1`. Clamps to the endpoints. `nil` when
    /// the rect is absent or its travel is non-positive.
    private static func sliderFraction(
        rect: (x: Int, y: Int, width: Int, height: Int)?, skinX: Int
    ) -> Double? {
        guard let rect else { return nil }
        let travel = rect.width - 1
        guard travel > 0 else { return nil }
        let offset = Double(skinX - rect.x)
        let fraction = offset / Double(travel)
        return min(max(fraction, 0), 1)
    }

    /// The level-frame INDEX for a `0...1` fraction over `count` frames:
    /// `round(fraction * (count - 1))`, clamped to `0...(count-1)`. A non-finite
    /// fraction is treated as `0`. Shared by volume/balance frame selection.
    private static func levelIndex(forFraction fraction: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let safe = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let index = Int((safe * Double(count - 1)).rounded())
        return min(max(index, 0), count - 1)
    }
}
