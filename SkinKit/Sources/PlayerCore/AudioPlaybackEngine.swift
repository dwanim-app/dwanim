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
    /// - Note: A real engine may fire this on a background/audio thread; the
    ///   concrete implementation is responsible for hopping to the main thread
    ///   before invoking it, since `PlayerCore` is main-actor-oriented state.
    var onPlaybackFinished: (() -> Void)? { get set }
}
