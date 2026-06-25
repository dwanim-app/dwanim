import Foundation

// MARK: - AudioPlaybackEngine

/// The platform audio engine, injected into `PlayerCore`.
///
/// The protocol is deliberately platform-neutral — its signatures use only
/// `URL`, `TimeInterval`, and `Float` — so the playback core can depend on the
/// abstraction while the concrete, framework-backed implementation lives in a
/// separate module (and a fake can stand in for unit tests). `PlayerCore` owns
/// transport policy; the engine owns the actual decoding and output.
public protocol AudioPlaybackEngine: AnyObject {
    /// Prepare a file for playback. Throws if the file cannot be loaded, which
    /// the core treats as an unplayable track to skip past.
    func load(_ url: URL) throws
    /// Begin or resume output of the loaded file.
    func play()
    /// Pause output, preserving position.
    func pause()
    /// Stop output and release the current playback position.
    func stop()
    /// Seek the loaded file to an absolute time in seconds.
    func seek(to time: TimeInterval)

    /// Current playback position in seconds.
    var currentTime: TimeInterval { get }
    /// Length of the loaded file in seconds.
    var duration: TimeInterval { get }
    /// Whether output is currently running.
    var isPlaying: Bool { get }
    /// Output volume in the range `0...1`.
    var volume: Float { get set }

    /// Invoked by the engine when the current track plays to its natural end.
    ///
    /// - Note: The handler is `@MainActor`-isolated because `PlayerCore` (the sole
    ///   installer) is `@MainActor` and the finish path mutates main-actor state.
    ///   A real engine may detect the finish on a background/audio thread, so the
    ///   concrete implementation MUST hop to the main actor before invoking this —
    ///   the `@MainActor` type makes that hop a compiler-checked obligation rather
    ///   than a convention (and a `@Sendable` closure, so it can be stored/forwarded
    ///   across the audio→main boundary).
    var onPlaybackFinished: (@Sendable @MainActor () -> Void)? { get set }
}
