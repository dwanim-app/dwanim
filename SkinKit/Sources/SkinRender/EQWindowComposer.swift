import Foundation
import SkinKit

// MARK: - EQWindowComposer
//
// Pure RGBA8 compositor for the classic 275x116 equalizer (EQ) window face. Like
// `MainWindowComposer`, it needs NO graphics framework: compositing is just
// copying sprite pixels onto a copy of the background buffer at each control's
// (x, y), all in `DecodedBitmap`'s top-left-origin RGBA8 space (no vertical
// flip). Every blit goes through the shared `SkinCanvas.overlay`, which clips to
// bounds and skips size-inconsistent sprites, so missing/malformed control
// sprites are tolerated and no write ever lands out of range.
//
// MODULE DEPENDENCY NOTE: `compose` takes the EQ state as RAW values
// (`enabled`, `preamp`, `bands`) rather than the `PlayerCore.EQState` type,
// because `SkinRender` depends only on `SkinKit` — NOT on `PlayerCore`. Threading
// the state in as plain `Bool`/`Double` keeps the module graph clean (the caller
// in the platform shell, which already has `PlayerCore`, unpacks `EQState` into
// these arguments). The values follow the same contract `EQState` enforces: gains
// are dB, sanitised/clamped to `±12 dB` by `EQWindowLayout.thumbTopY`.
//
// DEFERRED (documented, not drawn here):
//   * the colored band-graph response CURVE line over `EQWindowLayout.graphFrame`
//     (its per-row color gradient is under-pinned in `SpriteCoordinates`);
//   * the PRESET / status text in `EQWindowLayout.presetDisplayOrigin` (drawn
//     from the bitmap font at a later increment);
//   * the AUTO on-state (no auto-preset flag is modelled yet — AUTO is drawn OFF);
//   * the `eq_ex.bmp` windowshade (rolled-up) variant.

public enum EQWindowComposer {

    // MARK: - Compose

    /// Composite the equalizer window into a single RGBA8 bitmap (275x116):
    /// start from a COPY of `eqmain.bmp/background`, overlay the slider thumb for
    /// the preamp and each of the ten bands at its column x and gain-derived y,
    /// then overlay the ON button (on/off per `enabled`) and the AUTO button
    /// (always OFF for now). Returns `nil` only if the background sprite is absent
    /// or malformed.
    ///
    /// - Parameters:
    ///   - skin: the loaded skin to pull `eqmain.bmp` sprites from.
    ///   - enabled: whether the equalizer is on (selects the ON button sprite).
    ///   - preamp: preamp gain in dB; placed on the preamp slider column.
    ///   - bands: per-band gains in dB. An array of any length is tolerated — only
    ///     the first ten entries are used, and a short array leaves the remaining
    ///     band thumbs unplaced (the background shows through), never trapping.
    ///   - active: reserved for the active/inactive title bar (the bare face does
    ///     not include the title strip); accepted for symmetry with the other
    ///     composers and forward use.
    public static func compose(
        _ skin: Skin,
        enabled: Bool,
        preamp: Double,
        bands: [Double],
        active: Bool = true
    ) -> DecodedBitmap? {
        guard let background = skin.sprite(sheet: "eqmain.bmp", name: "background") else {
            return nil
        }

        let width = background.width
        let height = background.height
        // `DecodedBitmap` does not enforce that its backing buffer holds exactly
        // `width * height * 4` bytes. An undersized background would make the blit
        // read/write out of range, so treat a malformed background as no usable
        // background (same guard class as `MainWindowComposer`).
        guard background.pixels.count == width * height * 4 else {
            return nil
        }

        // Start from a COPY of the background, then overlay each control through
        // the shared blit primitive. `overlay` clips to bounds and skips a missing
        // or size-inconsistent sprite, so every step below is fault tolerant.
        var canvas = DecodedBitmap(width: width, height: height, pixels: background.pixels)

        // (2) Slider thumbs: preamp column, then the ten band columns. One shared
        // thumb graphic; only the gain (→ y) and the column (x) differ. A missing
        // thumb sprite simply leaves the columns bare (background shows through).
        if let thumb = skin.sprite(sheet: "eqmain.bmp", name: "sliderThumb") {
            // Preamp.
            SkinCanvas.overlay(
                thumb,
                onto: &canvas,
                x: EQWindowLayout.preampSliderX,
                y: EQWindowLayout.thumbTopY(forGain: preamp)
            )
            // Ten bands: index into the layout's column table; tolerate an
            // off-length `bands` array by only placing the bands actually present.
            let columns = EQWindowLayout.bandSliderXs
            for index in 0..<min(columns.count, bands.count) {
                SkinCanvas.overlay(
                    thumb,
                    onto: &canvas,
                    x: columns[index],
                    y: EQWindowLayout.thumbTopY(forGain: bands[index])
                )
            }
        }

        // (3) ON button: on-state when the equalizer is enabled, off-state when
        // disabled. AUTO button: always the off-state for now (no auto-preset flag
        // is modelled). Both missing-sprite tolerant.
        let onSpriteName = enabled ? "onButtonOn" : "onButtonOff"
        if let onSprite = skin.sprite(sheet: "eqmain.bmp", name: onSpriteName) {
            SkinCanvas.overlay(
                onSprite,
                onto: &canvas,
                x: EQWindowLayout.onButtonOrigin.x,
                y: EQWindowLayout.onButtonOrigin.y
            )
        }
        if let autoSprite = skin.sprite(sheet: "eqmain.bmp", name: "autoButtonOff") {
            SkinCanvas.overlay(
                autoSprite,
                onto: &canvas,
                x: EQWindowLayout.autoButtonOrigin.x,
                y: EQWindowLayout.autoButtonOrigin.y
            )
        }

        return canvas
    }
}
