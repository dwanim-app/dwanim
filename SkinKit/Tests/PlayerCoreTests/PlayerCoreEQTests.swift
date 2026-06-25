import Foundation
import XCTest
@testable import PlayerCore

// MARK: - PlayerCoreEQTests

/// Tests that `PlayerCore` exposes the equalizer as observable state and mirrors
/// every change to an engine that opts in to `AudioEqualizing` — the EQ analogue
/// of the `setVolume -> engine.volume` flow. A `FakePlaybackEngine` (no EQ
/// conformance) proves the cast is a safe no-op for engines that do not support
/// equalization.
@MainActor
final class PlayerCoreEQTests: XCTestCase {

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    // MARK: - Default

    func testEqualizerDefaultsFlatAndDisabled() {
        let core = PlayerCore(engine: EqualizingFakeEngine())
        XCTAssertEqual(core.equalizer, EQState())
        XCTAssertFalse(core.equalizer.enabled)
    }

    // MARK: - Mutators push to the engine

    func testSetEQEnabledMirrorsToEngine() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        core.setEQEnabled(true)
        XCTAssertTrue(core.equalizer.enabled)
        XCTAssertEqual(engine.lastApplied?.enabled, true,
                       "enabling pushes the new state to the engine")
    }

    func testSetEQBandClampsAndMirrorsToEngine() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        core.setEQBand(0, dB: 100) // clamps to +12
        XCTAssertEqual(core.equalizer.bands[0], 12)
        XCTAssertEqual(engine.lastApplied?.bands[0], 12,
                       "the clamped band gain reaches the engine")
    }

    func testSetEQPreampClampsAndMirrorsToEngine() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        core.setEQPreamp(-100) // clamps to -12
        XCTAssertEqual(core.equalizer.preamp, -12)
        XCTAssertEqual(engine.lastApplied?.preamp, -12)
    }

    func testSetEQBandOutOfRangeDoesNotPushInvalidState() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        core.setEQBand(99, dB: 6) // guarded no-op
        // State is unchanged; even if a push fires, it carries the still-flat state.
        XCTAssertEqual(core.equalizer, EQState())
        if let applied = engine.lastApplied {
            XCTAssertEqual(applied, EQState(),
                           "an out-of-range band must not corrupt the pushed state")
        }
    }

    func testSetEqualizerReplacesWholeStateAndMirrors() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        let preset = EQState(enabled: true, preamp: 3, bands: Array(repeating: 6, count: 10))
        core.setEqualizer(preset)
        XCTAssertEqual(core.equalizer, preset)
        XCTAssertEqual(engine.lastApplied, preset)
    }

    // MARK: - Re-applied on load

    func testEqualizerIsReappliedOnTrackLoad() {
        let engine = EqualizingFakeEngine()
        let core = PlayerCore(engine: engine)
        core.setEQEnabled(true)
        core.setEQBand(2, dB: 9)
        let pushesBeforeLoad = engine.applyCount

        core.load([track("a"), track("b")])
        core.play() // loads track "a"

        XCTAssertGreaterThan(
            engine.applyCount,
            pushesBeforeLoad,
            "loading a track re-pushes the EQ state to the re-wired engine graph"
        )
        XCTAssertEqual(
            engine.lastApplied?.bands[2],
            9,
            "the re-applied state carries the dialed-in band"
        )
    }

    // MARK: - Non-conforming engine is a safe no-op

    func testNonEqualizingEngineIsSafeNoOp() {
        // FakePlaybackEngine does NOT conform to AudioEqualizing.
        let engine = FakePlaybackEngine()
        let core = PlayerCore(engine: engine)
        // None of these should crash or have any effect on the engine.
        core.setEQEnabled(true)
        core.setEQBand(0, dB: 12)
        core.setEQPreamp(6)
        XCTAssertTrue(core.equalizer.enabled, "core still tracks its own state")
        XCTAssertEqual(core.equalizer.bands[0], 12)
    }
}
