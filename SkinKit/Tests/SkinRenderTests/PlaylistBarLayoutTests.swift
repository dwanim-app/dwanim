import Foundation
import XCTest
@testable import SkinRender

/// Tests for the pure playlist bottom-bar hit table (`PlaylistBarLayout`): the
/// measured rects at the classic default size, corner GLUE across a resize
/// (left buttons keep x, right-glued rects follow the width; everything
/// follows the height), pairwise non-overlap at classic widths, fit inside the
/// bottom band, and the point hit-test.
final class PlaylistBarLayoutTests: XCTestCase {

    /// The classic default playlist window size (matches
    /// `PlaylistWindowGeometry` in SkinAppKit, restated here since this pure
    /// tier cannot import it).
    private let width = 275
    private let height = 232

    private func rect(
        _ control: PlaylistBarLayout.Control, w: Int? = nil, h: Int? = nil
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        PlaylistBarLayout.rect(for: control, canvasWidth: w ?? width, canvasHeight: h ?? height)
    }

    // MARK: - Measured rects at the classic default size (275 x 232)

    func testMenuButtonRectsMatchMeasuredArt() {
        // Left-glued 22x18 faces at x = 14/43/72/101 (29px pitch), tops 30px
        // above the bottom edge; LIST OPTS right-glued at W-43.
        XCTAssertTrue(rect(.addMenu) == (x: 14, y: 202, width: 22, height: 18))
        XCTAssertTrue(rect(.removeMenu) == (x: 43, y: 202, width: 22, height: 18))
        XCTAssertTrue(rect(.selectionMenu) == (x: 72, y: 202, width: 22, height: 18))
        XCTAssertTrue(rect(.miscMenu) == (x: 101, y: 202, width: 22, height: 18))
        XCTAssertTrue(rect(.listMenu) == (x: 232, y: 202, width: 22, height: 18))
    }

    func testMiniTransportRectsTileWithoutGapsAtMeasuredPositions() {
        // Right-glued micro buttons on the glyph band (tops 17px above the
        // bottom edge, 12px tall), tiling [W-147, W-89) with no gaps.
        XCTAssertTrue(rect(.miniPrevious) == (x: 128, y: 215, width: 10, height: 12))
        XCTAssertTrue(rect(.miniPlay) == (x: 138, y: 215, width: 10, height: 12))
        XCTAssertTrue(rect(.miniPause) == (x: 148, y: 215, width: 10, height: 12))
        XCTAssertTrue(rect(.miniStop) == (x: 158, y: 215, width: 10, height: 12))
        XCTAssertTrue(rect(.miniNext) == (x: 168, y: 215, width: 8, height: 12))
        XCTAssertTrue(rect(.miniEject) == (x: 176, y: 215, width: 10, height: 12))
    }

    // MARK: - Glue across resize

    func testLeftMenuButtonsKeepXAcrossAWidthResize() {
        for control: PlaylistBarLayout.Control in [.addMenu, .removeMenu, .selectionMenu, .miscMenu] {
            XCTAssertEqual(rect(control).x, rect(control, w: width + 137).x)
        }
    }

    func testRightGluedRectsFollowTheWidth() {
        let grow = 137
        for control: PlaylistBarLayout.Control in [
            .listMenu, .miniPrevious, .miniPlay, .miniPause, .miniStop, .miniNext, .miniEject
        ] {
            XCTAssertEqual(rect(control, w: width + grow).x, rect(control).x + grow)
        }
    }

    func testEveryRectFollowsTheHeight() {
        let grow = 89
        for control in PlaylistBarLayout.Control.allCases {
            XCTAssertEqual(rect(control, h: height + grow).y, rect(control).y + grow)
            XCTAssertEqual(rect(control, h: height + grow).x, rect(control).x)
        }
    }

    // MARK: - Fit + overlap

    /// Every rect stays inside the canvas AND inside the 38px bottom-frame band
    /// (where the baked button art lives), at the default and a stretched size.
    func testRectsFitInsideTheBottomBand() {
        for (w, h) in [(width, height), (width + 200, height + 150)] {
            for control in PlaylistBarLayout.Control.allCases {
                let r = PlaylistBarLayout.rect(for: control, canvasWidth: w, canvasHeight: h)
                XCTAssertGreaterThanOrEqual(r.x, 0)
                XCTAssertLessThanOrEqual(r.x + r.width, w, "\(control) overruns width \(w)")
                XCTAssertGreaterThanOrEqual(r.y, h - 38, "\(control) above the bottom band")
                XCTAssertLessThanOrEqual(r.y + r.height, h, "\(control) overruns height \(h)")
            }
        }
    }

    /// No two rects overlap at classic widths (>= 275, where the corner pieces
    /// do not collide). Half-open bounds.
    func testNoPairwiseOverlapAtClassicWidths() {
        for (w, h) in [(275, 232), (276, 186), (500, 400)] {
            let all = PlaylistBarLayout.Control.allCases
            for (i, a) in all.enumerated() {
                for b in all[(i + 1)...] {
                    let ra = PlaylistBarLayout.rect(for: a, canvasWidth: w, canvasHeight: h)
                    let rb = PlaylistBarLayout.rect(for: b, canvasWidth: w, canvasHeight: h)
                    let disjoint = ra.x + ra.width <= rb.x || rb.x + rb.width <= ra.x
                        || ra.y + ra.height <= rb.y || rb.y + rb.height <= ra.y
                    XCTAssertTrue(disjoint, "\(a) overlaps \(b) at \(w)x\(h)")
                }
            }
        }
    }

    // MARK: - Hit test

    func testHitTestFindsEveryControlAtItsRectCorners() {
        for control in PlaylistBarLayout.Control.allCases {
            let r = rect(control)
            // Top-left corner (inclusive).
            XCTAssertEqual(
                PlaylistBarLayout.control(atX: r.x, y: r.y, canvasWidth: width, canvasHeight: height),
                control
            )
            // Bottom-right interior pixel (half-open bounds).
            XCTAssertEqual(
                PlaylistBarLayout.control(
                    atX: r.x + r.width - 1, y: r.y + r.height - 1,
                    canvasWidth: width, canvasHeight: height
                ),
                control
            )
        }
    }

    func testHitTestMissesOutsideTheButtons() {
        // The interior (track list) well above the bar.
        XCTAssertNil(PlaylistBarLayout.control(atX: 100, y: 100, canvasWidth: width, canvasHeight: height))
        // Between MISC and the mini transport.
        XCTAssertNil(PlaylistBarLayout.control(atX: 125, y: 205, canvasWidth: width, canvasHeight: height))
        // One pixel past a half-open right edge.
        let r = rect(.addMenu)
        XCTAssertNil(PlaylistBarLayout.control(
            atX: r.x + r.width, y: r.y, canvasWidth: width, canvasHeight: height
        ))
        // The resize-grip corner at the very bottom-right.
        XCTAssertNil(PlaylistBarLayout.control(
            atX: width - 3, y: height - 3, canvasWidth: width, canvasHeight: height
        ))
    }

    func testHitTestFollowsAResize() {
        // LIST OPTS stays under the cursor glued to the right edge after growing.
        let w = width + 60
        let r = PlaylistBarLayout.rect(for: .listMenu, canvasWidth: w, canvasHeight: height)
        XCTAssertEqual(
            PlaylistBarLayout.control(
                atX: r.x + 5, y: r.y + 5, canvasWidth: w, canvasHeight: height
            ),
            .listMenu
        )
        // The OLD (default-width) position is empty space at the wider size.
        XCTAssertNil(PlaylistBarLayout.control(atX: 232, y: 202, canvasWidth: w, canvasHeight: height))
    }
}
