import Foundation

// MARK: - SkinControl
//
// The clickable transport/toggle controls of the classic main player window.
// Pure value type: no graphics framework, no platform geometry. It names WHICH
// control was hit; `ControlHitTest` maps a point to one of these.
//
// SCOPE: the transport row (previous/play/pause/stop/next) and the two
// bottom-right toggles (shuffle/repeat). Sliders (volume/balance/seek), the
// title-bar window buttons (close/minimize/shade), and the mono/stereo
// indicators are NOT controls here — they are deferred to later increments.

/// A clickable control on the classic main window.
public enum SkinControl: Sendable, Equatable, CaseIterable {
    case previous, play, pause, stop, next
    case toggleShuffle, toggleRepeat
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
    /// - Note: the two toggles always use their OFF art here. Reflecting the live
    ///   on/off state (so a lit toggle uses the on / on-pressed sprite) is a
    ///   future refinement.
    // TODO: toggles — reflect live on/off state so a lit shuffle/repeat uses the
    //       `*On` / `*OnPressed` art instead of always the off variant.
    func spriteName(pressed: Bool) -> (sheet: String, name: String) {
        let key = releasedSpriteKey
        return (key.sheet, pressed ? key.name + "Pressed" : key.name)
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
        }
    }
}
