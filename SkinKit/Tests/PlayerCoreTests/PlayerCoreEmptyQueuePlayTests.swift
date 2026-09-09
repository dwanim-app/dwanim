import Foundation
import XCTest
@testable import PlayerCore

// MARK: - PlayerCoreEmptyQueuePlayTests
//
// F2 — Play on an EMPTY queue must not be a silent no-op. App Review pressed the
// Play button on a fresh install (nothing loaded) and reported the core feature
// "unresponsive". The model now publishes that press through a seam,
// `onPlayWithEmptyQueue`, so the App tier can open the add-files panel; with
// tracks loaded the seam is never consulted and `play()` behaves exactly as before.
@MainActor
final class PlayerCoreEmptyQueuePlayTests: XCTestCase {

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"), title: name)
    }

    func testPlayOnAnEmptyQueueInvokesTheSeamAndTouchesNoEngine() {
        let engine = FakePlaybackEngine()
        let core = PlayerCore(engine: engine)
        var calls = 0
        core.onPlayWithEmptyQueue = { calls += 1 }

        core.play()

        XCTAssertEqual(calls, 1, "an empty-queue play asks the app for content")
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs, [], "nothing is loaded")
        XCTAssertEqual(engine.playCount, 0, "the engine is never started")
    }

    func testTogglePlayPauseOnAnEmptyQueueRoutesThroughTheSameSeam() {
        let core = PlayerCore(engine: FakePlaybackEngine())
        var calls = 0
        core.onPlayWithEmptyQueue = { calls += 1 }

        core.togglePlayPause()

        XCTAssertEqual(calls, 1, "the transport's play/pause button reaches the seam too")
        XCTAssertFalse(core.isPlaying)
    }

    func testPlayWithTracksLoadedNeverConsultsTheSeam() {
        let engine = FakePlaybackEngine()
        let core = PlayerCore(engine: engine)
        var calls = 0
        core.onPlayWithEmptyQueue = { calls += 1 }
        core.load([track("a"), track("b")])

        core.play()
        core.pause()
        core.togglePlayPause()

        XCTAssertEqual(calls, 0, "a loaded queue plays; the seam is for an EMPTY queue only")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["a.mp3"])
    }

    func testAnUnwiredSeamKeepsTheOldGuardedNoOp() {
        let engine = FakePlaybackEngine()
        let core = PlayerCore(engine: engine)

        core.play()

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs, [])
        XCTAssertEqual(engine.playCount, 0)
    }

    func testTheSeamFiresOncePerPressNotOncePerObservation() {
        let core = PlayerCore(engine: FakePlaybackEngine())
        var calls = 0
        core.onPlayWithEmptyQueue = { calls += 1 }

        core.play()
        core.play()
        core.togglePlayPause()

        XCTAssertEqual(calls, 3, "one press, one call — no batching, no suppression")
    }
}
