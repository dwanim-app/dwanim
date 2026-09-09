import Foundation
import XCTest
@testable import PlayerCore

/// Pins `PlayerCore.canGoNext` / `canGoPrevious` — the model-side predicates the
/// Cadence transport row disables `▶▶` / `◀◀` from.
///
/// ## Why the predicates live HERE and not in the view
/// The reported complaint was a control that LOOKS live but is inert. The
/// condition for "this press cannot do anything" is a property of the transport
/// policy (playlist size, selection, `repeatMode`, `isShuffle`), so it is derived
/// once in the model and merely rendered by the view. Duplicating the branch
/// logic in SwiftUI would let the two drift — the dimming would be right until
/// someone changed `next()`.
///
/// ## The contract, stated once
/// `canGoNext` / `canGoPrevious` answer: *would a press produce an observable
/// change?* A press that merely re-issues `stop()` on an already-stopped engine
/// is NOT observable, which is exactly the end-of-queue case the owner reported.
///
/// The `.off` end-of-queue STOP (playing the last track, `▶▶` halts playback) is
/// deliberately counted as NOT-available: the owner chose to dim `▶▶` there, and
/// the ■ button remains the way to stop. That decision is asserted below rather
/// than left implicit.
@MainActor
final class PlayerCoreTransportAvailabilityTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    private func core(_ engine: FakePlaybackEngine = FakePlaybackEngine(),
                      tracks: Int,
                      shuffleStrategy: @escaping PlayerCore.ShuffleStrategy = PlayerCore.defaultShuffleStrategy)
        -> PlayerCore {
        let core = PlayerCore(engine: engine, shuffleStrategy: shuffleStrategy)
        core.load((0..<tracks).map { track("t\($0)") })
        return core
    }

    // MARK: - Empty queue

    /// An empty playlist has no selection, so BOTH skips are guarded no-ops in
    /// `next()`/`previous()` and both predicates must be false.
    func testEmptyPlaylistDisablesBothSkips() {
        let player = core(tracks: 0)
        XCTAssertNil(player.currentIndex)
        XCTAssertFalse(player.canGoNext)
        XCTAssertFalse(player.canGoPrevious)
    }

    /// `removeAll()` must return the predicates to the empty-queue answer (this is
    /// the live path a user hits with Clear Queue while a track is playing).
    func testClearingAQueueMidPlaybackDisablesBothSkips() {
        let player = core(tracks: 3)
        player.select(1)
        XCTAssertTrue(player.canGoNext)

        player.removeAll()

        XCTAssertFalse(player.canGoNext)
        XCTAssertFalse(player.canGoPrevious)
    }

    // MARK: - Sequential, repeat OFF

    /// Mid-list with repeat off: both directions act, so both are enabled.
    func testMidListWithRepeatOffEnablesBothSkips() {
        let player = core(tracks: 3)
        player.repeatMode = .off
        player.select(1)

        XCTAssertTrue(player.canGoNext)
        XCTAssertTrue(player.canGoPrevious)
    }

    /// The owner's reported case: parked on the LAST track with repeat off, `▶▶`
    /// cannot reach another track, so it is disabled.
    func testLastTrackWithRepeatOffDisablesNext() {
        let player = core(tracks: 3)
        player.repeatMode = .off
        player.select(2)

        XCTAssertFalse(player.canGoNext, "▶▶ at the end of the queue with repeat off is dead")
        XCTAssertTrue(player.canGoPrevious, "◀◀ still steps back")
    }

    /// ...and that holds while the last track is still PLAYING, not only after it
    /// finished. `next()` there would stop playback, which IS audible — but the
    /// owner's decision is that ■ owns stopping and `▶▶` must not double as a
    /// stop button. Asserted explicitly so the choice is not mistaken for an
    /// oversight.
    func testLastTrackWithRepeatOffDisablesNextEvenWhilePlaying() {
        let engine = FakePlaybackEngine()
        let player = core(engine, tracks: 3)
        player.repeatMode = .off
        player.select(2)
        XCTAssertTrue(player.isPlaying, "precondition: the last track is playing")

        XCTAssertFalse(player.canGoNext, "▶▶ is dimmed at the end even while playing (■ stops)")
    }

    /// The FIRST track with repeat off: `◀◀` restarts the track in place, which is
    /// an observable action (the position jumps back to 0), so it stays ENABLED.
    /// This is the deliberate `.off` asymmetry, seen from the availability side.
    func testFirstTrackWithRepeatOffKeepsPreviousEnabledBecauseItRestarts() {
        let engine = FakePlaybackEngine()
        let player = core(engine, tracks: 3)
        player.repeatMode = .off
        player.select(0)

        XCTAssertTrue(player.canGoPrevious, "◀◀ at the front restarts the track — a real action")
        XCTAssertTrue(player.canGoNext)

        // And the action really is observable: a fresh load + play of track 0.
        let playsBefore = engine.playCount
        player.previous()
        XCTAssertEqual(engine.playCount, playsBefore + 1)
        XCTAssertEqual(engine.lastLoadedURL, player.playlist[0].url)
    }

    // MARK: - Repeat ON re-enables the end of the queue

    /// With repeat `.all` or `.one`, explicit `▶▶` on the last track WRAPS, so it
    /// is never disabled at the end. Both repeat-on modes answer identically —
    /// the availability predicate and the wrap rule share one condition.
    func testLastTrackWithRepeatOnEnablesNextInBothRepeatModes() {
        for mode in [RepeatMode.all, RepeatMode.one] {
            let player = core(tracks: 3)
            player.repeatMode = mode
            player.select(2)
            XCTAssertTrue(player.canGoNext, "▶▶ wraps under \(mode), so it must stay lit")
            XCTAssertTrue(player.canGoPrevious)
        }
    }

    /// Toggling repeat OFF again at the end of the queue must take `▶▶` dark
    /// again — the predicate has to be live, not captured once.
    func testTurningRepeatOffAtTheEndOfTheQueueDisablesNextAgain() {
        let player = core(tracks: 3)
        player.repeatMode = .all
        player.select(2)
        XCTAssertTrue(player.canGoNext)

        player.repeatMode = .off

        XCTAssertFalse(player.canGoNext)
    }

    // MARK: - Single-track queues

    /// A 1-track queue with repeat OFF: the only track is also the last, so `▶▶`
    /// is disabled; `◀◀` still restarts it.
    func testSingleTrackWithRepeatOffDisablesNextButNotPrevious() {
        let player = core(tracks: 1)
        player.repeatMode = .off
        player.select(0)

        XCTAssertFalse(player.canGoNext)
        XCTAssertTrue(player.canGoPrevious)
    }

    /// A 1-track queue with repeat ON: both skips wrap onto the same track and
    /// RESTART it — observable, so both stay enabled.
    func testSingleTrackWithRepeatOnEnablesBothSkips() {
        let player = core(tracks: 1)
        player.repeatMode = .one
        player.select(0)

        XCTAssertTrue(player.canGoNext)
        XCTAssertTrue(player.canGoPrevious)
    }

    // MARK: - Shuffle

    /// Shuffle is "continuous": `next()` always picks another track regardless of
    /// `repeatMode`, so `▶▶` stays enabled even on the last row with repeat off.
    func testShuffleKeepsNextEnabledAtTheEndOfTheQueueWithRepeatOff() {
        let player = core(tracks: 3)
        player.repeatMode = .off
        player.isShuffle = true
        player.select(2)

        XCTAssertTrue(player.canGoNext, "shuffle has no end-of-list stop")
    }

    /// ...but a 1-track queue is the documented shuffle no-op (the strategy can
    /// only return the current index), so `▶▶` is disabled there too.
    func testShuffleOnASingleTrackQueueDisablesNext() {
        let player = core(tracks: 1)
        player.isShuffle = true
        player.select(0)

        XCTAssertFalse(player.canGoNext, "shuffle cannot leave a 1-track queue")
    }

    // MARK: - The predicates track playlist EDITS

    /// The predicates must follow live playlist mutation, not a snapshot: append a
    /// row after the last track and `▶▶` comes back; remove it and it goes dark.
    func testAppendingAndRemovingRowsFlipsNextAvailability() {
        let player = core(tracks: 2)
        player.repeatMode = .off
        player.select(1)
        XCTAssertFalse(player.canGoNext, "parked on the last of two rows")

        player.append([track("t2")])
        XCTAssertTrue(player.canGoNext, "a newly appended row is now reachable")

        player.remove(at: IndexSet(integer: 2))
        XCTAssertFalse(player.canGoNext, "removing it makes ▶▶ dead again")
    }

    /// A drag-reorder that moves the CURRENT track to the end must dim `▶▶`, and
    /// moving it back must re-light it — the exact sequence the playlist's
    /// drag-to-reorder produces.
    func testReorderingTheCurrentTrackFlipsNextAvailability() {
        let player = core(tracks: 3)
        player.repeatMode = .off
        player.select(0)
        XCTAssertTrue(player.canGoNext)

        player.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(player.currentIndex, 2, "the selection follows the moved track")
        XCTAssertFalse(player.canGoNext, "the current track is now last")

        player.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(player.currentIndex, 0)
        XCTAssertTrue(player.canGoNext)
    }

    // MARK: - Agreement with the transport itself (no drift)

    /// The anti-drift check: for EVERY combination of queue length, position,
    /// repeat mode and shuffle, `canGoNext` must agree with what `next()` actually
    /// does — "the selection moved, or a track was (re)loaded and played". This is
    /// the assertion that would fail if someone changed `next()` without changing
    /// the predicate.
    ///
    /// Shuffle is driven by a FORCED strategy so the outcome is deterministic
    /// (the default strategy is random); it picks the last index, or 0 when the
    /// current track already is the last.
    func testCanGoNextAgreesWithWhatNextActuallyDoes() {
        for count in 1...4 {
            for index in 0..<count {
                for mode in [RepeatMode.off, .all, .one] {
                    for shuffle in [false, true] {
                        let engine = FakePlaybackEngine()
                        let player = core(engine, tracks: count) { total, current in
                            current == total - 1 ? 0 : total - 1
                        }
                        player.repeatMode = mode
                        player.isShuffle = shuffle
                        player.select(index)
                        let indexBefore = player.currentIndex
                        let loadsBefore = engine.loadedURLs.count
                        let playsBefore = engine.playCount
                        let expected = player.canGoNext

                        player.next()

                        let moved = player.currentIndex != indexBefore
                        let restarted = engine.loadedURLs.count > loadsBefore
                            && engine.playCount > playsBefore
                        let label = "count=\(count) index=\(index) mode=\(mode) shuffle=\(shuffle)"
                        XCTAssertEqual(moved || restarted, expected, "canGoNext disagreed with next(): \(label)")
                    }
                }
            }
        }
    }

    /// The same anti-drift check for `previous()`. `previous` never shuffles, so
    /// the sweep covers queue length, position and repeat mode.
    func testCanGoPreviousAgreesWithWhatPreviousActuallyDoes() {
        for count in 1...4 {
            for index in 0..<count {
                for mode in [RepeatMode.off, .all, .one] {
                    let engine = FakePlaybackEngine()
                    let player = core(engine, tracks: count)
                    player.repeatMode = mode
                    player.select(index)
                    let indexBefore = player.currentIndex
                    let loadsBefore = engine.loadedURLs.count
                    let playsBefore = engine.playCount
                    let expected = player.canGoPrevious

                    player.previous()

                    let moved = player.currentIndex != indexBefore
                    let restarted = engine.loadedURLs.count > loadsBefore
                        && engine.playCount > playsBefore
                    let label = "count=\(count) index=\(index) mode=\(mode)"
                    XCTAssertEqual(moved || restarted, expected, "canGoPrevious disagreed with previous(): \(label)")
                }
            }
        }
    }
}
