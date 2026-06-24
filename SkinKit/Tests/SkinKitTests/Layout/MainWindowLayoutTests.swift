import Foundation
import XCTest
@testable import SkinKit

/// Guards the static main-window layout table: every placed element must
/// reference a real sprite in `SpriteCoordinates.mainWindow`, and its draw rect
/// (the destination position plus the sprite's nominal size) must fit entirely
/// within the 275x116 main window.
///
/// This is pure arithmetic over the two data tables — it reads no real skin
/// file. It exists so a future edit to `MainWindowLayout` cannot place an
/// element off-window or point it at a missing sprite without a test failing.
final class MainWindowLayoutTests: XCTestCase {

    /// Resolves the nominal pixel size of the sprite an element references,
    /// from `SpriteCoordinates.mainWindow`, or `nil` if the (sheet, sprite)
    /// pair is not a real key path.
    private func spriteSize(for element: WindowElement) -> (width: Int, height: Int)? {
        guard let rects = SpriteCoordinates.mainWindow[element.sheet],
              let rect = rects.first(where: { $0.name == element.sprite }) else {
            return nil
        }
        return (rect.width, rect.height)
    }

    func testEveryElementReferencesARealSprite() {
        for element in MainWindowLayout.elements {
            XCTAssertNotNil(
                spriteSize(for: element),
                "\(element.sheet)/\(element.sprite) is not a real sprite in "
                    + "SpriteCoordinates.mainWindow")
        }
    }

    func testEveryElementDrawRectFitsTheWindow() {
        let width = MainWindowLayout.windowWidth
        let height = MainWindowLayout.windowHeight

        for element in MainWindowLayout.elements {
            guard let size = spriteSize(for: element) else {
                continue // reported by testEveryElementReferencesARealSprite
            }
            XCTAssertGreaterThanOrEqual(
                element.x, 0, "\(element.sheet)/\(element.sprite): x must be >= 0")
            XCTAssertGreaterThanOrEqual(
                element.y, 0, "\(element.sheet)/\(element.sprite): y must be >= 0")
            XCTAssertLessThanOrEqual(
                element.x + size.width, width,
                "\(element.sheet)/\(element.sprite): right edge "
                    + "\(element.x + size.width) exceeds window width \(width)")
            XCTAssertLessThanOrEqual(
                element.y + size.height, height,
                "\(element.sheet)/\(element.sprite): bottom edge "
                    + "\(element.y + size.height) exceeds window height \(height)")
        }
    }

    /// The table should cover the standard static controls named in the brief:
    /// title bar, the five transport buttons, shuffle + repeat, the position
    /// track, the volume and balance backgrounds, and a mono/stereo indicator.
    func testTableCoversTheStandardStaticControls() {
        let pairs = Set(MainWindowLayout.elements.map { "\($0.sheet)/\($0.sprite)" })
        let expected = [
            "titlebar.bmp/titleBarActive",
            "cbuttons.bmp/previous",
            "cbuttons.bmp/play",
            "cbuttons.bmp/pause",
            "cbuttons.bmp/stop",
            "cbuttons.bmp/next",
            "shufrep.bmp/shuffleOff",
            "shufrep.bmp/repeatOff",
            "posbar.bmp/track",
            "monoster.bmp/stereoActive"
        ]
        for pair in expected {
            XCTAssertTrue(pairs.contains(pair), "layout is missing \(pair)")
        }
        // Volume and balance backgrounds are present (any level frame).
        XCTAssertTrue(
            MainWindowLayout.elements.contains { $0.sheet == "volume.bmp" },
            "layout is missing a volume slider background")
        XCTAssertTrue(
            MainWindowLayout.elements.contains { $0.sheet == "balance.bmp" },
            "layout is missing a balance slider background")
    }

    /// The visualization frame is a non-empty rect that fits entirely inside the
    /// 275x116 main window, so the spectrum renderer always draws in-bounds.
    func testVisualizationFrameFitsTheWindow() {
        let frame = MainWindowLayout.visualizationFrame
        XCTAssertGreaterThan(frame.width, 0, "vis frame width must be positive")
        XCTAssertGreaterThan(frame.height, 0, "vis frame height must be positive")
        XCTAssertGreaterThanOrEqual(frame.x, 0, "vis frame x must be >= 0")
        XCTAssertGreaterThanOrEqual(frame.y, 0, "vis frame y must be >= 0")
        XCTAssertLessThanOrEqual(
            frame.x + frame.width, MainWindowLayout.windowWidth,
            "vis frame right edge exceeds window width")
        XCTAssertLessThanOrEqual(
            frame.y + frame.height, MainWindowLayout.windowHeight,
            "vis frame bottom edge exceeds window height")
    }
}
