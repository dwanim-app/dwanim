import Foundation
import XCTest
@testable import PlayerCore

// MARK: - PlayerCoreEQInteractionEnablesTests
//
// F5 — the EQ bank must never be a dead block. On a fresh install the equalizer
// defaults OFF, and the default face used to `.disabled` every preset and slider
// until the user found the tiny On checkbox — App Review read that as "adjustment
// buttons unresponsive". The rule now lives in the MODEL: adjusting a band or the
// preamp (a slider drag, or a preset applied through the same setters) is an intent
// to hear it, so it turns the equalizer ON. Whole-state replacement (`setEqualizer`,
// e.g. restoring a saved state) and the explicit on/off switch are untouched.
@MainActor
final class PlayerCoreEQInteractionEnablesTests: XCTestCase {

    func testAdjustingABandTurnsTheEqualizerOn() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        XCTAssertFalse(core.equalizer.enabled, "precondition: a fresh equalizer is off")

        core.setEQBand(3, dB: 6)

        XCTAssertTrue(core.equalizer.enabled, "touching a band is an intent to hear it")
        XCTAssertEqual(core.equalizer.bands[3], 6)
        XCTAssertEqual(engine.lastApplied?.enabled, true,
                       "the engine receives the ENABLED state with the new gain")
        XCTAssertEqual(engine.lastApplied?.bands[3], 6)
    }

    func testAdjustingThePreampTurnsTheEqualizerOn() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)

        core.setEQPreamp(-3)

        XCTAssertTrue(core.equalizer.enabled)
        XCTAssertEqual(engine.lastApplied?.enabled, true)
        XCTAssertEqual(engine.lastApplied?.preamp, -3)
    }

    func testAnIgnoredAdjustmentDoesNotTurnTheEqualizerOn() {
        let core = PlayerCore(engine: EqualizingFakeEngine())

        core.setEQBand(99, dB: 6)      // out-of-range index: guarded no-op
        core.setEQBand(0, dB: .nan)    // non-finite: guarded no-op
        core.setEQPreamp(.infinity)    // non-finite: guarded no-op

        XCTAssertEqual(core.equalizer, EQState(),
                       "a rejected adjustment changes nothing — including the switch")
    }

    func testTheExplicitSwitchStillTurnsItOffAfterAnAdjustment() {
        let core = PlayerCore(engine: EqualizingFakeEngine())
        core.setEQBand(0, dB: 4)
        XCTAssertTrue(core.equalizer.enabled)

        core.setEQEnabled(false)

        XCTAssertFalse(core.equalizer.enabled, "the checkbox still toggles")
        XCTAssertEqual(core.equalizer.bands[0], 4, "…and keeps the dialed-in gain")
    }

    func testWholeStateReplacementDoesNotForceEnable() {
        let core = PlayerCore(engine: EqualizingFakeEngine())

        core.setEqualizer(EQState(enabled: false, preamp: 2, bands: [1, 2, 3]))

        XCTAssertFalse(core.equalizer.enabled,
                       "restoring a saved OFF state is not an interaction")
    }

    func testAdjustingWhileAlreadyOnLeavesItOn() {
        let core = PlayerCore(engine: EqualizingFakeEngine())
        core.setEQEnabled(true)

        core.setEQBand(5, dB: -2)

        XCTAssertTrue(core.equalizer.enabled)
    }
}
