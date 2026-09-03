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
///
/// ## Concurrency: `@unchecked Sendable`, NOT `@MainActor` (do not regress)
/// The engine is deliberately NOT actor-isolated. It owns an `AVAudioEngine`
/// whose render graph runs on the audio thread, and its two off-main closures —
/// the `scheduleSegment` completion callback and the PCM tap — fire on that audio
/// render thread. Marking the class `@MainActor` would (wrongly) make those
/// closures main-isolated, which is unsound for callbacks the audio thread
/// invokes, and could push UI-actor work onto the render thread. So the class
/// stays nonisolated.
///
/// Its Swift-level mutable state (`file`, `generation`, `seekBaseTime`,
/// `wantsToPlay`, `reachedEnd`, `hasPendingSegment`, `onPlaybackFinished`, …) is
/// nonetheless MAIN-CONFINED: every transport method (`load`/`play`/`pause`/
/// `stop`/`seek`) is called by the `@MainActor` `PlayerCore`, and the finish
/// handler mutates that state ONLY inside the `DispatchQueue.main.async` hop in
/// `handleCompletion`. The audio-thread closures themselves touch NO Swift state:
/// the completion callback only bounces to main (carrying a `Sendable` token), and
/// the tap writes solely the lock-guarded, `Sendable` `SpectrumFeed`. Because that
/// discipline is hand-audited rather than compiler-enforced, the conformance is
/// `@unchecked Sendable` (the audit, not a lock, is what makes it safe) — this lets
/// the engine cross the audio→main boundary as the closures' captured reference
/// without a data race, while keeping the audio boundary exactly where it is.
public final class AVAudioEnginePlayer: AudioPlaybackEngine, @unchecked Sendable {

    // MARK: - Graph

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// The 10-band graphic equalizer, inserted between `playerNode` and the
    /// main mixer (`playerNode -> eq -> mainMixerNode`). Its bands are pinned to
    /// the classic centre frequencies in `init` and never re-created, so the
    /// node identity is stable across track-change reconnects. See `EQConfig`.
    private let eq = AVAudioUnitEQ(numberOfBands: EQConfig.centreFrequencies.count)

    // MARK: - Loaded file state

    private var file: AVAudioFile?
    private var processingFormat: AVAudioFormat?
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    /// The loaded file's channel count (1 = mono, 2 = stereo, …), captured
    /// synchronously from the processing format on `load`. `0` before any load.
    /// Surfaced via `TrackFormatProviding` for the mono/stereo indicator.
    private var loadedChannelCount: Int = 0
    /// The loaded file's bitrate in kbps. Deferred: always `0` for now.
    /// Surfaced via `TrackFormatProviding` for the kbps number box. The accurate
    /// compressed-audio bitrate needs the async `AVAsset.load(.estimatedDataRate)`
    /// API, which arrives with the strict-concurrency work at M5; until then this
    /// stays `0` so the kbps box reads blank.
    private var loadedBitrateKbps: Int = 0

    // MARK: - Position state

    /// Time (seconds) the most recent schedule started from. `currentTime`
    /// adds the node's elapsed render time to this base.
    private var seekBaseTime: TimeInterval = 0
    /// The live position captured at the moment of `pause()`, or `nil` when not
    /// paused. `AVAudioPlayerNode.playerTime(forNodeTime:)` returns `nil` while the
    /// node is paused, so without this cache `currentTime` would fall back to the
    /// seek base (0 for a track played from the start) and the display would blip to
    /// 00:00. While paused we report this frozen position instead; it is cleared the
    /// moment a new position is armed (play/seek/stop/load).
    private var pausedTime: TimeInterval?
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

    /// The natural-finish handler, `@MainActor`-isolated and `@Sendable` to match
    /// the protocol. `PlayerCore` (the installer) is `@MainActor`; the engine fires
    /// this only after hopping to the main actor (see `handleCompletion`).
    public var onPlaybackFinished: (@Sendable @MainActor () -> Void)?

    // MARK: - Init

    public init() {
        engine.attach(playerNode)
        engine.attach(eq)
        // Pin the 10 bands to the classic centre frequencies once. They are
        // configured (filter type, bandwidth, bypass) here and only their gains
        // change later via `applyEqualizer`, so the band layout is stable.
        EQConfig.configure(eq)
        // playerNode -> eq -> mainMixerNode. `format: nil` lets each connection
        // adopt the upstream format; `rewireIfFormatChanged(to:)` re-wires the
        // whole chain with the loaded file's format whenever a `load` brings a
        // different sample rate or channel count.
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
    }

    // MARK: - Loading

    public func load(_ url: URL) throws {
        let loaded = try AVAudioFile(forReading: url)
        let format = loaded.processingFormat

        file = loaded
        processingFormat = format
        totalFrames = loaded.length
        sampleRate = format.sampleRate
        // Channel count is exposed by the processing format synchronously, so
        // (unlike kbps) it is accurate immediately — the mono/stereo indicator
        // reads it right after load.
        loadedChannelCount = Int(format.channelCount)
        // Bitrate stays 0 (deferred to M5): the accurate value needs the async
        // `AVAsset.load(.estimatedDataRate)` API. `sampleRate` above is accurate
        // and synchronous, so kHz is reported now and kbps reads blank.

        resetPositionState()
        rewireIfFormatChanged(to: format)
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
        // Resuming (or starting) hands the clock back to the render timeline, so
        // drop the paused-position freeze.
        pausedTime = nil

        // Schedule from the current seek base if nothing is pending; if a
        // segment is already scheduled (e.g. after pause) just resume the node.
        if !playerNode.isPlaying {
            scheduleSegmentIfNeeded()
        }

        // A PAUSED seek to/past the last frame parks with the seek base at the
        // duration and NOTHING scheduled (`scheduleSegment`'s `remaining > 0`
        // guard), so playing the node here would run an EMPTY queue: `isPlaying`
        // would read true, the position would pin at the duration, and no
        // completion would EVER fire — a permanent silent "playing" state with
        // no auto-advance/repeat and no recovery short of another manual
        // transport press. Treat this play() as an immediate NATURAL FINISH
        // instead, through the same async, generation-gated end path the
        // while-playing seek-to-end uses, so repeat/advance semantics apply.
        let baseFrame = PlaybackMath.frame(forTime: seekBaseTime, sampleRate: sampleRate)
        if file != nil, baseFrame >= totalFrames, !hasPendingSegment {
            reachedEnd = true
            wantsToPlay = false
            let token = generation
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    self.onPlaybackFinished?()
                }
            }
            return
        }

        playerNode.play()
    }

    public func pause() {
        // Capture the live position BEFORE pausing: once the node is paused,
        // `playerTime(forNodeTime:)` returns nil and `currentTime` can no longer
        // read the render clock, so freeze the display at where we are now.
        pausedTime = currentTime
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
        pausedTime = nil
    }

    public func seek(to time: TimeInterval) {
        guard file != nil else { return }
        // Ignore a non-finite seek target rather than jumping to the start; the
        // pure math also sanitizes it, but a garbage seek should be a no-op.
        guard time.isFinite else { return }
        let clamped = PlaybackMath.clamp(time, to: duration)
        let wasPlaying = wantsToPlay

        // Stopping the node fires the old completion handler; bumping the
        // generation first means that handler is ignored.
        generation &+= 1
        hasPendingSegment = false
        reachedEnd = false
        playerNode.stop()

        seekBaseTime = clamped
        // A seek arms a new position: drop any paused-position freeze so the
        // display reflects the seek target (a seek while paused reads the target
        // via the seek base in the fallback below).
        pausedTime = nil

        // Seeking AT/PAST the last frame leaves nothing to schedule: no segment
        // means no completion callback would EVER fire, so playback used to die
        // silently at the end — display frozen at the duration, no auto-advance,
        // no repeat (live-reproduced: seek posbar to ~100%, 20+s of dead air).
        // Treat it as an immediate NATURAL FINISH instead, through the same
        // async, generation-gated end path a real drain uses, so repeat/advance
        // semantics apply. (A PAUSED seek-to-end just parks at the end — the
        // finish fires only when the seek happened while playing; a subsequent
        // play() over the parked-at-end state synthesizes the finish itself,
        // see the matching branch in `play()`.)
        let startFrame = PlaybackMath.frame(forTime: clamped, sampleRate: sampleRate)
        if wasPlaying, startFrame >= totalFrames {
            reachedEnd = true
            wantsToPlay = false
            let token = generation
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    self.onPlaybackFinished?()
                }
            }
            return
        }

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
            // Paused: the render clock is unreadable, so report the position frozen
            // at `pause()` (not the seek base, which would blip to 00:00).
            if let pausedTime {
                return PlaybackMath.clamp(pausedTime, to: duration)
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

    /// TEST-ONLY visibility (internal, reached via `@testable import`): whether
    /// the underlying `AVAudioEngine` is running. The format-change tests must
    /// assert that a SAME-format `load` never stops the engine (no gap between
    /// same-format tracks) while a format-CHANGE `load` may — `isPlaying` alone
    /// cannot distinguish those because `load` always stops the player node.
    /// Exposing this one read keeps the `engine` itself private instead of
    /// widening the public API or weakening production encapsulation.
    var isEngineRunningForTesting: Bool { engine.isRunning }

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

    // MARK: - Pan / balance

    /// Stereo balance via the player node's built-in `pan` (-1 left … +1 right).
    /// Clamped on the way in (a non-finite value from `PlayerCore.setBalance` is
    /// already filtered out there, but the clamp keeps a stray value in range).
    ///
    /// Applied on `playerNode` (the source) rather than the mixer so it is
    /// independent of the EQ/tap chain and survives a format-change re-wire
    /// (`rewireIfFormatChanged(to:)`) — the
    /// node identity is stable across track-change re-wires, so the pan persists
    /// (and `PlayerCore.playCurrent` re-applies it on each load as a belt-and-
    /// suspenders against any node reset).
    public var pan: Float {
        get { playerNode.pan }
        set { playerNode.pan = min(max(newValue, -1), 1) }
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
            // AUDIO THREAD: do the MINIMUM. Capture only the Sendable `token` and a
            // weak engine reference, read/write NO engine state here, and hand off
            // immediately to the main-thread hop in `handleCompletion`.
            self?.handleCompletion(token: token)
        }
    }

    // MARK: - Completion

    /// Called from the audio thread when a scheduled segment drains. Only a segment
    /// whose token still matches the live generation (one that was neither stopped
    /// nor reseeked) counts as a natural finish.
    ///
    /// ## Audio-to-main hop (strict concurrency)
    /// This runs on the AUDIO render thread, so it does nothing but bounce to the
    /// main thread via `DispatchQueue.main.async`. EVERY engine-state read/write
    /// (`generation`, `hasPendingSegment`, `wantsToPlay`, `reachedEnd`) and the
    /// `onPlaybackFinished` call happen INSIDE the main-thread block, never on the
    /// audio thread, so the engine's Swift state stays main-confined. The audio
    /// thread only carries the `@unchecked Sendable` engine reference across to the
    /// main actor untouched (see the class-level Sendable note). `assumeIsolated` is
    /// sound because a `DispatchQueue.main.async` block always lands on the main
    /// thread; it makes the main-actor reads of `onPlaybackFinished` provable.
    private func handleCompletion(token: UInt64) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
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

    /// The format the `playerNode -> eq -> mainMixer` chain is currently wired
    /// with, or `nil` before the first load (the `init` connections use
    /// `format: nil` and are always replaced by the first real wire-up).
    /// Compared by sample rate + channel count — the two axes an `AVAudioFile`
    /// `processingFormat` can actually vary on (it is always deinterleaved
    /// float32) and exactly the mismatch that made the old always-rewire crash.
    private var wiredFormat: AVAudioFormat?

    /// Re-wires the whole chain (`playerNode -> eq -> mainMixer`) with the
    /// loaded file's format — but ONLY when the format actually changed.
    ///
    /// ## Why the running-engine guard (crash -10868, do not regress)
    /// Re-wiring while the engine is RUNNING made AVFoundation throw an
    /// uncatchable ObjC exception — kAudioUnitErr_FormatNotSupported (-10868)
    /// from `AVAudioEngineGraph::UpdateGraphAfterReconfig` — whenever the new
    /// track's format differed from the wired one (e.g. a 44.1 kHz stereo MP3
    /// dropped into a queue of 48 kHz mono files). In the app, AppKit swallowed
    /// the exception mid-event, leaving a half-disconnected graph: "playing"
    /// with a frozen 0:00 clock and silence. So on a format CHANGE the engine
    /// is stopped first (the player node is already stopped by
    /// `resetPositionState`), then both hops are re-made, matching the
    /// verified-safe sequence: stop node -> stop engine -> rewire -> restart.
    ///
    /// The RESTART is deliberately left to `startEngineIfNeeded()` in `play()`
    /// (and in `seek(to:)`'s resume path), not done here: the only production
    /// caller (`PlayerCore.playCurrent`) always calls `load` then `play`
    /// back-to-back, `pause -> load(other format) -> play` reaches the same
    /// `startEngineIfNeeded()`, and a plain `load` with no intent to play
    /// should not spin up the render hardware at all.
    ///
    /// A SAME-format load skips the re-wire entirely and never touches the
    /// running engine, so consecutive same-format tracks keep today's gapless
    /// behaviour. Skipping is safe because the chain is already wired for this
    /// exact format, the node identities are stable, and the EQ state /
    /// volume / pan are re-pushed by `PlayerCore` on every load anyway.
    ///
    /// Disconnecting only the player output and reconnecting straight to the
    /// mixer would silently drop the EQ node from the graph, so both hops are
    /// re-made through `eq` (GRAPH-ORDER PIN: playerNode -> eq -> mainMixer,
    /// tap on the mixer input = post-EQ; see `AudioEqualizing`).
    private func rewireIfFormatChanged(to format: AVAudioFormat) {
        if let wired = wiredFormat,
           wired.sampleRate == format.sampleRate,
           wired.channelCount == format.channelCount {
            return
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eq)
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        wiredFormat = format
    }

    private func resetPositionState() {
        generation &+= 1
        seekBaseTime = 0
        wantsToPlay = false
        hasPendingSegment = false
        reachedEnd = false
        pausedTime = nil
        playerNode.stop()
    }
}

// MARK: - AudioEqualizing

/// Real 10-band graphic-equalizer DSP, kept separate from the transport surface
/// (opt-in, exactly like the PCM tap and the format facts).
///
/// The `AVAudioUnitEQ` sits in the graph between `playerNode` and the main mixer
/// (`playerNode -> eq -> mainMixerNode`), with its 10 bands pinned to the classic
/// centre frequencies as parametric (peaking) filters in `init`. `PlayerCore`
/// owns the authoritative `EQState` and pushes it here — on every EQ change and
/// re-pushed on each track load — by opt-in casting the engine to
/// `AudioEqualizing`. The mapping (gains, preamp -> `globalGain`, enabled ->
/// bypass) lives in `EQConfig.apply`, the same routine the offline DSP-proof test
/// exercises, so the test runs the real production band setup.
///
/// GRAPH-ORDER PIN (do not regress): the EQ sits BEFORE the mixer and the PCM tap
/// sits on the mixer INPUT, so the tap captures POST-EQ but PRE-(mixer-output)
/// volume audio. That ordering is INTENTIONAL: the spectrum/graph visualizer
/// reacts to EQ changes yet is independent of the volume fader (`outputVolume` is
/// applied after the tap point). A future reader must not move the EQ after the
/// tap or move the tap past `outputVolume`. See `AudioTapProviding`.
extension AVAudioEnginePlayer: AudioEqualizing {

    public func applyEqualizer(_ state: EQState) {
        EQConfig.apply(state, to: eq)
    }
}

// MARK: - TrackFormatProviding

/// The loaded track's format facts (kHz / kbps), kept separate from transport.
///
/// `sampleRateHz` is the loaded file's processing-format sample rate, captured
/// synchronously on `load` — accurate and `0` before any load. `bitrateKbps` is
/// DEFERRED: it always returns `0` for now (the kbps box reads blank). The
/// accurate compressed-audio bitrate needs the async
/// `AVAsset.load(.estimatedDataRate)` API, which lands with the strict-concurrency
/// work at M5. This surface is opt-in and never flows through `PlayerCore`'s
/// transport — a consumer casts the engine to this protocol, exactly like the
/// PCM tap.
extension AVAudioEnginePlayer: TrackFormatProviding {

    public var sampleRateHz: Double {
        // `sampleRate` is 0 before any load and otherwise the processing format's
        // rate captured in `load`.
        sampleRate
    }

    public var bitrateKbps: Int {
        // Deferred to M5 (async asset loading): always 0 for now. See
        // `loadedBitrateKbps`.
        loadedBitrateKbps
    }

    public var channelCount: Int {
        // Captured synchronously in `load` from the processing format; 0 before
        // any load.
        loadedChannelCount
    }
}

// MARK: - AudioTapProviding

/// Live PCM tap, kept separate from the transport surface.
///
/// The tap sits on `engine.mainMixerNode` bus 0 — the mixer INPUT, after the EQ
/// node but before `outputVolume` — so it captures whatever is being rendered
/// regardless of the source file's channel layout. Each delivered buffer is
/// downmixed to a single mono `[Float]` frame (the per-channel average) before the
/// stored callback is invoked. This is the payoff of building transport on
/// `AVAudioEngine` (ADR §3.3): the analyzer can observe audio without `PlayerCore`
/// ever touching PCM.
///
/// POST-EQ, PRE-VOLUME (do not regress): because the EQ is upstream and the volume
/// fader is `outputVolume` (applied after this tap point), the captured PCM is
/// POST-EQ but PRE-(mixer-output)volume. This is the INTENTIONAL visualizer
/// contract — the graph reacts to EQ yet ignores the volume control. See
/// `AudioTapProviding` and the `AudioEqualizing` graph-order pin above.
extension AVAudioEnginePlayer: AudioTapProviding {

    public func installTap(
        _ onBuffer: @escaping @Sendable (_ monoSamples: [Float], _ sampleRate: Double) -> Void
    ) {
        // AVAudioEngine permits only one tap per bus, so remove-then-install to
        // be safe if a tap was already present (calling `installTap` twice must
        // not crash).
        engine.mainMixerNode.removeTap(onBus: 0)

        // Capture the callback DIRECTLY in the tap block (a local `let` the block
        // closes over) instead of reading a shared mutable property on the audio
        // render thread. The block keeps the closure alive for the life of the
        // tap; `removeTap(onBus:)` tears the block down, releasing it. The audio
        // thread therefore never reads shared mutable state.
        let callback = onBuffer

        // `format: nil` adopts the bus's own (output) format. Installing before
        // or after `engine.start()` is fine — the block simply will not fire
        // until audio flows through the mixer.
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil
        ) { buffer, _ in
            // Fires on an audio render thread. Downmix to mono and hand off; the
            // consumer is responsible for thread-hopping before touching UI. No
            // shared mutable state is read here — `callback` is captured by value.
            guard let mono = AVAudioEnginePlayer.monoSamples(from: buffer) else { return }
            callback(mono, buffer.format.sampleRate)
        }
    }

    public func removeTap() {
        // `removeTap(onBus:)` synchronously tears down the in-flight block,
        // releasing its captured callback; it is idempotent, so calling it with
        // no tap present is harmless.
        engine.mainMixerNode.removeTap(onBus: 0)
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
