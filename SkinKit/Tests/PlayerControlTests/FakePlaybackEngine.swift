import Foundation
import PlayerCore

// MARK: - FakePlaybackEngine

/// A test double conforming to `AudioPlaybackEngine` that records every call and
/// exposes settable state, so the `PlayerControl` -> `PlayerCore` mapping can be
/// driven and asserted entirely in memory — no real audio framework involved.
///
/// Adapted from `PlayerCoreTests`'s fake. `AudioPlaybackEngine` is public, so
/// this needs only a plain `import PlayerCore` (no `@testable`).
final class FakePlaybackEngine: AudioPlaybackEngine {

    // MARK: - Recorded calls

    /// Every URL passed to `load(_:)`, in order (including ones that threw).
    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    /// Every time passed to `seek(to:)`, in order.
    private(set) var seekedTimes: [TimeInterval] = []

    /// The most recently loaded URL, for convenience in assertions.
    var lastLoadedURL: URL? { loadedURLs.last }

    // MARK: - Configurable behavior

    /// URLs whose `load(_:)` should throw, simulating an unplayable file.
    var unloadableURLs: Set<URL> = []

    // MARK: - AudioPlaybackEngine state

    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1.0
    var onPlaybackFinished: (() -> Void)?

    // MARK: - Errors

    enum FakeError: Error { case unloadable }

    // MARK: - AudioPlaybackEngine commands

    func load(_ url: URL) throws {
        loadedURLs.append(url)
        if unloadableURLs.contains(url) {
            throw FakeError.unloadable
        }
    }

    func play() {
        playCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCount += 1
        isPlaying = false
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        seekedTimes.append(time)
        currentTime = time
    }

    // MARK: - Test helpers

    /// Simulate the engine finishing the current track end-to-end.
    func fireFinished() {
        onPlaybackFinished?()
    }
}
