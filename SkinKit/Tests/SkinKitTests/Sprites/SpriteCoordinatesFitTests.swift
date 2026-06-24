import Foundation
import XCTest
@testable import SkinKit

/// Permanent guard that every sprite rectangle in the main-window table fits
/// within the **real** measured sheet dimensions. These standard dimensions were
/// measured across a large corpus of real classic `.wsz` skins; where a sheet
/// size varied between skins, the SMALLER value is used here so that any rect
/// fitting this table is guaranteed to fit every observed skin.
///
/// This is pure arithmetic — it does not read any real skin file. It exists so
/// that a future edit to `SpriteCoordinates` cannot reintroduce an over-bounds
/// rectangle without a test failing.
final class SpriteCoordinatesFitTests: XCTestCase {

    /// Standard (smallest observed) sheet dimensions, in pixels: sheet filename
    /// -> (width, height). A rect on a sheet must satisfy
    /// `x >= 0, y >= 0, x + width <= STD_WIDTH, y + height <= STD_HEIGHT`.
    private static let standardDimensions: [String: (width: Int, height: Int)] = [
        "main.bmp":     (275, 116),
        "cbuttons.bmp": (136, 36),
        "titlebar.bmp": (344, 87),
        "shufrep.bmp":  (92, 85),
        "posbar.bmp":   (307, 10),
        "numbers.bmp":  (99, 13),
        "monoster.bmp": (58, 24),
        "playpaus.bmp": (42, 9),
        // volume/balance ship as 68x420 (some skins 68x433); rects must fit 420.
        "volume.bmp":   (68, 420),
        "balance.bmp":  (68, 420),
        // text.bmp is 155 wide; height varies (18 / 73 / 74). Use the SMALLEST
        // observed height so any rect fitting here fits every real sheet.
        "text.bmp":     (155, 18)
    ]

    func testEverySpriteRectFitsItsStandardSheetDimensions() {
        for (sheet, rects) in SpriteCoordinates.mainWindow {
            guard let dims = Self.standardDimensions[sheet] else {
                XCTFail("no standard dimensions declared for sheet \(sheet)")
                continue
            }
            for rect in rects {
                XCTAssertGreaterThanOrEqual(
                    rect.x, 0, "\(sheet)/\(rect.name): x must be >= 0")
                XCTAssertGreaterThanOrEqual(
                    rect.y, 0, "\(sheet)/\(rect.name): y must be >= 0")
                XCTAssertLessThanOrEqual(
                    rect.x + rect.width, dims.width,
                    "\(sheet)/\(rect.name): right edge \(rect.x + rect.width) "
                        + "exceeds sheet width \(dims.width)")
                XCTAssertLessThanOrEqual(
                    rect.y + rect.height, dims.height,
                    "\(sheet)/\(rect.name): bottom edge \(rect.y + rect.height) "
                        + "exceeds sheet height \(dims.height)")
            }
        }
    }

    /// Every sheet declared in the coordinate table must have a standard-size
    /// entry here, so a newly added sheet cannot silently skip the fit check.
    func testEveryTableSheetHasStandardDimensions() {
        for sheet in SpriteCoordinates.mainWindow.keys {
            XCTAssertNotNil(
                Self.standardDimensions[sheet],
                "sheet \(sheet) is in the coordinate table but has no standard "
                    + "dimensions in the fit test")
        }
    }
}
