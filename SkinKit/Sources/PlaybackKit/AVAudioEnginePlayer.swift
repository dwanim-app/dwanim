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

    // MARK: - Completion gating

    /// Incremented on every schedule, stop, and seek. A completion handler
    /// only counts as a natural finish if its captured token still matches.
    private var generation: UInt64 = 0

    // MARK: - Public callbacks

    public var onPlaybackFinished: (() -> Void)?

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
        guard sampleRate > 0,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else {
            return PlaybackMath.clamp(base, to: duration)
        }
        let elapsed = PlaybackMath.time(
            forFrame: playerTime.sampleTime,
            sampleRate: sampleRate
        )
        return PlaybackMath.clamp(base + elapsed, to: duration)
    }

    public var duration: TimeInterval {
        PlaybackMath.duration(frames: totalFrames, sampleRate: sampleRate)
    }

    public var isPlaying: Bool {
        playerNode.isPlaying
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
            self.onPlaybackFinished?()
        }
    }

    // MARK: - Engine lifecycle

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        try? engine.start()
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
        playerNode.stop()
    }
}
