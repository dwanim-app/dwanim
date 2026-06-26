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

    // MARK: - Toggle on/off state art (spriteName(pressed:active:))
    //
    // The live window reflects a toggle's on/off state through
    // `spriteName(pressed:active:)`: a lit shuffle/repeat must select the `*On` /
    // `*OnPressed` art, an unlit one the `*Off` / `*OffPressed` art, and a
    // transport button must ignore `active` (no on/off state).

    func testToggleActiveSelectsOnArt() {
        XCTAssertEqual(
            SkinControl.toggleShuffle.spriteName(pressed: false, active: true).name,
            "shuffleOn", "active shuffle, released -> shuffleOn"
        )
        XCTAssertEqual(
            SkinControl.toggleShuffle.spriteName(pressed: true, active: true).name,
            "shuffleOnPressed", "active shuffle, pressed -> shuffleOnPressed"
        )
        XCTAssertEqual(
            SkinControl.toggleRepeat.spriteName(pressed: false, active: true).name,
            "repeatOn", "active repeat, released -> repeatOn"
        )
        XCTAssertEqual(
            SkinControl.toggleRepeat.spriteName(pressed: true, active: true).name,
            "repeatOnPressed", "active repeat, pressed -> repeatOnPressed"
        )
    }

    func testToggleInactiveSelectsOffArt() {
        XCTAssertEqual(
            SkinControl.toggleShuffle.spriteName(pressed: false, active: false).name,
            "shuffleOff", "inactive shuffle, released -> shuffleOff"
        )
        XCTAssertEqual(
            SkinControl.toggleShuffle.spriteName(pressed: true, active: false).name,
            "shuffleOffPressed", "inactive shuffle, pressed -> shuffleOffPressed"
        )
        XCTAssertEqual(
            SkinControl.toggleRepeat.spriteName(pressed: false, active: false).name,
            "repeatOff", "inactive repeat, released -> repeatOff"
        )
    }

    /// `active` is irrelevant for the five transport buttons — they have no on/off
    /// state, so `spriteName(pressed:active:)` must equal `spriteName(pressed:)`
    /// for any `active`.
    func testTransportButtonsIgnoreActive() {
        let transport: [SkinControl] = [.previous, .play, .pause, .stop, .next]
        for control in transport {
            for pressed in [false, true] {
                let plain = control.spriteName(pressed: pressed)
                for active in [false, true] {
                    let withActive = control.spriteName(pressed: pressed, active: active)
                    XCTAssertEqual(withActive.sheet, plain.sheet, "\(control) sheet")
                    XCTAssertEqual(
                        withActive.name, plain.name,
                        "\(control) (pressed \(pressed), active \(active)) ignores active"
                    )
                }
            }
        }
    }

    /// Every on/off, released/pressed toggle name must resolve to a real sprite —
    /// otherwise the on-state overlay would silently draw nothing.
    func testEveryToggleStateSpriteExists() {
        for control in [SkinControl.toggleShuffle, .toggleRepeat] {
            for active in [false, true] {
                for pressed in [false, true] {
                    let key = control.spriteName(pressed: pressed, active: active)
                    let sheet = SpriteCoordinates.mainWindow[key.sheet]
                    let exists = sheet?.contains { $0.name == key.name } ?? false
                    XCTAssertTrue(
                        exists,
                        "toggle sprite \(key.name) (active \(active), pressed \(pressed)) "
                            + "for \(control) not found in \(key.sheet)"
                    )
                }
            }
        }
    }
}
