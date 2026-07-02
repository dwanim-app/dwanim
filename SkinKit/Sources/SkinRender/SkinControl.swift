import Foundation

// MARK: - SkinControl
//
// The clickable transport/toggle controls of the classic main player window.
// Pure value type: no graphics framework, no platform geometry. It names WHICH
// control was hit; `ControlHitTest` maps a point to one of these.
//
// SCOPE: the transport row (previous/play/pause/stop/next), the two bottom-right
// toggles (shuffle/repeat), the EQ / PL window-toggle buttons, the eject button,
// and the title-bar minimize button. Sliders (volume/balance/seek) are NOT
// `SkinControl` cases — they are scrubbable regions, handled like the posbar via
// dedicated `ControlHitTest` region/value helpers — and the mono/stereo
// INDICATORS are display-only (no hit-test). The title-bar CLOSE button and the
// windowshade button are also not modelled here (see `ControlKind` notes / the
// deferred windowshade mode).

/// A clickable control on the classic main window.
///
/// Two flavors, distinguished by `kind`:
///   • TRANSPORT controls (`previous`/`play`/`pause`/`stop`/`next`/`toggleShuffle`/
///     `toggleRepeat`) map to a `PlayerCore` transport action via
///     `PlayerControl.apply`.
///   • HOST-ACTION controls (`eqButton`/`plButton`/`eject`/`minimize`) are NOT
///     transport — a click drives a host/window action (toggle the EQ / playlist
///     window, open a file, minimize the window). They are still `SkinControl`
///     cases so their hit rect derives from the SAME `MainWindowLayout` +
///     `SpriteCoordinates` single-source-of-truth as every other control; the
///     controller routes them to injected callbacks instead of `PlayerControl`.
public enum SkinControl: Sendable, Equatable, CaseIterable {
    case previous, play, pause, stop, next
    case toggleShuffle, toggleRepeat
    case eqButton, plButton, eject, minimize
}

// MARK: - Control kind

public extension SkinControl {

    /// Whether a control drives a `PlayerCore` TRANSPORT action (mapped by
    /// `PlayerControl.apply`) or a HOST/window action routed via an injected
    /// callback (EQ / PL window toggle, eject, minimize). Pure classification —
    /// the controller uses it to decide whether to call `PlayerControl.apply` or a
    /// host closure for a hit.
    enum Kind: Sendable, Equatable {
        case transport
        case hostAction
    }

    /// This control's kind. Transport for the five buttons + two toggles;
    /// host-action for the EQ / PL / eject / minimize buttons.
    var kind: Kind {
        switch self {
        case .previous, .play, .pause, .stop, .next, .toggleShuffle, .toggleRepeat:
            return .transport
        case .eqButton, .plButton, .eject, .minimize:
            return .hostAction
        }
    }
}

// MARK: - Sprite naming

public extension SkinControl {

    /// The sprite that draws this control, as a `(sheet, name)` pair.
    ///
    /// This is the SINGLE SOURCE OF TRUTH for control sprite names: both the
    /// hit-test layout lookup (`ControlHitTest`, released/static art) and the
    /// interactive pressed-button overlay select from this one table, so the two
    /// cannot drift apart.
    ///
    /// `pressed == false` yields the released/static sprite name (e.g. `play`,
    /// `shuffleOff`); `pressed == true` appends the `Pressed` suffix
    /// (`playPressed`, `shuffleOffPressed`) per the `SpriteCoordinates`
    /// convention.
    ///
    /// - Note: this overload always uses the control's OFF/released art. It is the
    ///   STATIC name used to derive the hit rect (`ControlHitTest`, where the OFF
    ///   sprite size is the canonical footprint) and to draw a transport button's
    ///   pressed state. To reflect a toggle's live on/off state in the live window,
    ///   use `spriteName(pressed:active:)`.
    func spriteName(pressed: Bool) -> (sheet: String, name: String) {
        let key = releasedSpriteKey
        return (key.sheet, pressed ? key.name + "Pressed" : key.name)
    }

    /// The sprite that draws this control reflecting a toggle's live on/off state.
    ///
    /// For the two toggles (`.toggleShuffle`, `.toggleRepeat`) an `active` of
    /// `true` selects the `*On` / `*OnPressed` art and `false` the
    /// `*Off` / `*OffPressed` art, so a lit shuffle/repeat shows its on sprite
    /// instead of always the off variant. For the five transport buttons `active`
    /// is ignored (they have no on/off state) and this is identical to
    /// `spriteName(pressed:)`.
    ///
    /// Pure naming only — no graphics framework, no live `PlayerCore` access. The
    /// caller passes the live state (`core.isShuffle`, `core.repeatMode != .off`)
    /// so this stays a unit-testable function of `(control, pressed, active)`.
    func spriteName(pressed: Bool, active: Bool) -> (sheet: String, name: String) {
        let base: (sheet: String, name: String)
        switch self {
        case .toggleShuffle:
            base = ("shufrep.bmp", active ? "shuffleOn" : "shuffleOff")
        case .toggleRepeat:
            base = ("shufrep.bmp", active ? "repeatOn" : "repeatOff")
        case .eqButton:
            // The EQ button lights (`eqButtonOn`) while the equalizer window is
            // open; otherwise it shows the off art.
            base = ("shufrep.bmp", active ? "eqButtonOn" : "eqButtonOff")
        case .plButton:
            // The PL button lights (`plButtonOn`) while the playlist window is open.
            base = ("shufrep.bmp", active ? "plButtonOn" : "plButtonOff")
        default:
            base = releasedSpriteKey
        }
        return (base.sheet, pressed ? base.name + "Pressed" : base.name)
    }

    /// The `(sheet, released-sprite-name)` backing this control. The released
    /// name is the control's default/static state; `spriteName(pressed:)` derives
    /// the pressed name from it.
    private var releasedSpriteKey: (sheet: String, name: String) {
        switch self {
        case .previous:      return ("cbuttons.bmp", "previous")
        case .play:          return ("cbuttons.bmp", "play")
        case .pause:         return ("cbuttons.bmp", "pause")
        case .stop:          return ("cbuttons.bmp", "stop")
        case .next:          return ("cbuttons.bmp", "next")
        case .toggleShuffle: return ("shufrep.bmp", "shuffleOff")
        case .toggleRepeat:  return ("shufrep.bmp", "repeatOff")
        // The EQ / PL toggles' default (released) state is OFF; the hit rect
        // derives from the OFF sprite's footprint, exactly like the shuffle/repeat
        // toggles derive from their `*Off` sprite. Their art lives in the bottom
        // band of shufrep.bmp (measured; NOT in titlebar.bmp).
        case .eqButton:      return ("shufrep.bmp", "eqButtonOff")
        case .plButton:      return ("shufrep.bmp", "plButtonOff")
        case .eject:         return ("cbuttons.bmp", "eject")
        case .minimize:      return ("titlebar.bmp", "minimize")
        }
    }
}
