import Foundation

// MARK: - AudioTapProviding

/// Opt-in PCM tap, separate from transport.
///
/// This is deliberately a distinct protocol from `AudioPlaybackEngine`: not
/// every engine can (or should) expose live samples, and PCM must never flow
/// through `PlayerCore`'s transport state. A consumer that wants live audio —
/// e.g. a spectrum analyzer — opt-in casts the engine to this protocol and
/// installs a tap; the shell wires tap -> analyzer -> render.
///
/// The protocol is platform-neutral (only `[Float]`/`Double`) so it can live in
/// the Foundation-only core while the concrete, framework-backed implementation
/// stays in the playback module.
///
/// - Note: Samples are mono `Float`. The callback fires on an audio render
///   thread; the consumer is responsible for thread-hopping before touching UI
///   or main-actor state.
public protocol AudioTapProviding: AnyObject {
    /// Install a tap that delivers downmixed mono PCM as audio flows.
    ///
    /// Installing again replaces any prior tap. The callback receives the mono
    /// sample frame and the source sample rate, on an audio render thread.
    func installTap(_ onBuffer: @escaping (_ monoSamples: [Float], _ sampleRate: Double) -> Void)

    /// Remove a previously installed tap. Safe to call when none is installed.
    func removeTap()
}
