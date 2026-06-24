import Foundation
import XCTest
import PlayerCore
import SkinRender
@testable import PlayerControl

/// Tests for `PlayerControl`, the pure `SkinControl` -> `PlayerCore` mapping
/// lifted out of the interactive harness. A `FakePlaybackEngine` stands in for
/// the real audio engine so every mapping is asserted in memory; `nextRepeatMode`
/// is verified as a pure cycle. No graphics / audio framework is touched.
final class PlayerControlTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    /// A core preloaded with three tracks (so `next`/`previous` can move) over a
    /// returned fake engine, selection clamped to index 0.
    private func makeLoadedCore() -> (core: PlayerCore, engine: FakePlaybackEngine) {
        let engine = FakePlaybackEngine()
        let core = PlayerCore(engine: engine)
        core.load([track("a"), track("b"), track("c")])
        return (core, engine)
    }

    // MARK: - .play

    func testPlayStartsTheEngine() {
        let (core, engine) = makeLoadedCore()

        PlayerControl.apply(.play, to: core)

        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.playCount, 1, ".play should start the engine")
    }

    // MARK: - .pause

    func testPausePausesTheEngine() {
        let (core, engine) = makeLoadedCore()
        PlayerControl.apply(.play, to: core)

        PlayerControl.apply(.pause, to: core)

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.pauseCount, 1, ".pause should pause the engine")
    }

    // MARK: - .stop -> pause then seek(0)

    func testStopPausesThenSeeksToZero() {
        let (core, engine) = makeLoadedCore()
        PlayerControl.apply(.play, to: core)
        engine.currentTime = 42

        PlayerControl.apply(.stop, to: core)

        XCTAssertFalse(core.isPlaying, ".stop should pause")
        XCTAssertEqual(engine.pauseCount, 1, ".stop should pause exactly once")
        XCTAssertEqual(engine.seekedTimes, [0], ".stop should seek to 0")
        XCTAssertEqual(engine.currentTime, 0, "position should rewind to 0")
    }

    // MARK: - .next

    func testNextAdvancesSelection() {
        let (core, _) = makeLoadedCore()
        XCTAssertEqual(core.currentIndex, 0)

        PlayerControl.apply(.next, to: core)

        XCTAssertEqual(core.currentIndex, 1, ".next should advance to the next track")
    }

    // MARK: - .previous

    func testPreviousMovesSelectionBack() {
        let (core, _) = makeLoadedCore()
        core.select(2)

        PlayerControl.apply(.previous, to: core)

        XCTAssertEqual(core.currentIndex, 1, ".previous should step back a track")
    }

    // MARK: - .toggleShuffle

    func testToggleShuffleFlipsIsShuffle() {
        let (core, _) = makeLoadedCore()
        XCTAssertFalse(core.isShuffle)

        PlayerControl.apply(.toggleShuffle, to: core)
        XCTAssertTrue(core.isShuffle, ".toggleShuffle should turn shuffle on")

        PlayerControl.apply(.toggleShuffle, to: core)
        XCTAssertFalse(core.isShuffle, ".toggleShuffle should turn shuffle back off")
    }

    // MARK: - .toggleRepeat cycles through all three modes

    func testToggleRepeatCyclesOffAllOneOff() {
        let (core, _) = makeLoadedCore()
        XCTAssertEqual(core.repeatMode, .off)

        PlayerControl.apply(.toggleRepeat, to: core)
        XCTAssertEqual(core.repeatMode, .all, "off -> all")

        PlayerControl.apply(.toggleRepeat, to: core)
        XCTAssertEqual(core.repeatMode, .one, "all -> one")

        PlayerControl.apply(.toggleRepeat, to: core)
        XCTAssertEqual(core.repeatMode, .off, "one -> off")
    }

    // MARK: - nextRepeatMode pure cycle

    func testNextRepeatModeIsAPureCycle() {
        XCTAssertEqual(PlayerControl.nextRepeatMode(.off), .all)
        XCTAssertEqual(PlayerControl.nextRepeatMode(.all), .one)
        XCTAssertEqual(PlayerControl.nextRepeatMode(.one), .off)
    }
}
