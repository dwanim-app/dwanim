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

    /// A point over the first band thumb (but not the preamp's) resolves to the
    /// band, and a point over the preamp thumb resolves to the preamp — a defined,
    /// non-ambiguous nearest-DRAWN-thumb tie-break. The hit region is centred on
    /// each thumb's DRAWN centre (`column + thumbWidth/2`), so the in-thumb sample
    /// points use that centre rather than the bare top-left column.
    func testSliderResolutionPicksNearestColumn() {
        let offset = hitThumbWidth / 2
        let preampCentre = EQWindowLayout.preampSliderX + offset
        let band0Centre = EQWindowLayout.bandSliderXs[0] + offset
        // A point on band 0's drawn thumb (nearer band 0 than the preamp) -> band 0.
        XCTAssertEqual(EQWindowLayout.slider(atSkinX: band0Centre), .band(0))
        // A point on the preamp's drawn thumb -> preamp.
        XCTAssertEqual(EQWindowLayout.slider(atSkinX: preampCentre), .preamp)
    }

    // MARK: - slider(atSkinX:) hit region is centred on the DRAWN thumb
    //
    // The composer (`EQWindowComposer`) blits each thumb with its TOP-LEFT x AT
    // the column, so the VISIBLE thumb spans `[columnX, columnX + thumbWidth)` and
    // its DRAWN CENTRE is `columnX + thumbWidth/2`. The hit region must be centred
    // on that drawn centre (matching the y-axis centre compensation in `applyGain`,
    // which uses `skinY - thumbHeight/2`), so clicking anywhere over the visible
    // thumb — including its right half — grabs that thumb, not the neighbour.

    private var hitThumbWidth: Int { eqSpriteSize("sliderThumb")?.width ?? 14 }

    /// A click on the VISIBLE CENTRE of band i's thumb (`bandSliderXs[i] +
    /// thumbWidth/2`) resolves to that band.
    func testSliderAtBandVisibleCentreResolvesToBand() {
        for (index, columnX) in EQWindowLayout.bandSliderXs.enumerated() {
            let visibleCentre = columnX + hitThumbWidth / 2
            XCTAssertEqual(
                EQWindowLayout.slider(atSkinX: visibleCentre), .band(index),
                "visible centre x \(visibleCentre) should resolve to band \(index)")
        }
    }

    /// The VISIBLE LEFT edge of band i's thumb (`bandSliderXs[i]`) and its VISIBLE
    /// RIGHT edge (`bandSliderXs[i] + thumbWidth - 1`) both resolve to band i — not
    /// nil and not the neighbour. The right edge is the case that misfired before
    /// the centre-on-drawn-thumb fix.
    func testSliderAtBandVisibleEdgesResolveToBand() {
        for (index, columnX) in EQWindowLayout.bandSliderXs.enumerated() {
            let leftEdge = columnX
            let rightEdge = columnX + hitThumbWidth - 1
            XCTAssertEqual(
                EQWindowLayout.slider(atSkinX: leftEdge), .band(index),
                "visible left edge x \(leftEdge) should resolve to band \(index)")
            XCTAssertEqual(
                EQWindowLayout.slider(atSkinX: rightEdge), .band(index),
                "visible right edge x \(rightEdge) should resolve to band \(index)")
        }
    }

    /// A click on the VISIBLE CENTRE / LEFT / RIGHT edge of the PREAMP thumb
    /// resolves to the preamp slider.
    func testSliderAtPreampVisibleExtentResolvesToPreamp() {
        let columnX = EQWindowLayout.preampSliderX
        for x in [columnX, columnX + hitThumbWidth / 2, columnX + hitThumbWidth - 1] {
            XCTAssertEqual(
                EQWindowLayout.slider(atSkinX: x), .preamp,
                "preamp visible extent x \(x) should resolve to preamp")
        }
    }

    /// A point between two adjacent band thumbs resolves to the NEARER thumb (by
    /// their DRAWN centres), never the farther one. A point one px on band i's side
    /// of the inter-centre midpoint picks band i; one px on band i+1's side picks
    /// band i+1 — provided it is still within a thumb's hit half-width of that
    /// centre (the hit region is centred on the drawn thumb).
    func testSliderInGapBetweenThumbsResolvesToNearer() {
        let columns = EQWindowLayout.bandSliderXs
        let offset = hitThumbWidth / 2
        let centreA = columns[0] + offset
        let centreB = columns[1] + offset
        // A point just inside band 0's hit region (right portion of its thumb) is
        // nearer band 0 than band 1 -> band 0; symmetrically for band 1's left
        // portion -> band 1. Both sit on their own thumb, not in the dead gap.
        let half = Swift.min(hitThumbWidth / 2, EQWindowLayout.bandSliderSpacing / 2)
        let nearA = centreA + half        // band 0's far (right) hit boundary
        let nearB = centreB - half        // band 1's near (left) hit boundary
        XCTAssertEqual(
            EQWindowLayout.slider(atSkinX: nearA), .band(0),
            "x \(nearA) is nearer band 0's drawn centre -> band 0")
        XCTAssertEqual(
            EQWindowLayout.slider(atSkinX: nearB), .band(1),
            "x \(nearB) is nearer band 1's drawn centre -> band 1")
        // And neither resolves to the FARTHER neighbour.
        XCTAssertNotEqual(EQWindowLayout.slider(atSkinX: nearA), .band(1))
        XCTAssertNotEqual(EQWindowLayout.slider(atSkinX: nearB), .band(0))
    }

    // MARK: - slider(atSkinX:skinY:) — the y-gated resolver (graph-click guard)
    //
    // The interactive drag uses the y-gated resolver on a mouse-DOWN: a press only
    // grabs a slider when its y is inside the SLIDER CONTROL band (the thumb-travel
    // region `[sliderTrackTop, sliderTrackBottom)`). A press in the response-curve
    // GRAPH area ABOVE the track, or the label area BELOW it, must NOT grab a
    // slider — even though its x overlaps the band columns — so clicking the graph
    // no longer slams the nearest band to its clamped extreme.

    /// A representative y inside the control band (the track centre is always
    /// inside `[sliderTrackTop, sliderTrackBottom)`).
    private var inBandY: Int { EQWindowLayout.sliderTrackCenter }

    /// A click on each band column AT a y inside the track resolves to that band —
    /// the gate is transparent to a legitimate on-track press, matching the bare
    /// `slider(atSkinX:)`.
    func testSliderAtXYResolvesBandsWhenYInsideTrack() {
        for (index, x) in EQWindowLayout.bandSliderXs.enumerated() {
            XCTAssertEqual(
                EQWindowLayout.slider(atSkinX: x, skinY: inBandY), .band(index),
                "x \(x) at an in-track y should resolve to band \(index)")
        }
    }

    /// A click on the preamp column AT a y inside the track resolves to the preamp.
    func testSliderAtXYResolvesPreampWhenYInsideTrack() {
        XCTAssertEqual(
            EQWindowLayout.slider(atSkinX: EQWindowLayout.preampSliderX, skinY: inBandY),
            .preamp)
    }

    /// The SAME band x, but at a y ABOVE the track (in the response-curve graph
    /// area, `y < sliderTrackTop`), returns nil — the graph-click no longer grabs a
    /// band. The graph frame sits above the track, so a y in it is the real-world
    /// case. This FAILS without the y-gate (the bare resolver ignores y).
    func testSliderAtXYReturnsNilForBandXInGraphArea() {
        // A y inside the response-curve graph area, which lies above the track.
        let graphY = EQWindowLayout.graphFrame.y
        XCTAssertLessThan(
            graphY, EQWindowLayout.sliderTrackTop,
            "premise: the graph area is above the slider track")
        for (index, x) in EQWindowLayout.bandSliderXs.enumerated() {
            XCTAssertNil(
                EQWindowLayout.slider(atSkinX: x, skinY: graphY),
                "band \(index) x \(x) at a graph-area y must NOT grab a slider")
        }
        // And one pixel above the track top is still excluded.
        for x in EQWindowLayout.bandSliderXs {
            XCTAssertNil(
                EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackTop - 1),
                "one px above the track top must NOT grab a slider")
        }
    }

    /// The same x, at a y BELOW the track (the label area, `y >= sliderTrackBottom`)
    /// returns nil — the bottom is the half-open upper bound of the control band.
    /// FAILS without the y-gate.
    func testSliderAtXYReturnsNilForBandXInLabelArea() {
        let belowY = EQWindowLayout.sliderTrackBottom + 1
        for (index, x) in EQWindowLayout.bandSliderXs.enumerated() {
            XCTAssertNil(
                EQWindowLayout.slider(atSkinX: x, skinY: belowY),
                "band \(index) x \(x) at a label-area y must NOT grab a slider")
        }
        // The bottom row itself is the half-open exclusive bound -> nil.
        for x in EQWindowLayout.bandSliderXs {
            XCTAssertNil(
                EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackBottom),
                "sliderTrackBottom is the exclusive bound -> nil")
        }
    }

    /// The preamp x is gated the same way: nil in the graph area above and the
    /// label area below the track.
    func testSliderAtXYReturnsNilForPreampOffTrack() {
        let x = EQWindowLayout.preampSliderX
        XCTAssertNil(
            EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackTop - 1),
            "preamp above the track -> nil")
        XCTAssertNil(
            EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackBottom),
            "preamp at/below the track bottom -> nil")
    }

    /// The control-band edges are half-open `[sliderTrackTop, sliderTrackBottom)`:
    /// the top row is INCLUDED (a thumb can sit there) and the bottom row is
    /// EXCLUDED. A band x at the top row grabs; at the bottom row it does not.
    func testSliderAtXYBandEdgesAreHalfOpen() {
        let x = EQWindowLayout.bandSliderXs[0]
        XCTAssertEqual(
            EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackTop), .band(0),
            "track top row is inside the control band")
        XCTAssertEqual(
            EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackBottom - 1),
            .band(0),
            "last row before the bottom is inside the control band")
        XCTAssertNil(
            EQWindowLayout.slider(atSkinX: x, skinY: EQWindowLayout.sliderTrackBottom),
            "the bottom row is the exclusive upper bound")
    }

    /// Within the control band, the x tie-break / nearest-thumb behaviour is
    /// IDENTICAL to the bare `slider(atSkinX:)` — the gate only filters y, it does
    /// not change column resolution. Sampled at the visible left/centre/right of
    /// each band thumb and a far-off x.
    func testSliderAtXYInBandMatchesBareResolver() {
        let thumbW = hitThumbWidth
        let y = inBandY
        for columnX in [EQWindowLayout.preampSliderX] + EQWindowLayout.bandSliderXs {
            for x in [columnX, columnX + thumbW / 2, columnX + thumbW - 1] {
                XCTAssertEqual(
                    EQWindowLayout.slider(atSkinX: x, skinY: y),
                    EQWindowLayout.slider(atSkinX: x),
                    "in-band x \(x) must match the bare resolver")
            }
        }
        // A far-off x is nil under both (within the band).
        XCTAssertNil(EQWindowLayout.slider(atSkinX: -100, skinY: y))
        XCTAssertEqual(
            EQWindowLayout.slider(atSkinX: -100, skinY: y),
            EQWindowLayout.slider(atSkinX: -100))
    }
}
