import Foundation
import XCTest
@testable import PlayerCore

/// Pins the DIRECTION of the unplayable-file recovery walk, for the case where
/// the file will not OPEN at all. Its sibling
/// `PlayerCoreSilentTrackNavigationTests` covers the other kind of unplayable
/// file — one that opens and then renders nothing — which reaches the same walk
/// from the finish callback rather than from `load`'s `catch`.
///
/// ## The defect this file exists for
/// `playCurrent()` skips a track the engine cannot load. That recovery used to
/// walk FORWARD unconditionally — including when it was reached from
/// `previous()`. So a `◀◀` press onto a dead file put the listener back on the
/// track they had just come from, and one dead file made every track before it
/// permanently unreachable with `◀◀`:
///
/// ```
/// queue: t0 t1 t2 [t3 = dead] t4 t5 t6      repeat .off, parked on t4
/// ◀◀ -> 3 (dead) -> forward recovery -> 4   (back where we started)
/// ◀◀ -> 3 (dead) -> forward recovery -> 4   ...for ever
/// ```
///
/// `▶▶` was never affected (it steps OVER the dead file correctly), so the model
/// was silently asymmetric: the same queue walked forwards fine and backwards not
/// at all. `canGoPrevious` said `true` for every one of those inert presses, so
/// the control neither dimmed nor acted — the very "looks live but does nothing"
/// symptom the transport work set out to remove.
///
/// ## The contract these tests pin
/// - `◀◀` recovery walks BACKWARD (`previousPlayableCursor(before:)`), mirroring
///   `▶▶`'s forward walk, so an explicit skip NEVER moves the listener the other
///   way. Both honour the same `.off`/`.one` = no-wrap, `.all` = wrap policy.
/// - `▶▶` / `play()` / `select()` recovery still walks FORWARD (regression guard).
/// - The terminal case is stated, not left to chance: when nothing earlier is
///   playable, `◀◀` comes to rest (stop) rather than sweeping the queue.
@MainActor
final class PlayerCoreUnplayableNavigationTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    private func makeCore(_ engine: FakePlaybackEngine, tracks: Int) -> PlayerCore {
        let core = PlayerCore(engine: engine)
        core.load((0..<tracks).map { track("t\($0)") })
        return core
    }

    // MARK: - The reported defect

    /// The deterministic form of the real-audio repro: seven tracks, ONE dead
    /// file at index 3, parked on index 4. Six `◀◀` presses must walk the queue
    /// home (2, 1, 0, then restart in place), never bounce forward.
    ///
    /// Before the fix the observed trail was `[4, 4, 4, 4, 4, 4]` — every press
    /// landed back on the track the listener had just left.
    func testPreviousStepsBackOverADeadFileInsteadOfBouncingForward() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 7)
        engine.unloadableURLs = [track("t3").url]
        core.repeatMode = .off
        core.select(4)
        XCTAssertEqual(core.currentIndex, 4, "precondition: parked on t4")

        var trail: [Int] = []
        for press in 1...6 {
            XCTAssertTrue(core.canGoPrevious, "press \(press): ◀◀ claims it can act")
            core.previous()
            trail.append(core.currentIndex ?? -1)
        }

        XCTAssertEqual(trail, [2, 1, 0, 0, 0, 0],
                       "◀◀ steps BACK over the dead t3 (4 -> 2), walks home, then restarts t0 in place")
        XCTAssertTrue(core.isPlaying, "every one of those presses landed on a playable track")
        XCTAssertEqual(core.currentTrack, track("t0"))
    }

    /// The single press, asserted on its own: the dead file is stepped OVER
    /// backwards, and the engine really loaded the track two rows back.
    func testASinglePreviousOverADeadFileLandsOnTheTrackBeforeIt() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 5)
        engine.unloadableURLs = [track("t2").url]
        core.select(3)
        engine.resetRecordedCalls()

        core.previous()

        XCTAssertEqual(core.currentIndex, 1, "3 -> (2 is dead) -> 1")
        XCTAssertEqual(engine.loadedURLs, [track("t2").url, track("t1").url],
                       "the dead file was tried once, then the walk went BACKWARD")
        XCTAssertTrue(core.isPlaying)
    }

    /// A consecutive RUN of dead files is stepped over in one press, not one
    /// press per corpse.
    func testPreviousSkipsAWholeRunOfDeadFilesInASinglePress() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 6)
        engine.unloadableURLs = [track("t1").url, track("t2").url, track("t3").url]
        core.select(4)

        core.previous()

        XCTAssertEqual(core.currentIndex, 0, "4 -> (3, 2, 1 all dead) -> 0")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(core.currentTrack, track("t0"))
    }

    // MARK: - The wrap policy, mirrored

    /// With `.all` the backward recovery wraps exactly like the forward one: a
    /// `◀◀` from the first track wraps to the last, and if THAT is dead the walk
    /// keeps going backwards from there.
    func testBackwardRecoveryWrapsUnderRepeatAll() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 4)
        engine.unloadableURLs = [track("t3").url]
        core.repeatMode = .all
        core.select(0)
        engine.resetRecordedCalls()

        core.previous()

        XCTAssertEqual(core.currentIndex, 2, "0 -> wraps to 3 (dead) -> 2")
        XCTAssertEqual(engine.loadedURLs, [track("t3").url, track("t2").url])
        XCTAssertTrue(core.isPlaying)
    }

    /// `.one` wraps for the explicit press (like `.all`) but, like `.off`, does
    /// NOT wrap the RECOVERY walk — the same asymmetry `nextPlayableCursor`
    /// already documents, so a queue of dead files comes to rest instead of
    /// sweeping round a second time.
    func testBackwardRecoveryDoesNotWrapUnderRepeatOne() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 4)
        engine.unloadableURLs = [track("t0").url]
        core.repeatMode = .one
        core.select(1)
        engine.resetRecordedCalls()

        core.previous()

        XCTAssertEqual(engine.loadedURLs, [track("t0").url],
                       "the walk stops at the front rather than wrapping to t3")
        XCTAssertFalse(core.isPlaying, "nothing playable behind the cursor -> stop")
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }

    /// The terminal case, stated rather than implied: repeat off, everything
    /// before the cursor is dead. `◀◀` comes to rest — it must not sweep forward
    /// looking for something to play.
    func testPreviousStopsWhenNothingEarlierIsPlayableUnderRepeatOff() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 4)
        engine.unloadableURLs = [track("t0").url, track("t1").url, track("t2").url]
        core.repeatMode = .off
        core.select(3)
        engine.resetRecordedCalls()

        core.previous()

        XCTAssertEqual(engine.loadedURLs, [track("t2").url, track("t1").url, track("t0").url],
                       "it walked backwards only, and tried each corpse exactly once")
        XCTAssertFalse(core.isPlaying)
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }

    /// Restart-in-place (repeat off, first track) recovers BACKWARD too, so the
    /// press cannot smuggle the listener forward: a dead t0 stops instead of
    /// starting t1.
    func testRestartInPlaceOnADeadFirstTrackDoesNotJumpForward() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 3)
        engine.unloadableURLs = [track("t0").url]
        core.repeatMode = .off
        core.select(0)
        engine.resetRecordedCalls()

        core.previous()

        XCTAssertNotEqual(core.currentIndex, 1, "◀◀ never moves the listener FORWARD")
        XCTAssertFalse(core.isPlaying)
    }

    // MARK: - Regression guards: forward recovery is unchanged

    /// `▶▶` over a dead file still steps FORWARD — the direction fix must not
    /// have been applied globally.
    func testNextOverADeadFileStillWalksForward() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 5)
        engine.unloadableURLs = [track("t2").url]
        core.select(1)
        engine.resetRecordedCalls()

        core.next()

        XCTAssertEqual(core.currentIndex, 3, "1 -> (2 is dead) -> 3")
        XCTAssertEqual(engine.loadedURLs, [track("t2").url, track("t3").url])
        XCTAssertTrue(core.isPlaying)
    }

    /// `select()` (a playlist double-click) and `play()` still recover FORWARD.
    func testSelectAndPlayStillRecoverForward() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 4)
        engine.unloadableURLs = [track("t0").url, track("t2").url]

        core.select(2)
        XCTAssertEqual(core.currentIndex, 3, "select onto a dead track skips forward")

        let other = FakePlaybackEngine()
        let core2 = makeCore(other, tracks: 4)
        other.unloadableURLs = [track("t0").url]
        core2.play()
        XCTAssertEqual(core2.currentIndex, 1, "play() from a dead t0 skips forward")
    }

    /// Auto-advance is `next()`, so it keeps the forward walk even though the
    /// listener's last explicit press may have been `◀◀`.
    func testAutoAdvanceOverADeadFileStillWalksForward() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine, tracks: 5)
        engine.unloadableURLs = [track("t3").url]
        core.repeatMode = .off
        core.select(1)
        core.previous()                       // the backward walk happened first
        XCTAssertEqual(core.currentIndex, 0)
        core.select(2)
        engine.resetRecordedCalls()

        engine.fireFinished()                 // t2 ends -> auto-advance

        XCTAssertEqual(core.currentIndex, 4, "2 -> (3 is dead) -> 4, forward as ever")
        XCTAssertTrue(core.isPlaying)
    }
}
