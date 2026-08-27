import Foundation
import XCTest
@testable import PlayerCore

// MARK: - PlayerCoreDurationTests

/// Tests for `PlayerCore.setDuration(_:forURL:)` — the URL-keyed metadata
/// write-back the app uses to fill the playlist Time column in after an async
/// duration read. The rules under test: it writes onto the matching row(s),
/// updates EVERY copy of a duplicated file, is a guarded no-op for an unknown URL
/// or a non-finite / non-positive value, and stays URL-keyed so a reorder between
/// the load starting and finishing still lands on the right track.
@MainActor
final class PlayerCoreDurationTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/music/\(name).mp3")
    }

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"), title: name)
    }

    private func makeCore(_ names: [String]) -> PlayerCore {
        let core = PlayerCore(engine: FakePlaybackEngine())
        core.load(names.map(track))
        return core
    }

    func testWritesDurationOntoMatchingTrack() {
        let core = makeCore(["a", "b", "c"])

        core.setDuration(187, forURL: url("b"))

        XCTAssertNil(core.playlist[0].duration)
        XCTAssertEqual(core.playlist[1].duration, 187)
        XCTAssertNil(core.playlist[2].duration)
    }

    func testUpdatesEveryCopyOfADuplicatedFile() {
        // The same file queued twice: both rows must fill in from one write.
        let core = makeCore(["a", "dup", "b", "dup"])

        core.setDuration(240, forURL: url("dup"))

        XCTAssertEqual(core.playlist[1].duration, 240)
        XCTAssertEqual(core.playlist[3].duration, 240)
        XCTAssertNil(core.playlist[0].duration)
        XCTAssertNil(core.playlist[2].duration)
    }

    func testUnknownURLIsNoOp() {
        let core = makeCore(["a", "b"])

        core.setDuration(120, forURL: url("not-in-queue"))

        XCTAssertNil(core.playlist[0].duration)
        XCTAssertNil(core.playlist[1].duration)
    }

    func testNonPositiveDurationIsGuardedNoOp() {
        let core = makeCore(["a"])

        core.setDuration(0, forURL: url("a"))
        XCTAssertNil(core.playlist[0].duration)

        core.setDuration(-5, forURL: url("a"))
        XCTAssertNil(core.playlist[0].duration)
    }

    func testNonFiniteDurationIsGuardedNoOp() {
        let core = makeCore(["a"])

        core.setDuration(.infinity, forURL: url("a"))
        XCTAssertNil(core.playlist[0].duration)

        core.setDuration(.nan, forURL: url("a"))
        XCTAssertNil(core.playlist[0].duration)
    }

    func testURLKeyedWriteSurvivesAReorder() {
        // A duration resolving AFTER the queue was reversed must still land on the
        // same file, wherever it moved to.
        let core = makeCore(["a", "b", "c"])
        core.reverse() // now ["c", "b", "a"]

        core.setDuration(99, forURL: url("a"))

        XCTAssertEqual(core.playlist[2].duration, 99) // "a" is last now
        XCTAssertNil(core.playlist[0].duration)
        XCTAssertNil(core.playlist[1].duration)
    }
}
