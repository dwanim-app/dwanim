import Foundation
import SkinKit
import XCTest
@testable import SkinRender

/// End-to-end regression for the classic EQ slider DRAG pipeline — the exact chain
/// the interactive `EQController` runs on a mouse-down / drag, minus the AppKit
/// window:
///
///   raw view-space y
///     → `ControlHitTest.skinPoint` (undo presentation scale + y-flip)
///     → `EQWindowLayout.slider(atSkinX:skinY:)` (grab gate)
///     → `EQWindowLayout.gain(forCursorSkinY:)` (cursor y → gain)
///
/// The bug this guards against ("classic EQ sliders cannot drag below centre —
/// stuck at the default 0 dB; upward works"): a downward view-space drag from the
/// thumb centre must produce gains that DECREASE monotonically through 0 dB down to
/// −12 dB (never plateauing at centre), and an upward drag must reach +12 dB. It
/// runs the sweep at presentation scale 1.0, 1.5, and 2.0 — the classic scales the
/// windows use, including the fractional 1.5 introduced by the scale-1.5 commit —
/// because the defect was reported specifically at 1.5 and the isolated pure-layout
/// tests never fed a real view-space y through `skinPoint` at a fractional scale.
///
/// Pure arithmetic over `ControlHitTest` + `EQWindowLayout` (no window, no skin
/// file, no AppKit): the same functions the controller composes, so a regression in
/// EITHER the coordinate flip or the cursor→gain mapping fails here.
final class EQDragPipelineTests: XCTestCase {

    /// The classic presentation scales the drag must be correct at (integer 1/2 and
    /// the fractional 1.5 the classic windows render at).
    private let scales: [Double] = [1.0, 1.5, 2.0]

    /// A band column x (skin space) to sample the drag on — band 0's drawn centre,
    /// so the gate resolves to a real slider.
    private var bandCentreX: Int {
        EQWindowLayout.bandSliderXs[0] + eqThumbWidth / 2
    }

    private var eqThumbWidth: Int {
        SpriteCoordinates.equalizerWindow["eqmain.bmp"]?
            .first { $0.name == "sliderThumb" }?.width ?? 14
    }
    private var eqThumbHeight: Int {
        SpriteCoordinates.equalizerWindow["eqmain.bmp"]?
            .first { $0.name == "sliderThumb" }?.height ?? 11
    }

    /// The EQ window's view height in POINTS at a presentation scale: the classic
    /// window is sized `skinHeight * scale` in points (the `showEQWindow` content
    /// rect), which is the `viewHeight` the controller passes into `skinPoint`.
    private func viewHeight(scale: Double) -> Double {
        Double(EQWindowLayout.windowHeight) * scale
    }

    /// The view-space y (bottom-left origin, scaled points) whose `skinPoint`
    /// maps to a given skin-space `skinY` — the forward draw map
    /// `viewHeight - skinY*scale`, sampled at the skin row's CENTRE so the floor in
    /// `skinPoint` lands squarely on `skinY` (avoids straddling a pixel boundary at
    /// the fractional scale). This is how a cursor over skin row `skinY` reports.
    private func viewY(forSkinY skinY: Int, scale: Double) -> Double {
        // Centre of the skin row in view space: the row spans view y
        // [viewHeight - (skinY+1)*scale, viewHeight - skinY*scale); its midpoint
        // floors to exactly `skinY` under `skinPoint`.
        viewHeight(scale: scale) - (Double(skinY) + 0.5) * scale
    }

    /// Run the full pipeline for a raw view-space y at a scale: map to skin space,
    /// gate to a slider, and (if grabbed) compute the gain — returning both the
    /// resolved skinY and the gain, or `nil` gain when the gate rejects the point.
    private func pipeline(
        viewY: Double, scale: Double
    ) -> (skinY: Int, gain: Double?) {
        let viewH = viewHeight(scale: scale)
        let viewX = Double(bandCentreX) * scale + 0.5   // squarely on the column
        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewH, scale: scale
        )
        guard EQWindowLayout.slider(atSkinX: point.x, skinY: point.y) != nil else {
            return (point.y, nil)
        }
        return (point.y, EQWindowLayout.gain(forCursorSkinY: point.y))
    }

    // MARK: - Full-travel round-trip: view-space sweep spans +12..-12

    /// A view-space y sweep from the track TOP to the track BOTTOM must produce
    /// gains that span the full +12..-12 dB range, monotonically non-increasing as
    /// the cursor moves DOWN (view y decreases → screen goes down → gain drops).
    /// The critical assertions: the sweep REACHES +12 near the top and −12 near the
    /// bottom, and it PASSES THROUGH 0 without plateauing there (the bug's
    /// signature). Run at every classic scale.
    func testFullTravelSweepSpansPlusMinus12MonotonicallyAtEveryScale() {
        for scale in scales {
            // Skin rows covering the whole grab band [sliderTrackTop, sliderTrackBottom).
            let topRow = EQWindowLayout.sliderTrackTop
            let bottomRow = EQWindowLayout.sliderTrackBottom - 1

            var gains: [Double] = []
            var previous = Double.infinity
            // Sweep the cursor DOWNWARD on screen == skin y INCREASING == view y
            // DECREASING. Walk skin rows top→bottom so the physical motion is a
            // downward drag.
            for skinY in topRow...bottomRow {
                let vy = viewY(forSkinY: skinY, scale: scale)
                let result = pipeline(viewY: vy, scale: scale)
                XCTAssertEqual(
                    result.skinY, skinY,
                    "scale \(scale): view y for skin row \(skinY) must map back to \(skinY)")
                guard let gain = result.gain else {
                    XCTFail("scale \(scale): skin row \(skinY) is inside the grab band but was not grabbed")
                    continue
                }
                gains.append(gain)
                XCTAssertLessThanOrEqual(
                    gain, previous + 1e-9,
                    "scale \(scale): gain must not INCREASE on a downward drag (skinY \(skinY): \(gain) > \(previous))")
                previous = gain
            }

            guard let maxGain = gains.max(), let minGain = gains.min() else {
                XCTFail("scale \(scale): no gains sampled")
                continue
            }
            // The sweep reaches BOTH extremes — not saturating short of them.
            XCTAssertEqual(maxGain, 12, accuracy: 1e-6,
                           "scale \(scale): the top of the sweep must reach +12 dB")
            XCTAssertEqual(minGain, -12, accuracy: 1e-6,
                           "scale \(scale): the BOTTOM of the sweep must reach −12 dB (the down-drag bug)")
            // And it passes THROUGH the centre: some sample is near 0 dB, so the
            // slider is not stuck at either rail.
            XCTAssertTrue(
                gains.contains { abs($0) < 1.0 },
                "scale \(scale): the sweep must pass through ~0 dB, not jump rail-to-rail")
        }
    }

    // MARK: - The specific centre-and-below values the bug missed

    /// Pressing at the thumb CENTRE reads 0 dB, and every step DOWN from there
    /// produces a strictly more-negative gain — the exact behaviour the "stuck at
    /// default" report said was broken. Asserts concrete values at the centre and
    /// several rows below it, at every scale.
    func testDownwardFromCentreProducesNegativeGainsAtEveryScale() {
        // The thumb centre at 0 dB: the composer draws the thumb top at
        // `thumbTopY(0)`, so its centre row is `thumbTopY(0) + thumbHeight/2`.
        let centreSkinY = EQWindowLayout.thumbTopY(forGain: 0) + eqThumbHeight / 2

        for scale in scales {
            // At the centre the drag reads flat.
            let centre = pipeline(viewY: viewY(forSkinY: centreSkinY, scale: scale), scale: scale)
            XCTAssertEqual(centre.skinY, centreSkinY, "scale \(scale): centre row maps back")
            XCTAssertEqual(centre.gain ?? .nan, 0, accuracy: 1e-6,
                           "scale \(scale): pressing the thumb centre reads 0 dB")

            // Each row below the centre cuts further — never sticking at 0.
            var last = 0.0
            for delta in 1...(EQWindowLayout.sliderTrackBottom - 1 - centreSkinY) {
                let skinY = centreSkinY + delta
                let below = pipeline(viewY: viewY(forSkinY: skinY, scale: scale), scale: scale)
                guard let gain = below.gain else {
                    XCTFail("scale \(scale): row \(skinY) below centre must still be grabbable")
                    continue
                }
                XCTAssertLessThan(
                    gain, last + 1e-9,
                    "scale \(scale): row \(skinY) (below centre) must cut BELOW the row above it, not stick at 0")
                XCTAssertLessThan(gain, 0.0001,
                                  "scale \(scale): every row below centre is a CUT (< 0 dB), skinY \(skinY) gave \(gain)")
                last = gain
            }
            // The last grabbable row below centre bottoms out at −12 dB.
            XCTAssertEqual(last, -12, accuracy: 1e-6,
                           "scale \(scale): the bottom of the track reaches −12 dB")
        }
    }

    /// Symmetry: an UPWARD drag from the centre reaches +12 dB (the direction the
    /// bug report said already worked), so the fix keeps both directions correct.
    func testUpwardFromCentreReachesMaxBoostAtEveryScale() {
        let centreSkinY = EQWindowLayout.thumbTopY(forGain: 0) + eqThumbHeight / 2
        for scale in scales {
            var last = 0.0
            for delta in 1...(centreSkinY - EQWindowLayout.sliderTrackTop) {
                let skinY = centreSkinY - delta
                let above = pipeline(viewY: viewY(forSkinY: skinY, scale: scale), scale: scale)
                guard let gain = above.gain else { continue }
                XCTAssertGreaterThan(
                    gain, last - 1e-9,
                    "scale \(scale): row \(skinY) (above centre) must boost above the row below it")
                last = gain
            }
            XCTAssertEqual(last, 12, accuracy: 1e-6,
                           "scale \(scale): the top of the track reaches +12 dB")
        }
    }
}
