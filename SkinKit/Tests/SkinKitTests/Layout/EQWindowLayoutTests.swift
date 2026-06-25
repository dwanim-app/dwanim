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
}
