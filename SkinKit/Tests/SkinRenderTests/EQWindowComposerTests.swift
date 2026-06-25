import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure RGBA8 equalizer-window compositor on synthetic skins built
/// entirely in-memory (no real `.wsz` files, no graphics framework). Each test
/// asserts directly on the returned `DecodedBitmap.pixels`, proving the
/// compositor's background fill, the eleven slider-thumb landing positions
/// (preamp + ten bands) at their gain-derived y, the ON/AUTO toggle state, and
/// its fault tolerance / bounds safety — all without any platform image bridge.
///
/// `EQWindowComposer.compose` takes RAW values (`enabled`, `preamp`, `bands`)
/// rather than the `PlayerCore.EQState` type, because `SkinRender` does not (and
/// must not) depend on `PlayerCore`. Keeping the seam at plain `Bool`/`Double`
/// keeps the module graph clean.
final class EQWindowComposerTests: XCTestCase {

    // MARK: - Helpers

    private func solidBitmap(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8, UInt8)
    ) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = color.3
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    private func pixel(_ bitmap: DecodedBitmap, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * bitmap.width + x) * 4
        return (
            bitmap.pixels[index],
            bitmap.pixels[index + 1],
            bitmap.pixels[index + 2],
            bitmap.pixels[index + 3]
        )
    }

    private func makeSkin(sprites: [String: [String: DecodedBitmap]]) -> Skin {
        Skin(sprites: sprites, visColors: [], playlist: nil, region: nil)
    }

    /// Nominal pixel size of an EQ sprite from the coordinate table.
    private func eqSize(_ name: String) -> (width: Int, height: Int) {
        let rects = SpriteCoordinates.equalizerWindow["eqmain.bmp"]!
        let rect = rects.first { $0.name == name }!
        return (rect.width, rect.height)
    }

    /// A full set of distinctly-colored EQ sprites at their nominal sizes so each
    /// composited element is identifiable by its color. The background is a solid
    /// fill of `bgColor`.
    private func eqSheets(
        bgColor: (UInt8, UInt8, UInt8, UInt8),
        thumbColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 255, 255),
        onOnColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255),
        onOffColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255),
        autoOffColor: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255),
        autoOnColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 255, 255)
    ) -> [String: [String: DecodedBitmap]] {
        let bg = solidBitmap(
            width: EQWindowLayout.windowWidth,
            height: EQWindowLayout.windowHeight,
            color: bgColor
        )
        let thumb = eqSize("sliderThumb")
        let onOff = eqSize("onButtonOff")
        let onOn = eqSize("onButtonOn")
        let autoOff = eqSize("autoButtonOff")
        let autoOn = eqSize("autoButtonOn")
        return [
            "eqmain.bmp": [
                "background": bg,
                "sliderThumb": solidBitmap(width: thumb.width, height: thumb.height, color: thumbColor),
                "onButtonOff": solidBitmap(width: onOff.width, height: onOff.height, color: onOffColor),
                "onButtonOn": solidBitmap(width: onOn.width, height: onOn.height, color: onOnColor),
                "autoButtonOff": solidBitmap(width: autoOff.width, height: autoOff.height, color: autoOffColor),
                "autoButtonOn": solidBitmap(width: autoOn.width, height: autoOn.height, color: autoOnColor)
            ]
        ]
    }

    private let thumbColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 255, 255)
    private let bgColor: (UInt8, UInt8, UInt8, UInt8) = (10, 20, 30, 255)

    // MARK: - 1. Dimensions / background fill

    func testComposeReturnsTheClassic275x116Bitmap() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor))
        guard let composed = EQWindowComposer.compose(
            skin, enabled: false, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil for a skin with an eqmain background")
            return
        }
        XCTAssertEqual(composed.width, 275)
        XCTAssertEqual(composed.height, 116)
        XCTAssertEqual(composed.pixels.count, 275 * 116 * 4, "buffer must be exactly w*h*4")
    }

    /// The background sprite fills the whole face: a pixel in a corner untouched
    /// by any control still equals the background color.
    func testBackgroundFillsTheFace() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor))
        guard let composed = EQWindowComposer.compose(
            skin, enabled: false, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil")
            return
        }
        // Bottom-right corner is below the slider track and outside all controls.
        let corner = pixel(composed, x: 274, y: 115)
        XCTAssertEqual(corner.0, bgColor.0)
        XCTAssertEqual(corner.1, bgColor.1)
        XCTAssertEqual(corner.2, bgColor.2)
        XCTAssertEqual(corner.3, bgColor.3)
    }

    // MARK: - 2. Thumb placement (x columns + gain -> y)

    /// The eleven thumbs (preamp + ten bands) land at their layout x columns and
    /// at the gain-derived y. With all gains 0 the thumb top is the centered y for
    /// every column; the thumb color appears there.
    func testThumbsLandAtTheirColumnsAtZeroGain() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, thumbColor: thumbColor))
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil")
            return
        }
        let y = EQWindowLayout.thumbTopY(forGain: 0)
        let columns = [EQWindowLayout.preampSliderX] + EQWindowLayout.bandSliderXs
        for x in columns {
            let landed = pixel(composed, x: x, y: y)
            XCTAssertEqual(landed.0, thumbColor.0, "thumb red at column \(x), y \(y)")
            XCTAssertEqual(landed.1, thumbColor.1)
            XCTAssertEqual(landed.2, thumbColor.2)
        }
    }

    /// A boosted band's thumb lands HIGHER (smaller y) than a cut band's thumb:
    /// the gain->y mapping is reflected in the composited positions. Build a skin
    /// with band 0 at +12 and band 1 at -12 and find the thumb's top row in each
    /// column.
    func testBoostedThumbIsHigherThanCutThumb() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, thumbColor: thumbColor))
        var bands = [Double](repeating: 0, count: 10)
        bands[0] = 12   // max boost -> top
        bands[1] = -12  // max cut -> bottom
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: bands
        ) else {
            XCTFail("compose returned nil")
            return
        }

        let boostedTop = topRowOfThumb(in: composed, column: EQWindowLayout.bandSliderXs[0])
        let cutTop = topRowOfThumb(in: composed, column: EQWindowLayout.bandSliderXs[1])
        XCTAssertNotNil(boostedTop, "boosted band thumb must be present")
        XCTAssertNotNil(cutTop, "cut band thumb must be present")
        XCTAssertLessThan(boostedTop!, cutTop!, "the +12 thumb must be higher (smaller y) than the -12 thumb")
        XCTAssertEqual(boostedTop, EQWindowLayout.thumbTopY(forGain: 12))
        XCTAssertEqual(cutTop, EQWindowLayout.thumbTopY(forGain: -12))
    }

    /// The first row (smallest y) in `column` that carries the thumb color, or nil.
    private func topRowOfThumb(in bitmap: DecodedBitmap, column: Int) -> Int? {
        for y in 0..<bitmap.height {
            let p = pixel(bitmap, x: column, y: y)
            if p.0 == thumbColor.0 && p.1 == thumbColor.1 && p.2 == thumbColor.2 {
                return y
            }
        }
        return nil
    }

    // MARK: - 3. ON / AUTO toggle state

    /// `enabled == true` composites the ON sprite at the ON origin; `false`
    /// composites the OFF sprite.
    func testOnSpriteReflectsEnabledFlag() {
        let onOnColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)
        let onOffColor: (UInt8, UInt8, UInt8, UInt8) = (200, 0, 0, 255)
        let sheets = eqSheets(bgColor: bgColor, onOnColor: onOnColor, onOffColor: onOffColor)
        let origin = EQWindowLayout.onButtonOrigin

        guard let enabledComposed = EQWindowComposer.compose(
            makeSkin(sprites: sheets), enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ), let disabledComposed = EQWindowComposer.compose(
            makeSkin(sprites: sheets), enabled: false, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil")
            return
        }

        let onWhenEnabled = pixel(enabledComposed, x: origin.x, y: origin.y)
        XCTAssertEqual(onWhenEnabled.0, onOnColor.0, "ON sprite (enabled) red")
        XCTAssertEqual(onWhenEnabled.1, onOnColor.1)

        let onWhenDisabled = pixel(disabledComposed, x: origin.x, y: origin.y)
        XCTAssertEqual(onWhenDisabled.0, onOffColor.0, "OFF sprite (disabled) red")
        XCTAssertEqual(onWhenDisabled.1, onOffColor.1)
    }

    /// AUTO defaults to OFF (no auto flag modelled yet): its OFF sprite is drawn at
    /// the AUTO origin.
    func testAutoSpriteIsOffByDefault() {
        let autoOffColor: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 200, 255)
        let sheets = eqSheets(bgColor: bgColor, autoOffColor: autoOffColor)
        let origin = EQWindowLayout.autoButtonOrigin
        guard let composed = EQWindowComposer.compose(
            makeSkin(sprites: sheets), enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil")
            return
        }
        let auto = pixel(composed, x: origin.x, y: origin.y)
        XCTAssertEqual(auto.2, autoOffColor.2, "AUTO OFF sprite blue at AUTO origin")
        XCTAssertEqual(auto.0, autoOffColor.0)
    }

    // MARK: - 4. Missing eqmain background -> nil

    func testNoBackgroundReturnsNil() {
        // A skin with no eqmain.bmp/background at all.
        let skin = makeSkin(sprites: [:])
        XCTAssertNil(EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ))
    }

    // MARK: - 5. Missing individual sprites tolerated

    /// With only the background present (no thumb / no buttons), compose still
    /// succeeds and returns the background unmodified — missing control sprites are
    /// skipped, never fatal.
    func testMissingControlSpritesAreToleratedAndBackgroundShowsThrough() {
        let onlyBackground: [String: [String: DecodedBitmap]] = [
            "eqmain.bmp": [
                "background": solidBitmap(
                    width: EQWindowLayout.windowWidth,
                    height: EQWindowLayout.windowHeight,
                    color: bgColor
                )
            ]
        ]
        guard let composed = EQWindowComposer.compose(
            makeSkin(sprites: onlyBackground), enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil with a valid background but no controls")
            return
        }
        // A slider column at the centered thumb y still shows the background (the
        // missing thumb was skipped, not drawn).
        let y = EQWindowLayout.thumbTopY(forGain: 0)
        let p = pixel(composed, x: EQWindowLayout.preampSliderX, y: y)
        XCTAssertEqual(p.0, bgColor.0)
        XCTAssertEqual(p.1, bgColor.1)
        XCTAssertEqual(p.2, bgColor.2)
    }

    // MARK: - 6. Bounds / buffer integrity

    /// The composed buffer is exactly 275*116*4 bytes regardless of state — no
    /// out-of-range write ever resizes or corrupts it. Also exercised with extreme
    /// out-of-range / non-finite gains, which clamp rather than write off-buffer.
    func testBufferSizeIsStableUnderExtremeGains() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor))
        let bands: [Double] = [100, -100, .nan, .infinity, -.infinity, 12, -12, 0, 6, -6]
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 1000, bands: bands
        ) else {
            XCTFail("compose returned nil")
            return
        }
        XCTAssertEqual(composed.pixels.count, 275 * 116 * 4)
        XCTAssertEqual(composed.width, 275)
        XCTAssertEqual(composed.height, 116)
    }

    /// A `bands` array of the wrong length must not trap: fewer than ten bands
    /// places only the bands provided (plus preamp); more than ten ignores the
    /// extras. Buffer stays well-formed.
    func testWrongLengthBandsArrayIsToleratedWithoutTrapping() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor))
        guard let short = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: [0, 0, 0]
        ), let long = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 25)
        ) else {
            XCTFail("compose returned nil for an off-length bands array")
            return
        }
        XCTAssertEqual(short.pixels.count, 275 * 116 * 4)
        XCTAssertEqual(long.pixels.count, 275 * 116 * 4)
    }
}
