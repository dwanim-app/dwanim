import Foundation
@testable import PlayerCore

// MARK: - FakePlaybackEngine

/// A test double conforming to `AudioPlaybackEngine` that records every call and
/// exposes settable state, so the transport logic in `PlayerCore` can be driven
/// and asserted entirely in memory — no real audio framework involved.
///
/// It records the ordered list of loaded URLs and counts of each transport
/// command. A URL listed in `unloadableURLs` makes `load(_:)` throw, exercising
/// the fault-tolerant "skip the unplayable track" path. The injected callback
/// `onPlaybackFinished` can be fired directly via `fireFinished()` to simulate a
/// track ending.
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
    var onPlaybackFinished: (@Sendable @MainActor () -> Void)?

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

    /// Simulate the engine finishing the current track end-to-end. `@MainActor`
    /// because the stored handler is now main-actor-isolated (it drives the
    /// `@MainActor` `PlayerCore`); the tests call this from main-actor methods.
    @MainActor
    func fireFinished() {
        onPlaybackFinished?()
    }
}
