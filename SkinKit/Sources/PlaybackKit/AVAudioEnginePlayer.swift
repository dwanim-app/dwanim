import AVFoundation
import Foundation
import PlayerCore

// MARK: - AVAudioEnginePlayer

/// A concrete `AudioPlaybackEngine` backed by `AVAudioEngine`.
///
/// The graph is a single `AVAudioPlayerNode` attached to the engine and
/// connected through `engine.mainMixerNode` to the default output. Files are
/// opened with `AVAudioFile`, so every format the platform decoder understands
/// (MP3, AAC, ALAC, FLAC, WAV, AIFF, …) is supported without per-format code.
///
/// Position tracking combines two pieces: a `seekBaseTime` offset, captured
/// every time a segment is scheduled, plus the elapsed render time reported by
/// the player node since that schedule. The natural end-of-track callback is
/// guarded by a generation token so that the completion handlers which also
/// fire on `stop()`/`seek()` cannot be mistaken for a real finish.
public final class AVAudioEnginePlayer: AudioPlaybackEngine {

    // MARK: - Graph

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // MARK: - Loaded file state

    private var file: AVAudioFile?
    private var processingFormat: AVAudioFormat?
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0

    // MARK: - Position state

    /// Time (seconds) the most recent schedule started from. `currentTime`
    /// adds the node's elapsed render time to this base.
    private var seekBaseTime: TimeInterval = 0
    /// Whether the user intends playback to be running. Survives engine
    /// pauses and is used to decide whether a seek should resume.
    private var wantsToPlay = false
    /// Set when a segment drains naturally (end of track). While set, the
    /// render clock is gone (the node has been stopped by the finish path), so
    /// `currentTime` must report the end of the track rather than fall back to
    /// the seek base — otherwise the reported position blips backward toward 0
    /// on the finishing poll. Cleared whenever fresh playback is armed
    /// (`play`/`seek`/`load`). This does not alter the seek/pause/stop base
    /// arithmetic; it only governs the read-time fallback after a finish.
    private var reachedEnd = false

    // MARK: - Completion gating

    /// Incremented on every schedule, stop, and seek. A completion handler
    /// only counts as a natural finish if its captured token still matches.
    private var generation: UInt64 = 0

    // MARK: - Public callbacks

    public var onPlaybackFinished: (() -> Void)?

    // MARK: - Audio tap

    /// The installed PCM tap callback, if any. Set by `installTap`, cleared by
    /// `removeTap`. The tap block on `mainMixerNode` reads this; it fires on an
    /// audio render thread, so consumers must thread-hop before touching UI.
    fileprivate var tapBuffer: ((_ monoSamples: [Float], _ sampleRate: Double) -> Void)?

    // MARK: - Init

    public init() {
        engine.attach(playerNode)
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: nil
        )
    }

    // MARK: - Loading

    public func load(_ url: URL) throws {
        let loaded = try AVAudioFile(forReading: url)
        let format = loaded.processingFormat

        file = loaded
        processingFormat = format
        totalFrames = loaded.length
        sampleRate = format.sampleRate

        resetPositionState()
        reconnect(using: format)
    }

    // MARK: - Transport

    public func play() {
        guard file != nil else { return }
        startEngineIfNeeded()
        wantsToPlay = true
        // Fresh playback is being armed, so the previous track is no longer at
        // its end. Resume of a paused node is also handled here (the flag was
        // already false in that case).
        reachedEnd = false

        // Schedule from the current seek base if nothing is pending; if a
        // segment is already scheduled (e.g. after pause) just resume the node.
        if !playerNode.isPlaying {
            scheduleSegmentIfNeeded()
        }
        playerNode.play()
    }

    public func pause() {
        playerNode.pause()
        wantsToPlay = false
    }

    public func stop() {
        // A stop must not be reported as a natural finish.
        generation &+= 1
        wantsToPlay = false
        hasPendingSegment = false
        playerNode.stop()
        seekBaseTime = 0
    }

    public func seek(to time: TimeInterval) {
        guard file != nil else { return }
        let clamped = PlaybackMath.clamp(time, to: duration)
        let wasPlaying = wantsToPlay

        // Stopping the node fires the old completion handler; bumping the
        // generation first means that handler is ignored.
        generation &+= 1
        hasPendingSegment = false
        reachedEnd = false
        playerNode.stop()

        seekBaseTime = clamped
        scheduleSegment(fromTime: clamped)

        if wasPlaying {
            startEngineIfNeeded()
            playerNode.play()
            wantsToPlay = true
        }
    }

    // MARK: - Position

    public var currentTime: TimeInterval {
        let base = seekBaseTime
        // Only trust the render clock once it is actually valid. During the
        // transient right after `playerNode.play()` the engine is spinning up:
        // `lastRenderTime`/`playerTime` is non-nil but `sampleTime` is stale
        // (zero or negative), which would momentarily drag the reported time
        // back toward the seek base. Until the clock is valid, hold at the base.
        guard sampleRate > 0,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else {
            // After a natural finish the node is stopped, so there is no render
            // clock to read. Report the end of the track (not the seek base) so
            // the position never blips backward on the finishing poll.
            if reachedEnd {
                return PlaybackMath.clamp(duration, to: duration)
            }
            return PlaybackMath.clamp(base, to: duration)
        }
        // A stale/negative sample time must never subtract from the base.
        let elapsed = max(
            0,
            PlaybackMath.time(
                forFrame: playerTime.sampleTime,
                sampleRate: sampleRate
            )
        )
        return PlaybackMath.clamp(base + elapsed, to: duration)
    }

    public var duration: TimeInterval {
        PlaybackMath.duration(frames: totalFrames, sampleRate: sampleRate)
    }

    public var isPlaying: Bool {
        // The player node can report `isPlaying == true` even when the engine
        // never actually started rendering (e.g. a no-output-device/route
        // failure that `startEngineIfNeeded()` swallowed). Reflect real state by
        // also requiring the engine to be running, so a failed start cannot
        // masquerade as playing.
        engine.isRunning && playerNode.isPlaying
    }

    // MARK: - Volume

    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = min(max(newValue, 0), 1) }
    }

    // MARK: - Scheduling

    /// Whether a segment has been handed to the node and not yet consumed by
    /// a stop/seek. Lets `play()` after `pause()` resume rather than reschedule.
    private var hasPendingSegment = false

    private func scheduleSegmentIfNeeded() {
        guard !hasPendingSegment else { return }
        scheduleSegment(fromTime: seekBaseTime)
    }

    /// Schedules the loaded file from `time` to its end, capturing a generation
    /// token so the completion handler can distinguish a natural finish from a
    /// stop/seek-triggered callback.
    private func scheduleSegment(fromTime time: TimeInterval) {
        guard let file else { return }

        let startFrame = PlaybackMath.frame(
            forTime: time,
            sampleRate: sampleRate
        )
        let remaining = totalFrames - startFrame
        guard remaining > 0 else { return }

        generation &+= 1
        let token = generation
        hasPendingSegment = true

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            self?.handleCompletion(token: token)
        }
    }

    // MARK: - Completion

    /// Called from the audio thread when a scheduled segment drains. Only a
    /// segment whose token still matches the live generation — i.e. one that
    /// was neither stopped nor reseeked — counts as a natural finish.
    private func handleCompletion(token: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard token == self.generation else { return }
            self.hasPendingSegment = false
            self.wantsToPlay = false
            // The track drained on its own; mark it so `currentTime` reports the
            // end position while the render clock is gone (see `reachedEnd`).
            self.reachedEnd = true
            self.onPlaybackFinished?()
        }
    }

    // MARK: - Engine lifecycle

    /// The most recent error thrown by `engine.start()`, captured for future
    /// surfacing. Not yet exposed through the protocol — the full state/error
    /// callback is a separate backlog item.
    private var lastStartError: Error?

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            lastStartError = nil
        } catch {
            // Swallow here as before (no protocol surface yet), but record the
            // failure so `isPlaying` (engine.isRunning && …) reports honestly
            // and the cause is available for future diagnostics.
            lastStartError = error
        }
    }

    private func reconnect(using format: AVAudioFormat) {
        engine.disconnectNodeOutput(playerNode)
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: format
        )
    }

    private func resetPositionState() {
        generation &+= 1
        seekBaseTime = 0
        wantsToPlay = false
        hasPendingSegment = false
        reachedEnd = false
        playerNode.stop()
    }
}

// MARK: - AudioTapProviding

/// Live PCM tap, kept separate from the transport surface.
///
/// The tap sits on `engine.mainMixerNode` — the post-mix point — so it captures
/// whatever is actually being rendered regardless of the source file's channel
/// layout. Each delivered buffer is downmixed to a single mono `[Float]` frame
/// (the per-channel average) before the stored callback is invoked. This is the
/// payoff of building transport on `AVAudioEngine` (ADR §3.3): the analyzer can
/// observe audio without `PlayerCore` ever touching PCM.
extension AVAudioEnginePlayer: AudioTapProviding {

    public func installTap(
        _ onBuffer: @escaping (_ monoSamples: [Float], _ sampleRate: Double) -> Void
    ) {
        // AVAudioEngine permits only one tap per bus, so remove-then-install to
        // be safe if a tap was already present (calling `installTap` twice must
        // not crash). Storing the closure lets `removeTap` clear it later.
        engine.mainMixerNode.removeTap(onBus: 0)
        tapBuffer = onBuffer

        // `format: nil` adopts the bus's own (output) format. Installing before
        // or after `engine.start()` is fine — the block simply will not fire
        // until audio flows through the mixer.
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil
        ) { [weak self] buffer, _ in
            // Fires on an audio render thread. Downmix to mono and hand off; the
            // consumer is responsible for thread-hopping before touching UI.
            guard let self,
                  let callback = self.tapBuffer,
                  let mono = AVAudioEnginePlayer.monoSamples(from: buffer)
            else { return }
            callback(mono, buffer.format.sampleRate)
        }
    }

    public func removeTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        tapBuffer = nil
    }

    /// Averages every channel of `buffer` into a single mono `[Float]` frame.
    ///
    /// Returns `nil` for an empty or float-data-less buffer. A single-channel
    /// buffer is copied through unchanged; multi-channel buffers are averaged
    /// per frame.
    ///
    /// Module-internal (not public) so headless offline-render tests can drive
    /// the exact downmix the live tap uses; it is not part of the public API.
    static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }

        var mono = [Float](repeating: 0, count: frameLength)
        if channelCount == 1 {
            let samples = channels[0]
            for frame in 0..<frameLength {
                mono[frame] = samples[frame]
            }
        } else {
            let scale = 1 / Float(channelCount)
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channels[channel][frame]
                }
                mono[frame] = sum * scale
            }
        }
        return mono
    }
}
