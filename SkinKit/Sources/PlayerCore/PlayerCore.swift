import Foundation
import Observation

// MARK: - PlayerCore

/// The pure, UI-agnostic playback core: it owns the playlist, the current
/// selection, and transport policy (repeat / shuffle / skip), and drives an
/// injected `AudioPlaybackEngine`.
///
/// It is `Foundation`-only and holds no audio or UI framework types, so all of
/// its behavior is unit-testable with a fake engine. Randomness for shuffle is
/// injected as a strategy closure so tests can force a deterministic order.
///
/// ## Boundary choices (documented)
/// - `next` past the last track with `.off`: the engine is stopped and
///   `isPlaying` becomes `false`; the selection **clamps to the last track**
///   (it does not advance off the end or clear), so the listener can replay or
///   step back.
/// - `previous` before the first track with `.off`: the selection **stays at
///   the first track** and that track is (re)loaded and played, i.e. "restart".
/// - With `.all`, both `next` and `previous` wrap around the ends.
/// - `.one` only matters for `onPlaybackFinished` (replay the same track);
///   explicit `next`/`previous` always move to a different track so the listener
///   can still navigate.
///
/// ## Shuffle choice (documented)
/// When `isShuffle` is on, `next` consults `shuffleStrategy(count, current)` to
/// choose the next index. The default strategy picks a uniformly random index
/// **other than** the current one (and is a no-op for 0- or 1-track playlists).
/// `previous` does not shuffle; it steps linearly so "go back" is predictable.
@MainActor
@Observable
public final class PlayerCore {

    // MARK: - Types

    /// Chooses the next index given the playlist `count` and the `current`
    /// index. Injected so shuffle can be made deterministic in tests.
    public typealias ShuffleStrategy = (_ count: Int, _ current: Int?) -> Int

    // MARK: - Dependencies

    @ObservationIgnored private let engine: AudioPlaybackEngine
    @ObservationIgnored private let shuffleStrategy: ShuffleStrategy

    /// The playlist index currently loaded into the engine, or `nil` when the
    /// engine holds no track (never loaded, stopped, or playlist replaced).
    ///
    /// This lets `play()` distinguish "resume the already-loaded current track"
    /// (no reload, so the engine keeps its position) from "switch to a different
    /// track" (load + play). It is updated on every successful `engine.load(...)`
    /// and cleared by `stop()` and `load(_:)`; `pause()` leaves it intact so a
    /// subsequent `play()` resumes rather than restarting from 0.
    @ObservationIgnored private var loadedIndex: Int?

    // MARK: - Observable state

    public private(set) var playlist: [Track] = []
    public private(set) var currentIndex: Int?
    public private(set) var isPlaying: Bool = false
    public private(set) var volume: Float = 1.0
    public var repeatMode: RepeatMode = .off
    public var isShuffle: Bool = false

    /// The authoritative 10-band graphic-equalizer state. Defaults to flat and
    /// disabled (a perfect pass-through). Mutated only through `setEQEnabled`,
    /// `setEQPreamp`, and `setEQBand`, each of which also mirrors the new state
    /// to the engine (see `setEqualizer`), exactly how `setVolume` flows.
    ///
    /// Settable directly (e.g. to restore a saved preset) and the `didSet`
    /// mirror keeps the engine in sync; the named mutators are the clamping,
    /// bounds-checked path a UI control should prefer.
    public var equalizer: EQState = EQState() {
        didSet { pushEqualizerToEngine() }
    }

    // MARK: - Derived state

    /// Current playback position in seconds, delegated to the engine.
    public var currentTime: TimeInterval { engine.currentTime }
    /// Length of the current track in seconds, delegated to the engine.
    public var duration: TimeInterval { engine.duration }
    /// The selected track, or `nil` when nothing is selected.
    public var currentTrack: Track? {
        guard let index = currentIndex, playlist.indices.contains(index) else { return nil }
        return playlist[index]
    }

    // MARK: - Init

    public convenience init(engine: AudioPlaybackEngine) {
        self.init(engine: engine, shuffleStrategy: PlayerCore.defaultShuffleStrategy)
    }

    public init(engine: AudioPlaybackEngine, shuffleStrategy: @escaping ShuffleStrategy) {
        self.engine = engine
        self.shuffleStrategy = shuffleStrategy
        self.volume = engine.volume
        self.engine.onPlaybackFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }
    }

    // MARK: - Default shuffle

    /// Picks a uniformly random index other than `current`. For 0- or 1-track
    /// playlists it returns `current ?? 0` (the caller treats this as a no-op).
    public static func defaultShuffleStrategy(count: Int, current: Int?) -> Int {
        guard count > 1 else { return current ?? 0 }
        var pick = Int.random(in: 0..<count)
        while pick == current {
            pick = Int.random(in: 0..<count)
        }
        return pick
    }

    // MARK: - Playlist commands

    /// Replace the playlist. If playback is in progress, the engine is stopped
    /// first so the old track does not keep playing under the new playlist, and
    /// transport state is reset. Then selects index 0 if non-empty (else clears
    /// the selection). Does **not** auto-play.
    public func load(_ tracks: [Track]) {
        if isPlaying {
            engine.stop()
            isPlaying = false
        }
        loadedIndex = nil
        playlist = tracks
        currentIndex = tracks.isEmpty ? nil : 0
    }

    // MARK: - Transport

    /// Start (or resume) playback of the current track.
    ///
    /// If we are resuming a *paused* current track that is still the one loaded
    /// in the engine (`!isPlaying` and `loadedIndex == currentIndex`), this just
    /// calls `engine.play()` so the engine keeps its position — it does not
    /// reload from the start. Otherwise it loads the current track and plays it:
    /// if loading throws, the track is treated as unplayable and skipped; if
    /// nothing is playable the engine is stopped. Empty playlist is a no-op.
    ///
    /// - Note: Calling `play()` while *already* playing is **not** treated as a
    ///   resume — it reloads and restarts the current track (documented
    ///   behavior). Only a paused current track resumes without reload.
    public func play() {
        guard !playlist.isEmpty, let index = currentIndex,
              playlist.indices.contains(index) else { return }

        if !isPlaying, loadedIndex == index {
            // Resuming the already-loaded, paused current track: do not reload,
            // so the engine preserves its current position.
            engine.play()
            isPlaying = true
            return
        }

        playCurrent()
    }

    /// Pause playback, preserving position.
    public func pause() {
        guard isPlaying else { return }
        engine.pause()
        isPlaying = false
    }

    /// Toggle between play and pause.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Advance to the next track per `repeatMode` / `isShuffle`, then play it.
    public func next() {
        guard !playlist.isEmpty, let index = currentIndex else { return }

        if isShuffle {
            // Intentional for now: while shuffling, `next` always picks another
            // track and returns here, so the sequential `.off` end-of-list stop
            // below never applies. Shuffle is therefore "continuous" — it keeps
            // picking regardless of `repeatMode`; `.off`'s end-stop is a
            // sequential-mode behavior only.
            let pick = boundedShuffleIndex()
            guard pick != index else { return } // single-track / no-op strategy
            currentIndex = pick
            playCurrent()
            return
        }

        if index < playlist.count - 1 {
            currentIndex = index + 1
            playCurrent()
        } else {
            // At the last track.
            switch repeatMode {
            case .all:
                currentIndex = 0
                playCurrent()
            case .off, .one:
                stop()
            }
        }
    }

    /// Retreat to the previous track per `repeatMode`, then play it.
    public func previous() {
        guard !playlist.isEmpty, let index = currentIndex else { return }

        if index > 0 {
            currentIndex = index - 1
            playCurrent()
        } else {
            // At the first track.
            switch repeatMode {
            case .all:
                currentIndex = playlist.count - 1
                playCurrent()
            case .off, .one:
                // Restart the first track in place.
                playCurrent()
            }
        }
    }

    /// Seek the engine to an absolute time in seconds.
    ///
    /// - Note: This is intentionally a pass-through — the value is **not**
    ///   clamped here (negatives and times past the duration are forwarded as
    ///   given). The real engine is responsible for guarding the seek against
    ///   its own loaded file's bounds, so `PlayerCore` does not duplicate that
    ///   policy.
    public func seek(to time: TimeInterval) {
        engine.seek(to: time)
    }

    /// Set the volume, clamped to `0...1`, on both the observable state and the
    /// engine. A non-finite value (`NaN`/`±inf`) is ignored as a no-op, since
    /// clamping cannot sanitize it (`min(max(NaN, 0), 1)` is `NaN`) and a real
    /// engine receiving such a value is undefined.
    public func setVolume(_ v: Float) {
        guard v.isFinite else { return }
        let clamped = min(max(v, 0), 1)
        volume = clamped
        engine.volume = clamped
    }

    // MARK: - Equalizer

    /// Turn the equalizer on or off and mirror the change to the engine. When
    /// disabled the engine passes audio through unchanged regardless of the
    /// gains, so toggling does not lose the dialed-in band/preamp values.
    public func setEQEnabled(_ enabled: Bool) {
        equalizer.enabled = enabled
    }

    /// Set the preamp gain in dB (clamped to `EQState.gainRange`) and mirror the
    /// change to the engine. Non-finite values are ignored (no-op).
    public func setEQPreamp(_ dB: Double) {
        equalizer.setPreamp(dB)
    }

    /// Set band `index`'s gain in dB (clamped to `EQState.gainRange`) and mirror
    /// the change to the engine. An out-of-range index or a non-finite value is
    /// a guarded no-op.
    public func setEQBand(_ index: Int, dB: Double) {
        equalizer.setBand(index, dB: dB)
    }

    /// Replace the whole equalizer state at once (e.g. to apply a preset) and
    /// mirror it to the engine.
    public func setEqualizer(_ state: EQState) {
        equalizer = state
    }

    /// Mirror the current equalizer state to the engine, if the injected engine
    /// opts in to `AudioEqualizing`. This is the EQ analogue of how `setVolume`
    /// writes through to `engine.volume`: `PlayerCore` stays pure and never
    /// touches audio frameworks — it just hands the platform-neutral `EQState`
    /// to whatever sink the engine exposes. An engine that does not conform
    /// silently no-ops (EQ is opt-in, like the tap).
    private func pushEqualizerToEngine() {
        (engine as? AudioEqualizing)?.applyEqualizer(equalizer)
    }

    /// Select a playlist index (bounds-checked) and play it. Out-of-range is a
    /// guarded no-op.
    public func select(_ index: Int) {
        guard playlist.indices.contains(index) else { return }
        currentIndex = index
        playCurrent()
    }

    // MARK: - Engine callback

    /// Called when the engine finishes the current track.
    /// - `.one`: reload and replay the same track.
    /// - `.all`: advance with wrap.
    /// - `.off`: advance, or stop if already at the last track.
    private func handlePlaybackFinished() {
        guard !playlist.isEmpty, currentIndex != nil else { return }
        switch repeatMode {
        case .one:
            playCurrent()
        case .all, .off:
            next()
        }
    }

    // MARK: - Helpers

    /// Load the current track and start the engine, skipping unplayable tracks.
    /// If every remaining track is unplayable, stop.
    private func playCurrent() {
        guard !playlist.isEmpty, let index = currentIndex,
              playlist.indices.contains(index) else { return }

        var visited = Set<Int>()
        var cursor = index

        while true {
            guard !visited.contains(cursor) else {
                // Cycled through every reachable track; nothing playable.
                stop()
                return
            }
            visited.insert(cursor)

            do {
                try engine.load(playlist[cursor].url)
                // Re-apply the core's volume to the engine on every load so the
                // two cannot silently diverge across a track change (a real
                // engine may reset volume when it swaps the underlying file).
                engine.volume = volume
                // Likewise re-apply the equalizer: the concrete engine re-wires
                // its graph on load, so push the authoritative EQ state through
                // again to keep the DSP in sync across a track change.
                pushEqualizerToEngine()
                currentIndex = cursor
                loadedIndex = cursor
                engine.play()
                isPlaying = true
                return
            } catch {
                // Unplayable: skip forward to the next track.
                if let nextCursor = nextPlayableCursor(after: cursor) {
                    cursor = nextCursor
                } else {
                    stop()
                    return
                }
            }
        }
    }

    /// The index to try after an unplayable track, honoring `.all` wrap. With
    /// `.off`/`.one` it does not wrap past the end.
    private func nextPlayableCursor(after cursor: Int) -> Int? {
        if cursor < playlist.count - 1 {
            return cursor + 1
        }
        switch repeatMode {
        case .all:
            return 0
        case .off, .one:
            return nil
        }
    }

    /// Resolve the shuffle strategy's pick into a valid in-range index.
    private func boundedShuffleIndex() -> Int {
        let raw = shuffleStrategy(playlist.count, currentIndex)
        guard playlist.indices.contains(raw) else {
            return currentIndex ?? 0
        }
        return raw
    }

    /// Stop the engine and clear the playing flag. Also clears `loadedIndex`,
    /// since the engine no longer holds a track to resume.
    private func stop() {
        engine.stop()
        isPlaying = false
        loadedIndex = nil
    }
}
