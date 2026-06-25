import Foundation
@testable import PlayerCore

// MARK: - EqualizingFakeEngine

/// A `FakePlaybackEngine`-style double that ALSO conforms to `AudioEqualizing`,
/// recording every `EQState` pushed to it so the "PlayerCore mirrors EQ to the
/// engine" wiring can be asserted in memory — the same opt-in cast a real
/// `AVAudioUnitEQ`-backed engine receives.
final class EqualizingFakeEngine: AudioPlaybackEngine, AudioEqualizing {

    // MARK: - Recorded EQ

    /// Every `EQState` passed to `applyEqualizer`, in order.
    private(set) var appliedStates: [EQState] = []
    /// The most recently applied state, for convenience in assertions.
    var lastApplied: EQState? { appliedStates.last }
    /// How many times `applyEqualizer` was called.
    var applyCount: Int { appliedStates.count }

    func applyEqualizer(_ state: EQState) {
        appliedStates.append(state)
    }

    // MARK: - AudioPlaybackEngine

    private(set) var loadedURLs: [URL] = []
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1.0
    var onPlaybackFinished: (() -> Void)?

    func load(_ url: URL) throws { loadedURLs.append(url) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func seek(to time: TimeInterval) { currentTime = time }
}
