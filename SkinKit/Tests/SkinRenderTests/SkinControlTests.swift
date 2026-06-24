import Foundation
import XCTest
@testable import SkinRender
import SkinKit

/// Exercises `SkinControl.spriteName(pressed:)`, the unified released/pressed
/// sprite-name table that is the single source of truth shared by the hit-test
/// layout lookup and the interactive pressed-button overlay. Asserts the
/// expected `(sheet, name)` pairs and that every named sprite actually exists in
/// `SpriteCoordinates`, so the table cannot name a sprite the format does not
/// define. No graphics framework is touched.
final class SkinControlTests: XCTestCase {

    // MARK: - Expected names (released)

    /// The released `(sheet, name)` each control should report. Mirrors the
    /// documented mapping; pressed names are derived by appending "Pressed".
    private static let expectedReleased: [SkinControl: (sheet: String, name: String)] = [
        .previous:      ("cbuttons.bmp", "previous"),
        .play:          ("cbuttons.bmp", "play"),
        .pause:         ("cbuttons.bmp", "pause"),
        .stop:          ("cbuttons.bmp", "stop"),
        .next:          ("cbuttons.bmp", "next"),
        .toggleShuffle: ("shufrep.bmp", "shuffleOff"),
        .toggleRepeat:  ("shufrep.bmp", "repeatOff")
    ]

    func testReleasedSpriteNamesMatchExpected() {
        for (control, expected) in Self.expectedReleased {
            let key = control.spriteName(pressed: false)
            XCTAssertEqual(key.sheet, expected.sheet, "released sheet for \(control)")
            XCTAssertEqual(key.name, expected.name, "released name for \(control)")
        }
    }

    func testPressedSpriteNamesAppendPressedSuffix() {
        for (control, expected) in Self.expectedReleased {
            let key = control.spriteName(pressed: true)
            XCTAssertEqual(key.sheet, expected.sheet, "pressed sheet for \(control)")
            XCTAssertEqual(
                key.name,
                expected.name + "Pressed",
                "pressed name for \(control) should be the released name + Pressed"
            )
        }
    }

    // MARK: - Spot checks (explicit pairs)

    func testSpotCheckSpecificPairs() {
        XCTAssertEqual(SkinControl.play.spriteName(pressed: false).name, "play")
        XCTAssertEqual(SkinControl.play.spriteName(pressed: true).name, "playPressed")
        XCTAssertEqual(SkinControl.toggleShuffle.spriteName(pressed: false).name, "shuffleOff")
        XCTAssertEqual(SkinControl.toggleShuffle.spriteName(pressed: true).name, "shuffleOffPressed")
        XCTAssertEqual(SkinControl.toggleRepeat.spriteName(pressed: true).name, "repeatOffPressed")
    }

    // MARK: - Every named sprite exists in SpriteCoordinates

    /// Both the released and pressed names for every control must resolve to a
    /// real sprite in `SpriteCoordinates.mainWindow` — otherwise the harness's
    /// pressed-overlay would silently draw nothing and the hit-test rect could
    /// not be derived.
    func testEverySpriteNameExistsInSpriteCoordinates() {
        for control in SkinControl.allCases {
            for pressed in [false, true] {
                let key = control.spriteName(pressed: pressed)
                let sheet = SpriteCoordinates.mainWindow[key.sheet]
                XCTAssertNotNil(sheet, "sheet \(key.sheet) for \(control) missing")
                let exists = sheet?.contains { $0.name == key.name } ?? false
                XCTAssertTrue(
                    exists,
                    "sprite \(key.name) (pressed: \(pressed)) for \(control) "
                        + "not found in \(key.sheet)"
                )
            }
        }
    }
}
