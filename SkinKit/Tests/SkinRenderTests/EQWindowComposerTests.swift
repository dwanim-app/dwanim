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
    /// fill of `bgColor`. When `includeRamp` is true a `graphLineColorRamp` sprite
    /// is added: a 1px-wide, 19px-tall vertical strip whose rows are a known color
    /// per row (so the curve's per-row tint can be asserted). When false the ramp is
    /// omitted (the truncated-sheet case).
    private func eqSheets(
        bgColor: (UInt8, UInt8, UInt8, UInt8),
        thumbColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 255, 255),
        onOnColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255),
        onOffColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255),
        autoOffColor: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255),
        autoOnColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 255, 255),
        includeRamp: Bool = false
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
        var sprites: [String: DecodedBitmap] = [
            "background": bg,
            "sliderThumb": solidBitmap(width: thumb.width, height: thumb.height, color: thumbColor),
            "onButtonOff": solidBitmap(width: onOff.width, height: onOff.height, color: onOffColor),
            "onButtonOn": solidBitmap(width: onOn.width, height: onOn.height, color: onOnColor),
            "autoButtonOff": solidBitmap(width: autoOff.width, height: autoOff.height, color: autoOffColor),
            "autoButtonOn": solidBitmap(width: autoOn.width, height: autoOn.height, color: autoOnColor)
        ]
        if includeRamp {
            sprites["graphLineColorRamp"] = rampBitmap()
        }
        return ["eqmain.bmp": sprites]
    }

    /// A 1px-wide ramp whose row `r` carries color `(r, 0, 0, 255)` — a distinct red
    /// channel per row so a curve pixel's tint reveals which ramp row coloured it.
    private func rampBitmap() -> DecodedBitmap {
        let ramp = eqSize("graphLineColorRamp")
        var pixels = [UInt8](repeating: 0, count: ramp.width * ramp.height * 4)
        for row in 0..<ramp.height {
            let i = (row * ramp.width) * 4
            pixels[i] = UInt8(row)   // R encodes the row index
            pixels[i + 1] = 0
            pixels[i + 2] = 0
            pixels[i + 3] = 255
        }
        return DecodedBitmap(width: ramp.width, height: ramp.height, pixels: pixels)
    }

    /// Graph rectangle building blocks shared by the curve tests.
    private var graph: (x: Int, y: Int, width: Int, height: Int) { EQWindowLayout.graphFrame }

    /// True when `(x, y)` differs from `bgColor` (i.e. the compositor wrote
    /// something there).
    private func differsFromBackground(_ bitmap: DecodedBitmap, x: Int, y: Int) -> Bool {
        let p = pixel(bitmap, x: x, y: y)
        return p.0 != bgColor.0 || p.1 != bgColor.1 || p.2 != bgColor.2
    }

    /// The set of rows in graph column `x` (window space) that the compositor wrote
    /// (differ from the background), restricted to the graph's row span.
    private func curveRows(in bitmap: DecodedBitmap, graphColumnX x: Int) -> [Int] {
        (graph.y..<(graph.y + graph.height)).filter { differsFromBackground(bitmap, x: x, y: $0) }
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

    // MARK: - 7. Response curve in the graph area

    /// A "smile" curve (boost the ends, cut the middle) draws a low-in-the-middle /
    /// high-at-the-ends shape in the graph: the curve row at the LEFT and RIGHT
    /// edges sits HIGHER (smaller y) than the curve row in the MIDDLE. Asserts on
    /// the composited pixels (not the helper), proving the curve is actually drawn.
    func testSmileCurveIsLowInTheMiddleHighAtTheEnds() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, includeRamp: true))
        // A pronounced smile so the shape is unambiguous in pixels.
        let bands: [Double] = [12, 8, 2, -6, -12, -12, -6, 2, 8, 12]
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: bands
        ) else {
            XCTFail("compose returned nil")
            return
        }

        func topCurveRow(atGraphColumn columnIndex: Int) -> Int? {
            let x = graph.x + columnIndex
            return curveRows(in: composed, graphColumnX: x).min()
        }

        let left = topCurveRow(atGraphColumn: 0)
        let middle = topCurveRow(atGraphColumn: graph.width / 2)
        let right = topCurveRow(atGraphColumn: graph.width - 1)
        XCTAssertNotNil(left, "curve must be drawn at the left edge")
        XCTAssertNotNil(middle, "curve must be drawn in the middle")
        XCTAssertNotNil(right, "curve must be drawn at the right edge")
        // Smile: ends boosted (small y), middle cut (large y).
        XCTAssertLessThan(left!, middle!, "left end is higher (smaller y) than the dipped middle")
        XCTAssertLessThan(right!, middle!, "right end is higher (smaller y) than the dipped middle")
    }

    /// A flat (all-0) curve draws a centred HORIZONTAL line across the graph: every
    /// graph column has a written pixel on the centre row, and the written rows are
    /// the same across columns (a level line).
    func testFlatCurveDrawsACentredHorizontalLine() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, includeRamp: true))
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: [Double](repeating: 0, count: 10)
        ) else {
            XCTFail("compose returned nil")
            return
        }
        let expected = EQResponseCurve.graphY(forGain: 0)
        // Every column carries a written pixel at the flat centre row.
        for columnIndex in 0..<graph.width {
            let x = graph.x + columnIndex
            XCTAssertTrue(
                differsFromBackground(composed, x: x, y: expected),
                "flat curve must mark the centre row at graph column \(columnIndex)")
        }
    }

    /// The curve stays CLIPPED to the graph rectangle: a pixel just outside the
    /// graph (one row above its top, and one column left of its left edge) is left
    /// as background even under a full-boost curve that pins to the top row.
    func testCurveStaysClippedToTheGraphRectangle() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, includeRamp: true))
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: [Double](repeating: 12, count: 10)
        ) else {
            XCTFail("compose returned nil")
            return
        }
        // One row above the graph top, within the graph's x span: must be untouched
        // (the curve clamps to the top ROW, never above it).
        if graph.y - 1 >= 0 {
            let aboveTop = pixel(composed, x: graph.x + graph.width / 2, y: graph.y - 1)
            XCTAssertEqual(aboveTop.0, bgColor.0, "no curve pixel above the graph top")
            XCTAssertEqual(aboveTop.1, bgColor.1)
            XCTAssertEqual(aboveTop.2, bgColor.2)
        }
        // One column left of the graph's left edge, on the curve's row: untouched.
        if graph.x - 1 >= 0 {
            let leftOfGraph = pixel(composed, x: graph.x - 1, y: graph.y)
            XCTAssertEqual(leftOfGraph.0, bgColor.0, "no curve pixel left of the graph")
            XCTAssertEqual(leftOfGraph.1, bgColor.1)
            XCTAssertEqual(leftOfGraph.2, bgColor.2)
        }
        // And the column just right of the graph's right edge is untouched.
        let rightEdgeX = graph.x + graph.width
        if rightEdgeX < composed.width {
            let rightOfGraph = pixel(composed, x: rightEdgeX, y: graph.y)
            XCTAssertEqual(rightOfGraph.0, bgColor.0, "no curve pixel right of the graph")
        }
    }

    /// The curve is colored by the graph ramp: a curve pixel's color matches the
    /// ramp row indexed by the curve's row-fraction within the graph. With the test
    /// ramp encoding the row index in the red channel, a curve pixel at the graph's
    /// TOP row should be tinted by the ramp's top row, and a pixel at the BOTTOM row
    /// by a higher ramp row — i.e. the red channel increases with the curve's y.
    func testCurveIsColoredByTheGraphRamp() {
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, includeRamp: true))
        // A monotone ramp from full boost (band 0, top) to full cut (band 9, bottom)
        // so the curve sweeps top -> bottom across the graph.
        let bands: [Double] = [12, 9, 6, 3, 0, -3, -6, -9, -12, -12]
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: bands
        ) else {
            XCTFail("compose returned nil")
            return
        }
        // The leftmost column sits near the top row; the ramp's red channel there is
        // small (low row index). The rightmost column sits near the bottom row; its
        // ramp red channel is larger (high row index).
        let leftX = graph.x
        let rightX = graph.x + graph.width - 1
        guard let leftRow = curveRows(in: composed, graphColumnX: leftX).min(),
              let rightRow = curveRows(in: composed, graphColumnX: rightX).max() else {
            XCTFail("curve must be drawn at both edges")
            return
        }
        let leftRed = pixel(composed, x: leftX, y: leftRow).0
        let rightRed = pixel(composed, x: rightX, y: rightRow).0
        // The ramp encodes the in-graph row index in red, so a lower (top) curve
        // pixel is tinted by a smaller red than a higher-y (bottom) one.
        XCTAssertLessThan(
            leftRed, rightRed,
            "the curve tint must track the ramp row by the curve's height in the graph")
    }

    /// Missing ramp (truncated sheet) is graceful: the curve is still drawn (a
    /// single sane line color) and the compose succeeds — no crash, buffer intact.
    func testMissingRampStillDrawsACurveAndDoesNotCrash() {
        // includeRamp: false -> the ramp sprite is absent, as on a truncated sheet.
        let skin = makeSkin(sprites: eqSheets(bgColor: bgColor, includeRamp: false))
        let bands: [Double] = [12, 8, 2, -6, -12, -12, -6, 2, 8, 12]
        guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: 0, bands: bands
        ) else {
            XCTFail("compose returned nil even though the background is present")
            return
        }
        XCTAssertEqual(composed.pixels.count, 275 * 116 * 4, "buffer intact without the ramp")
        // The curve is still plotted: at least one graph column has a written pixel.
        let anyDrawn = (0..<graph.width).contains { columnIndex in
            !curveRows(in: composed, graphColumnX: graph.x + columnIndex).isEmpty
        }
        XCTAssertTrue(anyDrawn, "the curve must still be drawn with a fallback color when the ramp is absent")
    }

    /// The curve never writes outside the graph rectangle anywhere on the buffer:
    /// scanning the whole 275x116 buffer, every pixel that DIFFERS from the
    /// background and is NOT covered by a control sprite footprint lies inside the
    /// graph rect. We make the control sprites the SAME color as the background so
    /// the only non-background writes are the curve (and we exclude the known
    /// control footprints, which are background-colored here anyway).
    func testCurveWritesNothingOutsideTheGraphRectangle() {
        // Controls colored identically to the background, so the ONLY pixels that
        // can differ from the background are the curve pixels.
        let sheets = eqSheets(
            bgColor: bgColor,
            thumbColor: bgColor,
            onOnColor: bgColor,
            onOffColor: bgColor,
            autoOffColor: bgColor,
            autoOnColor: bgColor,
            includeRamp: true
        )
        let bands: [Double] = [12, -12, 12, -12, 12, -12, 12, -12, 12, -12]
        guard let composed = EQWindowComposer.compose(
            makeSkin(sprites: sheets), enabled: true, preamp: 0, bands: bands
        ) else {
            XCTFail("compose returned nil")
            return
        }
        for y in 0..<composed.height {
            for x in 0..<composed.width {
                guard differsFromBackground(composed, x: x, y: y) else { continue }
                let inGraph = x >= graph.x && x < graph.x + graph.width
                    && y >= graph.y && y < graph.y + graph.height
                XCTAssertTrue(
                    inGraph,
                    "a non-background pixel at (\(x), \(y)) lies OUTSIDE the graph rect")
            }
        }
    }
}
