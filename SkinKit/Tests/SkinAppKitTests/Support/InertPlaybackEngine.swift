import Foundation
import PlayerCore

// MARK: - InertPlaybackEngine
//
// A do-nothing `AudioPlaybackEngine` so a real `PlayerCore` can be constructed for
// the shaped-window window-build tests without touching any audio framework. These
// tests never load or play a track — the window is built with `tap: nil` and
// `format: nil`, so no PCM tap is installed and the engine's transport is never
// exercised. This exists only to satisfy `PlayerCore(engine:)`.
final class InertPlaybackEngine: AudioPlaybackEngine {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1.0
    var pan: Float = 0.0
    var onPlaybackFinished: (@Sendable @MainActor () -> Void)?

    func load(_ url: URL) throws {}
    func play() {}
    func pause() {}
    func stop() {}
    func seek(to time: TimeInterval) {}
}
