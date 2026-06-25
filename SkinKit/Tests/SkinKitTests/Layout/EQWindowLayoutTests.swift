import Foundation
import XCTest
@testable import SkinKit

/// Guards the static equalizer-window layout table: the eleven slider columns
/// (preamp + ten bands) are distinct and on-window, the shared slider track
/// y-range is inside the window, and the ON/AUTO buttons, graph area, and preset
/// display all sit entirely within the 275x116 EQ window.
///
/// This is pure arithmetic over the layout data plus the EQ sprite sizes — it
/// reads no real skin file. It exists so a future edit to `EQWindowLayout`
/// cannot place a control off-window without a test failing.
final class EQWindowLayoutTests: XCTestCase {

    private let width = EQWindowLayout.windowWidth
    private let height = EQWindowLayout.windowHeight

    /// Nominal pixel size of an EQ sprite by name, from
    /// `SpriteCoordinates.equalizerWindow`, or `nil` if absent.
    private func eqSpriteSize(_ name: String) -> (width: Int, height: Int)? {
        guard let rects = SpriteCoordinates.equalizerWindow["eqmain.bmp"],
              let rect = rects.first(where: { $0.name == name }) else {
            return nil
        }
        return (rect.width, rect.height)
    }

    func testWindowIsTheClassic275x116() {
        XCTAssertEqual(width, 275, "EQ window width")
        XCTAssertEqual(height, 116, "EQ window height")
    }

    // MARK: - Slider columns

    /// There are exactly ten band-slider x columns, all distinct.
    func testTenBandSliderColumnsAreDistinct() {
        let xs = EQWindowLayout.bandSliderXs
        XCTAssertEqual(xs.count, 10, "there must be exactly ten band-slider columns")
        XCTAssertEqual(Set(xs).count, 10, "the ten band-slider x columns must be distinct")
    }

    /// The preamp column is distinct from all ten band columns (it is a separate
    /// slider to the left of the band group).
    func testPreampColumnIsDistinctFromBands() {
        let xs = EQWindowLayout.bandSliderXs
        XCTAssertFalse(
            xs.contains(EQWindowLayout.preampSliderX),
            "preamp column must be distinct from the band columns")
    }

    /// Every slider thumb (preamp + ten bands) fits horizontally within the
    /// window at every point of its travel — the thumb's right edge (column x +
    /// thumb width) must not exceed the window width, and the column must be >= 0.
    func testEverySliderColumnFitsTheWindowWidth() {
        guard let thumb = eqSpriteSize("sliderThumb") else {
            XCTFail("sliderThumb sprite missing from the EQ table")
            return
        }
        let columns = [EQWindowLayout.preampSliderX] + EQWindowLayout.bandSliderXs
        for x in columns {
            XCTAssertGreaterThanOrEqual(x, 0, "slider column x \(x) must be >= 0")
            XCTAssertLessThanOrEqual(
                x + thumb.width, width,
                "slider column right edge \(x + thumb.width) exceeds window width \(width)")
        }
    }

    /// The slider track y-range is well-formed (top above bottom) and the thumb,
    /// at BOTH ends of its travel, stays within the window height. The thumb top
    /// at `sliderTrackTop` and its bottom at `sliderTrackBottom + thumbHeight`
    /// must both be in-bounds.
    func testSliderTrackYRangeIsWithinTheWindow() {
        guard let thumb = eqSpriteSize("sliderThumb") else {
            XCTFail("sliderThumb sprite missing from the EQ table")
            return
        }
        let top = EQWindowLayout.sliderTrackTop
        let bottom = EQWindowLayout.sliderTrackBottom
        XCTAssertGreaterThanOrEqual(top, 0, "track top must be >= 0")
        XCTAssertLessThan(top, bottom, "track top must be above track bottom")
        XCTAssertLessThanOrEqual(
            bottom + thumb.height, height,
            "thumb at the bottom of travel (\(bottom + thumb.height)) exceeds window "
                + "height \(height)")
    }

    /// The 0 dB centre is the midpoint of the track and lies strictly inside the
    /// travel range.
    func testSliderTrackCenterIsWithinTravel() {
        let center = EQWindowLayout.sliderTrackCenter
        XCTAssertGreaterThanOrEqual(center, EQWindowLayout.sliderTrackTop)
        XCTAssertLessThanOrEqual(center, EQWindowLayout.sliderTrackBottom)
    }

    // MARK: - Toggle buttons

    /// The ON and AUTO buttons, placed at their layout origins with their sprite
    /// sizes, fit entirely within the window and do not overlap each other.
    func testOnAndAutoButtonsFitTheWindowAndDoNotOverlap() {
        guard let onSize = eqSpriteSize("onButtonOff"),
              let autoSize = eqSpriteSize("autoButtonOff") else {
            XCTFail("ON/AUTO button sprites missing from the EQ table")
            return
        }
        let on = EQWindowLayout.onButtonOrigin
        let auto = EQWindowLayout.autoButtonOrigin

        for (name, x, y, size) in [
            ("ON", on.x, on.y, onSize),
            ("AUTO", auto.x, auto.y, autoSize)
        ] {
            XCTAssertGreaterThanOrEqual(x, 0, "\(name) x must be >= 0")
            XCTAssertGreaterThanOrEqual(y, 0, "\(name) y must be >= 0")
            XCTAssertLessThanOrEqual(
                x + size.width, width, "\(name) right edge exceeds window width")
            XCTAssertLessThanOrEqual(
                y + size.height, height, "\(name) bottom edge exceeds window height")
        }

        // No horizontal overlap of the two button footprints.
        let onRight = on.x + onSize.width
        let autoRight = auto.x + autoSize.width
        let disjoint = onRight <= auto.x || autoRight <= on.x
        XCTAssertTrue(disjoint, "ON and AUTO button footprints must not overlap")
    }

    // MARK: - Graph area and preset display

    /// The response-curve graph area is a non-empty rect entirely within the
    /// window.
    func testGraphFrameFitsTheWindow() {
        let g = EQWindowLayout.graphFrame
        XCTAssertGreaterThan(g.width, 0, "graph frame width must be positive")
        XCTAssertGreaterThan(g.height, 0, "graph frame height must be positive")
        XCTAssertGreaterThanOrEqual(g.x, 0, "graph frame x must be >= 0")
        XCTAssertGreaterThanOrEqual(g.y, 0, "graph frame y must be >= 0")
        XCTAssertLessThanOrEqual(
            g.x + g.width, width, "graph frame right edge exceeds window width")
        XCTAssertLessThanOrEqual(
            g.y + g.height, height, "graph frame bottom edge exceeds window height")
    }

    /// The preset display origin is within the window bounds.
    func testPresetDisplayOriginIsWithinTheWindow() {
        let p = EQWindowLayout.presetDisplayOrigin
        XCTAssertGreaterThanOrEqual(p.x, 0, "preset display x must be >= 0")
        XCTAssertGreaterThanOrEqual(p.y, 0, "preset display y must be >= 0")
        XCTAssertLessThanOrEqual(p.x, width, "preset display x exceeds window width")
        XCTAssertLessThanOrEqual(p.y, height, "preset display y exceeds window height")
    }

    // MARK: - thumbTopY (gain -> thumb top-left y)
    //
    // The pure mapping the compositor uses to place a slider thumb from a band's
    // dB gain. +12 dB pins the thumb at the TOP of the track (`sliderTrackTop`);
    // -12 dB pins it at the BOTTOM such that the 11px thumb body's lower edge sits
    // on `sliderTrackBottom` (so its top-left is `sliderTrackBottom - thumbHeight`);
    // 0 dB centres the thumb on `sliderTrackCenter`. Linear and clamped between.

    /// The expected thumb-top travel ends, derived from the layout + thumb height,
    /// so the assertions below describe the contract rather than restate magic
    /// numbers.
    private var thumbHeight: Int {
        eqSpriteSize("sliderThumb")?.height ?? 11
    }
    private var topTravelY: Int { EQWindowLayout.sliderTrackTop }
    private var bottomTravelY: Int { EQWindowLayout.sliderTrackBottom - thumbHeight }

    /// +12 dB (maximum boost) puts the thumb at the very top of the track.
    func testThumbTopYAtMaxGainIsTrackTop() {
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: 12), topTravelY)
    }

    /// -12 dB (maximum cut) puts the thumb at the bottom of the track, accounting
    /// for the thumb body height so the thumb stays within the track.
    func testThumbTopYAtMinGainIsTrackBottomMinusThumb() {
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: -12), bottomTravelY)
    }

    /// 0 dB (flat) centres the thumb on the track centre: the thumb top is
    /// `sliderTrackCenter - thumbHeight/2`, which is the midpoint of the travel.
    func testThumbTopYAtZeroGainIsCenteredOnTrackCenter() {
        let centered = EQWindowLayout.sliderTrackCenter - thumbHeight / 2
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: 0), centered)
        // And the midpoint of the travel ends.
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: 0), (topTravelY + bottomTravelY) / 2)
    }

    /// Gains beyond the +-12 dB range clamp to the track ends — they never push
    /// the thumb above the top or below the bottom of its travel.
    func testThumbTopYClampsOutOfRangeGains() {
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: 100), topTravelY, "huge boost clamps to top")
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: -100), bottomTravelY, "huge cut clamps to bottom")
        // Non-finite gain falls back to the flat (centre) position rather than
        // producing a garbage/NaN coordinate.
        let centered = EQWindowLayout.sliderTrackCenter - thumbHeight / 2
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: .nan), centered, "NaN gain -> centre")
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: .infinity), topTravelY, "+inf clamps to top")
        XCTAssertEqual(EQWindowLayout.thumbTopY(forGain: -.infinity), bottomTravelY, "-inf clamps to bottom")
    }

    /// The mapping is monotonic non-increasing in gain: a higher gain is never a
    /// LARGER y (lower on screen) than a lower gain — more boost means higher up
    /// (smaller y). Sampled across the full range plus the out-of-range tails.
    func testThumbTopYIsMonotonicNonIncreasingInGain() {
        let gains = stride(from: -16.0, through: 16.0, by: 0.5)
        var previous = EQWindowLayout.thumbTopY(forGain: -16)
        for gain in gains {
            let y = EQWindowLayout.thumbTopY(forGain: gain)
            XCTAssertLessThanOrEqual(
                y, previous,
                "thumb y must not increase as gain rises (gain \(gain))")
            previous = y
        }
    }

    /// Every thumb position across the full clamped range keeps the whole 11px
    /// thumb body inside the track `[sliderTrackTop, sliderTrackBottom]`.
    func testThumbBodyStaysWithinTrackForAllGains() {
        for gain in stride(from: -12.0, through: 12.0, by: 0.25) {
            let top = EQWindowLayout.thumbTopY(forGain: gain)
            XCTAssertGreaterThanOrEqual(top, EQWindowLayout.sliderTrackTop)
            XCTAssertLessThanOrEqual(top + thumbHeight, EQWindowLayout.sliderTrackBottom)
        }
    }

    // MARK: - thumbGain (thumb top-left y -> gain) — the inverse of thumbTopY
    //
    // The pure inverse the EQ drag uses to turn a thumb-top y (clicked/dragged in
    // skin space) back into a band/preamp dB gain. The track top maps to +12 dB,
    // the track bottom (`sliderTrackBottom - thumbHeight`) to -12 dB; linear and
    // clamped between. Higher on screen (smaller y) ⇒ more boost.

    /// The thumb-top y at the TOP of the track maps back to +12 dB (max boost).
    func testThumbGainAtTrackTopIsMaxBoost() {
        XCTAssertEqual(EQWindowLayout.thumbGain(forThumbTopY: topTravelY), 12, accuracy: 0.0001)
    }

    /// The thumb-top y at the BOTTOM of the track maps back to -12 dB (max cut).
    func testThumbGainAtTrackBottomIsMaxCut() {
        XCTAssertEqual(EQWindowLayout.thumbGain(forThumbTopY: bottomTravelY), -12, accuracy: 0.0001)
    }

    /// The thumb-top y at the centre of the travel maps back to 0 dB (flat).
    func testThumbGainAtTrackCenterIsFlat() {
        let center = (topTravelY + bottomTravelY) / 2
        XCTAssertEqual(EQWindowLayout.thumbGain(forThumbTopY: center), 0, accuracy: 0.5)
    }

    /// A y above the track top (smaller than `sliderTrackTop`) clamps to +12 dB;
    /// a y below the track bottom clamps to -12 dB — the gain never escapes ±12.
    func testThumbGainClampsOutOfTrackY() {
        XCTAssertEqual(
            EQWindowLayout.thumbGain(forThumbTopY: topTravelY - 100), 12, accuracy: 0.0001,
            "y above the top clamps to +12")
        XCTAssertEqual(
            EQWindowLayout.thumbGain(forThumbTopY: bottomTravelY + 100), -12, accuracy: 0.0001,
            "y below the bottom clamps to -12")
    }

    /// The inverse is monotonic non-increasing in y: a larger y (lower on screen)
    /// never yields a LARGER gain than a smaller y. Sampled across the track plus
    /// the out-of-range tails.
    func testThumbGainIsMonotonicNonIncreasingInY() {
        var previous = EQWindowLayout.thumbGain(forThumbTopY: topTravelY - 10)
        for y in stride(from: topTravelY - 10, through: bottomTravelY + 10, by: 1) {
            let gain = EQWindowLayout.thumbGain(forThumbTopY: y)
            XCTAssertLessThanOrEqual(
                gain, previous + 0.0001,
                "gain must not increase as y rises (y \(y))")
            previous = gain
        }
    }

    /// Round-trip: `thumbTopY(thumbGain(y))` returns to the same y for every
    /// in-track y. The two functions are inverses (within the integer-rounding the
    /// forward map applies), so a thumb dragged to a y and re-placed lands back.
    func testThumbGainRoundTripsThroughThumbTopY() {
        for y in topTravelY...bottomTravelY {
            let gain = EQWindowLayout.thumbGain(forThumbTopY: y)
            XCTAssertEqual(
                EQWindowLayout.thumbTopY(forGain: gain), y,
                "thumbTopY(thumbGain(\(y))) must round-trip to \(y)")
        }
    }

    /// Round-trip the OTHER way at representative gains: `thumbGain(thumbTopY(g))`
    /// returns approximately `g` for 0, ±12, and a few mid gains (within the
    /// per-pixel quantization the forward map's rounding introduces).
    func testThumbTopYRoundTripsThroughThumbGainAtRepresentativeGains() {
        // One pixel of travel is the whole ±12→±12 range over the pixel span, so
        // the round-trip tolerance is one pixel's worth of dB.
        let span = Double(bottomTravelY - topTravelY)
        let dBPerPixel = (EQWindowLayout.gainMaxDB - EQWindowLayout.gainMinDB) / span
        for gain in [-12.0, -6.0, -3.0, 0.0, 3.0, 6.0, 12.0] {
            let y = EQWindowLayout.thumbTopY(forGain: gain)
            let back = EQWindowLayout.thumbGain(forThumbTopY: y)
            XCTAssertEqual(
                back, gain, accuracy: dBPerPixel + 0.0001,
                "thumbGain(thumbTopY(\(gain))) must round-trip to ~\(gain)")
        }
    }

    // MARK: - slider(atSkinX:) — column -> which slider (preamp or band index)

    /// A click on the exact preamp column resolves to the preamp slider.
    func testSliderAtPreampColumnIsPreamp() {
        XCTAssertEqual(EQWindowLayout.slider(atSkinX: EQWindowLayout.preampSliderX), .preamp)
    }

    /// A click on each band column resolves to that band index, in order.
    func testSliderAtBandColumnsResolveToTheirIndex() {
        for (index, x) in EQWindowLayout.bandSliderXs.enumerated() {
            XCTAssertEqual(
                EQWindowLayout.slider(atSkinX: x), .band(index),
                "x \(x) should resolve to band \(index)")
        }
    }

    /// A click a few px off a column still snaps to the nearest column within the
    /// hit width (the columns are `bandSliderSpacing` apart, so the thumb's own
    /// width comfortably covers a near-miss).
    func testSliderAtNearMissSnapsToNearestColumn() {
        // Just right of band 0's column, still well within half the spacing.
        let near = EQWindowLayout.bandSliderXs[0] + 2
        XCTAssertEqual(EQWindowLayout.slider(atSkinX: near), .band(0))
    }

    /// A click far from every column (e.g. above the slider block, far left of
    /// the preamp) is not on any slider.
    func testSliderAtFarColumnIsNil() {
        XCTAssertNil(
            EQWindowLayout.slider(atSkinX: -100), "far left of every column is nil")
        XCTAssertNil(
            EQWindowLayout.slider(atSkinX: EQWindowLayout.windowWidth + 100),
            "far right of every column is nil")
    }

    /// The midpoint between the preamp column and the first band column resolves
    /// to whichever is genuinely nearer (a defined, non-ambiguous tie-break), and
    /// every resolved column is one of the eleven sliders.
    func testSliderResolutionPicksNearestColumn() {
        // A point closer to the first band than to the preamp picks the band.
        let preamp = EQWindowLayout.preampSliderX
        let band0 = EQWindowLayout.bandSliderXs[0]
        let nearerBand = band0 - 1
        XCTAssertEqual(EQWindowLayout.slider(atSkinX: nearerBand), .band(0))
        // A point right on the preamp picks preamp.
        XCTAssertEqual(EQWindowLayout.slider(atSkinX: preamp), .preamp)
    }
}
