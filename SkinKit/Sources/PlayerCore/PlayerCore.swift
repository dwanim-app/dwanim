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

    /// Produces a permutation of `0..<count` (new position -> old index) for
    /// `randomize()`. Injected so the playlist shuffle-in-place can be made
    /// deterministic in tests, exactly like `ShuffleStrategy` for `next()`.
    public typealias PermutationStrategy = (_ count: Int) -> [Int]

    // MARK: - Dependencies

    @ObservationIgnored private let engine: AudioPlaybackEngine
    @ObservationIgnored private let shuffleStrategy: ShuffleStrategy
    @ObservationIgnored private let permutationStrategy: PermutationStrategy

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
    /// Stereo balance / pan, in `-1...1`: `-1` hard left, `0` centered (the
    /// default), `+1` hard right. Mutated only through `setBalance`, which clamps
    /// + finite-guards and writes through to `engine.pan`, exactly how `volume` /
    /// `setVolume` flows. Re-applied to the engine on every track load (see
    /// `playCurrent`) so the two cannot silently diverge across a track change.
    public private(set) var balance: Float = 0.0
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

    public init(
        engine: AudioPlaybackEngine,
        shuffleStrategy: @escaping ShuffleStrategy,
        permutationStrategy: @escaping PermutationStrategy = PlayerCore.defaultPermutationStrategy
    ) {
        self.engine = engine
        self.shuffleStrategy = shuffleStrategy
        self.permutationStrategy = permutationStrategy
        self.volume = engine.volume
        self.balance = engine.pan
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

    /// Uniform random permutation of `0..<count` (Fisher–Yates via `shuffled()`).
    /// The default `PermutationStrategy` behind `randomize()`. `nonisolated`
    /// (it touches no state) so it converts cleanly to the nonisolated
    /// `PermutationStrategy` function type as the init's default argument.
    nonisolated public static func defaultPermutationStrategy(count: Int) -> [Int] {
        Array(0..<count).shuffled()
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

    // MARK: - Playlist edits (append / remove / crop / clear)
    //
    // EDIT RULE (shared by every mutator below): `currentIndex` FOLLOWS THE
    // PLAYING TRACK — it is recomputed to that track's new position and never
    // silently retargeted to a different track. Only removing the current row
    // itself moves the selection (to the first surviving row after the removal
    // point) and stops playback, because the followed track is gone.

    /// Append `tracks` to the end of the playlist. An existing selection is
    /// untouched, playback keeps running, and appending nothing is a no-op.
    /// Appending to an EMPTY list (no selection) selects the first new row —
    /// SELECT ONLY, never auto-play: without a selection, `play()`/`next()`/
    /// `previous()` (which guard on `currentIndex`) would all be dead over a
    /// visibly non-empty list. The engine/`loadedIndex` are untouched — a
    /// later `play()` loads the track through the normal path.
    public func append(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        playlist.append(contentsOf: tracks)
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    /// Remove the rows at `indices` (out-of-range members are ignored).
    ///
    /// - The selection shifts DOWN by the number of removed rows before it, so
    ///   it keeps pointing at the same track.
    /// - If the CURRENT row itself is removed, playback stops and the selection
    ///   moves to the first surviving row after the removal point (clamped to
    ///   the new last row when everything after was removed too).
    /// - When the list empties, the selection clears (`nil`).
    public func remove(at indices: IndexSet) {
        let valid = indices.intersection(IndexSet(playlist.indices))
        guard !valid.isEmpty else { return }

        let removingCurrent = currentIndex.map { valid.contains($0) } ?? false
        let removedBefore = currentIndex.map { valid.count(in: 0..<$0) } ?? 0

        for index in valid.reversed() {
            playlist.remove(at: index)
        }

        guard !playlist.isEmpty else {
            stop()
            currentIndex = nil
            return
        }

        if removingCurrent {
            // The followed track is gone: stop, then land on the first
            // surviving row after the removal point (the old current position
            // minus the rows removed before it), clamped to the new last row.
            stop()
            let landing = (currentIndex ?? 0) - removedBefore
            currentIndex = min(max(landing, 0), playlist.count - 1)
        } else if currentIndex != nil {
            currentIndex = (currentIndex ?? 0) - removedBefore
            if let loaded = loadedIndex {
                // Normally loadedIndex == currentIndex (both follow the loaded
                // track); shift it the same way, and clear it defensively if
                // the loaded row itself was somehow removed.
                loadedIndex = valid.contains(loaded) ? nil : loaded - valid.count(in: 0..<loaded)
            }
        }
    }

    /// Keep ONLY the rows at `indices` ("crop") — i.e. remove the complement,
    /// with exactly `remove(at:)`'s selection/stop rules. Cropping to an empty
    /// or fully out-of-range set is a guarded NO-OP (never a silent clear —
    /// `removeAll()` is the explicit way to empty the list).
    public func crop(to indices: IndexSet) {
        let kept = indices.intersection(IndexSet(playlist.indices))
        guard !kept.isEmpty else { return }
        remove(at: IndexSet(playlist.indices).subtracting(kept))
    }

    /// Empty the playlist: stop playback, clear the list and the selection.
    public func removeAll() {
        guard !playlist.isEmpty else { return }
        stop()
        playlist = []
        currentIndex = nil
    }

    // MARK: - Playlist reorder (sort / reverse / randomize)

    /// Sort the playlist by display title (case-insensitive; a track with no
    /// title sorts by its filename, matching what the list draws). The selection
    /// follows the playing track to its new position; playback is untouched.
    public func sortByTitle() {
        applyReorder(sortedPermutation { $0.title ?? $0.url.lastPathComponent })
    }

    /// Sort the playlist by filename (case-insensitive `lastPathComponent`).
    /// The selection follows the playing track; playback is untouched.
    public func sortByFilename() {
        applyReorder(sortedPermutation { $0.url.lastPathComponent })
    }

    /// Reverse the playlist order. The selection follows the playing track;
    /// playback is untouched.
    public func reverse() {
        applyReorder(Array((0..<playlist.count).reversed()))
    }

    /// Shuffle the playlist IN PLACE via the injected `PermutationStrategy`
    /// (deterministic in tests). The selection follows the playing track;
    /// playback is untouched. A malformed strategy result (not a permutation of
    /// `0..<count`) is a guarded no-op, like `boundedShuffleIndex`.
    public func randomize() {
        applyReorder(permutationStrategy(playlist.count))
    }

    /// The permutation (new position -> old index) that sorts the playlist by
    /// `key`, case-insensitively. Ties keep their original relative order (the
    /// original index is the explicit tiebreak, so the sort is stable by
    /// construction — not reliant on the stdlib sort's stability).
    private func sortedPermutation(_ key: (Track) -> String) -> [Int] {
        (0..<playlist.count).sorted { a, b in
            let ka = key(playlist[a]).lowercased()
            let kb = key(playlist[b]).lowercased()
            return ka == kb ? a < b : ka < kb
        }
    }

    /// Reorder the playlist by `permutation` (new position -> old index) and
    /// recompute `currentIndex` / `loadedIndex` to the SAME tracks' new
    /// positions, leaving the engine untouched (the playing audio never skips).
    /// Anything but a true permutation of `0..<count` is a guarded no-op; 0- or
    /// 1-track playlists have nothing to reorder.
    private func applyReorder(_ permutation: [Int]) {
        guard playlist.count > 1,
              permutation.count == playlist.count,
              permutation.sorted() == Array(playlist.indices) else { return }

        playlist = permutation.map { playlist[$0] }
        if let current = currentIndex {
            currentIndex = permutation.firstIndex(of: current)
        }
        if let loaded = loadedIndex {
            loadedIndex = permutation.firstIndex(of: loaded)
        }
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

    /// Set the stereo balance / pan, clamped to `-1...1`, on both the observable
    /// state and the engine. A non-finite value (`NaN`/`±inf`) is ignored as a
    /// no-op, since clamping cannot sanitize it (`min(max(NaN, -1), 1)` is `NaN`)
    /// and a real engine receiving such a pan is undefined. Mirrors `setVolume`
    /// exactly, but centered at `0` over the `-1...1` range.
    public func setBalance(_ b: Float) {
        guard b.isFinite else { return }
        let clamped = min(max(b, -1), 1)
        balance = clamped
        engine.pan = clamped
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
                // Likewise re-apply the balance/pan: the concrete engine re-wires
                // its graph on load, so push the authoritative pan through again
                // to keep stereo placement stable across a track change.
                engine.pan = balance
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
