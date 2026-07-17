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
        .toggleRepeat:  ("shufrep.bmp", "repeatOff"),
        // Host-action buttons: EQ / PL default to their OFF art; eject / minimize
        // have a single released state.
        .eqButton:      ("titlebar.bmp", "eqButtonOff"),
        .plButton:      ("titlebar.bmp", "plButtonOff"),
        .eject:         ("cbuttons.bmp", "eject"),
        .minimize:      ("titlebar.bmp", "minimize")
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
    /// otherwise the on-state overlay would silently draw nothing. Covers the
    /// shuffle/repeat AND the EQ/PL on-state toggles.
    func testEveryToggleStateSpriteExists() {
        for control in [SkinControl.toggleShuffle, .toggleRepeat, .eqButton, .plButton] {
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

    // MARK: - Control kind (transport vs host-action)

    /// Each control reports the right kind: the five transport buttons + two
    /// toggles are `.transport`; the EQ / PL / eject / minimize buttons are
    /// `.hostAction`. This is what the controller uses to decide whether a click
    /// drives `PlayerControl.apply` or an injected host callback.
    func testControlKindClassification() {
        let transport: Set<SkinControl> = [.previous, .play, .pause, .stop, .next, .toggleShuffle, .toggleRepeat]
        let hostAction: Set<SkinControl> = [.eqButton, .plButton, .eject, .minimize]
        // The two sets partition allCases (no control is unclassified or in both).
        XCTAssertEqual(transport.union(hostAction), Set(SkinControl.allCases))
        XCTAssertTrue(transport.isDisjoint(with: hostAction))
        for control in transport {
            XCTAssertEqual(control.kind, .transport, "\(control) should be transport")
        }
        for control in hostAction {
            XCTAssertEqual(control.kind, .hostAction, "\(control) should be hostAction")
        }
    }

    // MARK: - EQ / PL on-state art (spriteName(pressed:active:))

    /// The EQ / PL buttons select their `*On` / `*OnPressed` art when active (their
    /// window is open) and `*Off` / `*OffPressed` otherwise — the same on/off
    /// pattern as shuffle/repeat, so the button lights while its window is open.
    func testEQPLActiveSelectsOnOffArt() {
        XCTAssertEqual(SkinControl.eqButton.spriteName(pressed: false, active: true).name, "eqButtonOn")
        XCTAssertEqual(SkinControl.eqButton.spriteName(pressed: true, active: true).name, "eqButtonOnPressed")
        XCTAssertEqual(SkinControl.eqButton.spriteName(pressed: false, active: false).name, "eqButtonOff")
        XCTAssertEqual(SkinControl.plButton.spriteName(pressed: false, active: true).name, "plButtonOn")
        XCTAssertEqual(SkinControl.plButton.spriteName(pressed: true, active: false).name, "plButtonOffPressed")
    }
}
