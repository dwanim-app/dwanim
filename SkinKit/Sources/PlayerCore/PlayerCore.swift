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
/// The rule in one line: **explicit `next`/`previous` wrap whenever repeat is ON
/// (`.all` or `.one`); only `.off` has ends.**
/// - `next` past the last track with `.off`: the engine is stopped and
///   `isPlaying` becomes `false`; the selection **clamps to the last track**
///   (it does not advance off the end or clear), so the listener can replay or
///   step back.
/// - `previous` before the first track with `.off`: the selection **stays at
///   the first track** and that track is (re)loaded and played, i.e. "restart".
///   That `.off` asymmetry — stop at the end, restart at the front — is
///   DELIBERATE and matches Music / iTunes / Spotify. Do not "fix" it.
/// - With `.all` **and** `.one`, both `next` and `previous` wrap around the ends:
///   `next` on the last track lands on the first, `previous` on the first lands
///   on the last. Mid-list both simply step to the neighbouring track, so an
///   explicit skip under `.one` is never a replay in place.
/// - `.one` differs from `.all` in AUTO-ADVANCE only: when the engine reports the
///   track finished, `.one` replays the SAME track (see `handlePlaybackFinished`)
///   while `.all` advances with wrap and `.off` stops at the end. Wrapping is an
///   explicit-navigation rule; repeating is an end-of-track rule.
/// - `canGoNext` / `canGoPrevious` publish the SAME policy as a predicate, so a
///   view can dim a skip button that could not act instead of leaving it looking
///   live. They are derived from this transport logic, never re-derived in a view.
///
/// ## Unplayable files (documented)
/// A track is unplayable in TWO ways, and both are handled the same:
/// 1. **It will not open** — `engine.load(_:)` throws.
/// 2. **It opens but renders nothing** — the load succeeds and the engine then
///    reports a natural finish before it could possibly have played anything
///    (`finishLooksLikeSilence`). An Ogg-wrapped FLAC does exactly this on
///    macOS: it opens, claims 100 s for an 8-second clip, and drains in ~18 ms.
///    Without this case a "finish" that fast was taken at face value and
///    auto-advance ran FORWARD, so a `◀◀` onto such a file bounced the listener
///    back to the track they had just left, and under `.one` it parked them on
///    silence for ever.
///
/// Either way the skip walks the way the PRESS pointed: `▶▶` (and `play()`,
/// `select()`, auto-advance) forward, `◀◀` backward. Both use the same wrap
/// policy — `.all` wraps, `.off`/`.one` come to rest at the end they reached —
/// so the two directions differ only in which way they move. Recovering a `◀◀`
/// forwards would make every track before a dead file unreachable; that was a
/// real defect, not a theoretical one.
///
/// The limit worth stating: case 2 is judged by TIMING, not by inspecting the
/// audio. A file that renders a little and then stops early, or renders
/// silence for its full length, is indistinguishable from music the listener
/// chose and is left alone.
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

    /// Reads a monotonically increasing number of seconds. Injected — like the
    /// two strategies above — so the "that finish arrived too fast to be real"
    /// judgement (see `finishLooksLikeSilence`) can be tested deterministically
    /// instead of by sleeping. The core keeps no other notion of time.
    public typealias MonotonicClock = () -> TimeInterval

    // MARK: - Dependencies

    @ObservationIgnored private let engine: AudioPlaybackEngine
    @ObservationIgnored private let shuffleStrategy: ShuffleStrategy
    @ObservationIgnored private let permutationStrategy: PermutationStrategy
    @ObservationIgnored private let now: MonotonicClock

    /// The playlist index currently loaded into the engine, or `nil` when the
    /// engine holds no track (never loaded, stopped, or playlist replaced).
    ///
    /// This lets `play()` distinguish "resume the already-loaded current track"
    /// (no reload, so the engine keeps its position) from "switch to a different
    /// track" (load + play). It is updated on every successful `engine.load(...)`
    /// and cleared by `stop()` and `load(_:)`; `pause()` leaves it intact so a
    /// subsequent `play()` resumes rather than restarting from 0.
    @ObservationIgnored private var loadedIndex: Int?

    // MARK: Silent-finish detection state
    //
    // Three pieces of bookkeeping behind ONE judgement: did the track that just
    // reported "finished" actually render any audio? See `finishLooksLikeSilence`.

    /// The clock reading at which the current track started producing audio (or
    /// at which a `seek` re-based that), or `nil` when nothing is loaded.
    @ObservationIgnored private var playbackStartedAt: TimeInterval?

    /// How many seconds of audio the engine promised from `playbackStartedAt` —
    /// the loaded file's duration, less any seek offset.
    @ObservationIgnored private var promisedSeconds: TimeInterval = 0

    /// Which way the walk that reached the current track was heading, so a track
    /// discovered to be silent AFTER it loaded can carry on the same way the
    /// press pointed. Set on every `playCurrent`.
    @ObservationIgnored private var lastSkipDirection: SkipDirection = .forward

    /// Indices found to render nothing since the last explicit transport command.
    /// It bounds the silent-file walk exactly as `playCurrent`'s `visited` set
    /// bounds the failed-load walk — without it a queue of silent files under
    /// `.all` would sweep round for ever. Cleared by every command that
    /// represents fresh listener intent.
    @ObservationIgnored private var silentSinceLastCommand: Set<Int> = []

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

    // MARK: Skip availability
    //
    // These two answer ONE question for a view: *would pressing this skip button
    // produce an observable change?* They exist so a transport row can dim a
    // control that cannot act, instead of leaving it looking live — the reported
    // complaint. They restate the `next()` / `previous()` policy rather than
    // inventing a second one; `PlayerCoreTransportAvailabilityTests` sweeps every
    // (count, index, repeatMode, isShuffle) combination and fails if the two ever
    // disagree with what the transport actually does.

    /// Whether `next()` would do something the listener can perceive.
    ///
    /// - No selection (an empty queue) — `next()` is a guarded no-op: `false`.
    /// - Shuffling — `next()` always picks another track, with no end-of-list
    ///   stop, so it is available on any queue longer than one track.
    /// - Mid-list — always available.
    /// - On the LAST track — available only while repeat is ON, because that is
    ///   exactly when `next()` wraps. With `.off` the call would merely `stop()`
    ///   the engine; that is a real effect while playing, but the owner's choice
    ///   is that `▶▶` is not a stop button (■ is), so the end of the queue reads
    ///   as "nowhere further to go" and the control dims.
    public var canGoNext: Bool {
        guard !playlist.isEmpty, let index = currentIndex,
              playlist.indices.contains(index) else { return false }
        if isShuffle { return playlist.count > 1 }
        if index < playlist.count - 1 { return true }
        return repeatMode != .off
    }

    /// Whether `previous()` would do something the listener can perceive.
    ///
    /// It reads the SAME `previousTargetIndex(from:)` the transport does, so the
    /// predicate cannot drift from the move: true exactly when that target
    /// exists. Mid-list the target is the row above; on the FIRST track it is the
    /// last row (repeat on) or that same first row re-started from the top
    /// (repeat off) — and a restart IS observable, which is why `◀◀` does not dim
    /// at the front the way `▶▶` dims at the end. Only an empty queue (no
    /// selection) has no target and disables it.
    ///
    /// - Note: This is a POLICY predicate over indices, not a playability oracle.
    ///   Whether the target file actually decodes is discovered only when the
    ///   engine is asked to load it (and whether it then renders anything is
    ///   discovered later still), so neither skip predicate can promise sound —
    ///   that limit is identical in both directions. What the model DOES
    ///   guarantee is that the recovery walk runs the same way the press pointed
    ///   (see `previousPlayableCursor(before:)` and `skipPastSilentTrack(at:)`),
    ///   so a `◀◀` onto a file that will not open — or that opens and plays
    ///   nothing — steps further BACK rather than returning the listener to the
    ///   track they just left.
    public var canGoPrevious: Bool {
        guard !playlist.isEmpty, let index = currentIndex,
              playlist.indices.contains(index) else { return false }
        return previousTargetIndex(from: index) != nil
    }

    /// The index an explicit `previous()` selects when pressed at `index` — the
    /// single definition both `previous()` and `canGoPrevious` read.
    ///
    /// - Mid-list: the row above.
    /// - First row, repeat ON (`.all` or `.one`): the last row (wrap).
    /// - First row, repeat OFF: the first row again (restart in place — the
    ///   deliberate `.off` asymmetry documented at the top of this file).
    ///
    /// `nil` only for an out-of-range index, i.e. nothing selected.
    private func previousTargetIndex(from index: Int) -> Int? {
        guard playlist.indices.contains(index) else { return nil }
        if index > 0 { return index - 1 }
        switch repeatMode {
        case .all, .one: return playlist.count - 1
        case .off:       return 0
        }
    }

    // MARK: - Init

    public convenience init(engine: AudioPlaybackEngine) {
        self.init(engine: engine, shuffleStrategy: PlayerCore.defaultShuffleStrategy)
    }

    public init(
        engine: AudioPlaybackEngine,
        shuffleStrategy: @escaping ShuffleStrategy,
        permutationStrategy: @escaping PermutationStrategy = PlayerCore.defaultPermutationStrategy,
        now: @escaping MonotonicClock = PlayerCore.defaultClock
    ) {
        self.engine = engine
        self.shuffleStrategy = shuffleStrategy
        self.permutationStrategy = permutationStrategy
        self.now = now
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

    // MARK: - Default clock

    /// Seconds since boot — monotonic, so it cannot run backwards when the wall
    /// clock is adjusted. `nonisolated` for the same reason
    /// `defaultPermutationStrategy` is: it touches no state, so it converts
    /// cleanly to the nonisolated `MonotonicClock` type as an init default.
    nonisolated public static func defaultClock() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
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
        playbackStartedAt = nil
        promisedSeconds = 0
        silentSinceLastCommand.removeAll()
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
    ///
    /// ## De-duplication (central for every ADD path)
    /// This is the single append seam every ADD flows through (drag-drop, Add
    /// Files…, Add Folder…, the classic playlist window's ADD), so the "no
    /// duplicates" rule lives HERE: a track whose file is ALREADY in the queue is
    /// skipped, and repeats WITHIN one batch collapse to a single entry — the
    /// FIRST occurrence is kept and the incoming order is preserved. Membership is
    /// by CANONICAL file URL (`standardizedFileURL`), so the same file added by a
    /// different path spelling is one entry while two different files that merely
    /// share a name are not duplicates. When every incoming track is a duplicate
    /// the queue is unchanged and the selection is left untouched — so an
    /// all-duplicate add never re-fires an empty-queue auto-play upstream.
    public func append(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        var seen = Set(playlist.map { $0.url.standardizedFileURL })
        var fresh: [Track] = []
        fresh.reserveCapacity(tracks.count)
        for track in tracks where seen.insert(track.url.standardizedFileURL).inserted {
            fresh.append(track)
        }
        guard !fresh.isEmpty else { return }
        playlist.append(contentsOf: fresh)
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

    // MARK: - Metadata write-back

    /// Write a resolved track `duration` (seconds) into EVERY playlist row whose
    /// `url` matches. This is how an ASYNC metadata read done after a file was
    /// added (e.g. the app resolving `AVURLAsset.load(.duration)`) fills the
    /// default face's playlist Time column in — `PlayerCore` stays Foundation-only
    /// and just receives the number.
    ///
    /// URL-keyed (not index-keyed) on purpose: the load may finish AFTER the queue
    /// was reordered or partly removed, and the same file may appear more than
    /// once, so matching by URL lands on the right track(s) regardless and updates
    /// every copy. A non-finite or non-positive value is a guarded no-op (an
    /// unreadable file keeps showing "—" rather than a bogus "0:00"), as is a URL
    /// no longer in the queue. Mutating `playlist` in place drives the observable
    /// update, so the row's Time cell refreshes as each duration resolves.
    public func setDuration(_ duration: TimeInterval, forURL url: URL) {
        guard duration.isFinite, duration > 0 else { return }
        for index in playlist.indices where playlist[index].url == url {
            playlist[index].duration = duration
        }
    }

    // MARK: - Playlist reorder (move / sort / reverse / randomize)

    /// Move the rows at `offsets` so they land, in their existing relative
    /// order, immediately before the row that sat at `destination` in the
    /// ORIGINAL list — the `Array.move(fromOffsets:toOffset:)` convention, which
    /// is exactly what SwiftUI's `onMove` hands a `List` (so the default face's
    /// drag-to-reorder forwards its arguments untouched). `destination` may be
    /// `playlist.count` to move to the very end.
    ///
    /// The EDIT RULE holds: the selection FOLLOWS THE PLAYING TRACK — drag the
    /// playing row and the now-playing marker moves with it; drag other rows
    /// across it and `currentIndex` is remapped so it still names the same
    /// track. The engine is never touched (no reload, no stop), so the audio
    /// never skips, and next / previous afterwards walk the NEW order.
    ///
    /// Guarded no-ops: an empty or fully out-of-range `offsets` (out-of-range
    /// members of a partly valid set are dropped, like `remove(at:)`), a
    /// `destination` outside `0...playlist.count`, and a move whose result is
    /// the same order (the block would land where it already is) — the latter
    /// returns before mutating `playlist`, so observers see no change at all.
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.intersection(IndexSet(playlist.indices))
        guard !valid.isEmpty, (0...playlist.count).contains(destination) else { return }

        let permutation = Self.movePermutation(count: playlist.count, lifting: valid, before: destination)
        guard permutation != Array(playlist.indices) else { return }

        applyReorder(permutation)
    }

    /// The permutation (new position -> old index) that lifts `lifted` out of
    /// `0..<count`, keeps their relative order, and re-inserts them before the
    /// element that sat at `destination` — `MutableCollection.move(fromOffsets:
    /// toOffset:)`'s exact semantics, re-derived here because that method ships
    /// in the SwiftUI overlay, which this Foundation-only tier cannot import.
    /// The insertion point in the staying rows is `destination` minus the lifted
    /// rows that sat before it (they no longer occupy those slots).
    nonisolated private static func movePermutation(
        count: Int, lifting lifted: IndexSet, before destination: Int
    ) -> [Int] {
        let staying = (0..<count).filter { !lifted.contains($0) }
        let insertion = destination - lifted.count(in: 0..<destination)
        return Array(staying[..<insertion]) + Array(lifted) + Array(staying[insertion...])
    }

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

        silentSinceLastCommand.removeAll()

        if !isPlaying, loadedIndex == index {
            // Resuming the already-loaded, paused current track: do not reload,
            // so the engine preserves its current position.
            //
            // The silent-finish window is deliberately NOT re-opened here. Time
            // spent paused counts towards the elapsed side of that test, which
            // can only make a finish look SLOWER than it was — a missed verdict,
            // never a false one. Re-basing on resume would instead risk
            // condemning a track the listener paused a moment before its end.
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
    /// At the LAST track this wraps to the first whenever repeat is on (`.all` or
    /// `.one`) and stops only under `.off`. `canGoNext` is the matching predicate.
    public func next() {
        guard !playlist.isEmpty, let index = currentIndex else { return }

        // Fresh intent (a press, or an honest end-of-track): forget which rows
        // were found silent during the previous walk.
        silentSinceLastCommand.removeAll()

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
            // At the last track: repeat ON (either mode) wraps to the front;
            // only `.off` stops here.
            switch repeatMode {
            case .all, .one:
                currentIndex = 0
                playCurrent()
            case .off:
                stop()
            }
        }
    }

    /// Retreat to the previous track per `repeatMode`, then play it. At the FIRST
    /// track this wraps to the last whenever repeat is on (`.all` or `.one`) and
    /// restarts the track in place only under `.off`. `canGoPrevious` is the
    /// matching predicate, and `previousTargetIndex(from:)` is the single
    /// definition of where the press lands that they both read.
    ///
    /// If that target turns out to be UNPLAYABLE — whether it refuses to open or
    /// opens and renders nothing (see "Unplayable files" at the top of this file)
    /// — the recovery walk runs BACKWARD, mirroring `next()`'s forward walk: a
    /// `◀◀` press never moves the listener forward, and one file the engine
    /// cannot play cannot make everything before it unreachable.
    public func previous() {
        guard !playlist.isEmpty, let index = currentIndex,
              let target = previousTargetIndex(from: index) else { return }

        silentSinceLastCommand.removeAll()
        currentIndex = target
        playCurrent(walking: .backward)
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
        // A seek re-bases the silent-finish window: after jumping to 99.9 s of a
        // 100 s track the engine owes only 0.1 s of audio, and finishing a moment
        // later is honest rather than suspicious.
        silentSinceLastCommand.removeAll()
        playbackStartedAt = now()
        promisedSeconds = max(0, engine.duration - engine.currentTime)
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
        silentSinceLastCommand.removeAll()
        currentIndex = index
        playCurrent()
    }

    // MARK: - Engine callback

    /// Called when the engine finishes the current track.
    ///
    /// A finish that arrived too fast to be real is not a finish at all — it is
    /// an unplayable track that happened to LOAD (see `finishLooksLikeSilence`),
    /// and it is handled by the skip machinery instead of by repeat policy.
    /// Otherwise the repeat rules are exactly as they always were:
    /// - `.one`: reload and replay the same track.
    /// - `.all`: advance with wrap.
    /// - `.off`: advance, or stop if already at the last track.
    private func handlePlaybackFinished() {
        guard !playlist.isEmpty, let index = currentIndex else { return }

        if finishLooksLikeSilence() {
            skipPastSilentTrack(at: index)
            return
        }

        switch repeatMode {
        case .one:
            // Replay the same track, still walking the way the listener's press
            // pointed should this reload now fail (the file may have vanished).
            playCurrent(walking: lastSkipDirection)
        case .all, .off:
            next()
        }
    }

    /// Whether the finish just reported can be believed.
    ///
    /// The engine promised `promisedSeconds` of audio and then claimed to have
    /// played it in less than `silentFinishWindow` of real time. No decoder can
    /// do that: the segment drained without rendering. The `promisedSeconds`
    /// floor keeps a genuinely tiny track (a jingle, a gapless fragment) from
    /// being condemned for the crime of being short, and because the window is a
    /// quarter of a second, a listener who seeks to the very end still gets an
    /// honest finish — `seek(to:)` re-bases the promise for exactly that reason.
    ///
    /// - Note: The clock is the injected `now`, so this is testable without
    ///   sleeping, and it is monotonic, so a wall-clock adjustment cannot make a
    ///   real finish look instant.
    private func finishLooksLikeSilence() -> Bool {
        guard let startedAt = playbackStartedAt else { return false }
        guard promisedSeconds > Self.silentFinishMinimumPromise else { return false }
        return now() - startedAt < Self.silentFinishWindow
    }

    /// Treat `index` as unplayable and keep walking the way the press pointed —
    /// the same recovery `playCurrent` runs for a load that threw, reached from
    /// the finish callback instead of from the `catch`.
    ///
    /// The candidate is refused if it is ALREADY known silent, which is what
    /// makes an all-silent queue come to rest instead of sweeping round under
    /// `.all`.
    ///
    /// Like the failed-load recovery it mirrors, this steps LINEARLY even while
    /// shuffling: recovering from a dead file is a repair, not a pick, and the
    /// next real `next()` press resumes shuffling normally.
    private func skipPastSilentTrack(at index: Int) {
        silentSinceLastCommand.insert(index)
        let direction = lastSkipDirection
        let candidate = direction == .forward
            ? nextPlayableCursor(after: index)
            : previousPlayableCursor(before: index)
        guard let candidate, !silentSinceLastCommand.contains(candidate) else {
            stop()
            return
        }
        currentIndex = candidate
        playCurrent(walking: direction)
    }

    // MARK: - Helpers

    /// Which way the unplayable-file recovery walk steps.
    ///
    /// It follows the PRESS, not the playlist: `▶▶` (and `play()`, `select()`,
    /// auto-advance) walk forward; `◀◀` walks backward. Recovering in the wrong
    /// direction is not merely inelegant — a backward press that recovers forward
    /// lands the listener back on the track they just left, which makes every
    /// track before a dead file permanently unreachable.
    private enum SkipDirection { case forward, backward }

    // MARK: Silent-finish thresholds

    /// A natural finish arriving sooner than this after the track started
    /// rendering did not play anything. A quarter of a second is far longer than
    /// the millisecond-scale drain of a container the decoder opens but cannot
    /// read, and far shorter than any audible fragment a listener could have
    /// heard, so nothing real falls between the two.
    private static let silentFinishWindow: TimeInterval = 0.25

    /// Below this much promised audio, a fast finish is simply a short track and
    /// is believed. Only a file claiming MORE than a second and delivering it
    /// instantly is condemned.
    private static let silentFinishMinimumPromise: TimeInterval = 1.0

    /// Load the current track and start the engine, skipping unplayable tracks in
    /// `direction`. If no track reachable that way is playable, stop.
    private func playCurrent(walking direction: SkipDirection = .forward) {
        guard !playlist.isEmpty, let index = currentIndex,
              playlist.indices.contains(index) else { return }

        // Remember which way this walk was heading: a track that loads fine and
        // only reveals itself as unplayable when it finishes instantly has to
        // carry on the same way (see `skipPastSilentTrack(at:)`).
        lastSkipDirection = direction

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
                // Open the window in which a "finished" report would be a lie:
                // from now, for as many seconds as the engine says this file
                // holds.
                playbackStartedAt = now()
                promisedSeconds = engine.duration
                return
            } catch {
                // Unplayable: keep walking the way the press pointed.
                let recovery = direction == .forward
                    ? nextPlayableCursor(after: cursor)
                    : previousPlayableCursor(before: cursor)
                if let recovery {
                    cursor = recovery
                } else {
                    stop()
                    return
                }
            }
        }
    }

    /// The index to try after an unplayable track, honoring `.all` wrap. With
    /// `.off`/`.one` it does not wrap past the end.
    ///
    /// This is the UNPLAYABLE-FILE skip, not navigation, and it deliberately did
    /// NOT adopt the `.one` wrap: a queue of dead files under `.one` must come to
    /// rest rather than sweep the list a second time. (`playCurrent`'s `visited`
    /// set already bounds the walk, so this is belt-and-braces.) The listener's
    /// own `next()` press still wraps — that is a different code path.
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

    /// The index to try BEFORE an unplayable track — the mirror image of
    /// `nextPlayableCursor(after:)`, used when the walk was started by `◀◀`.
    ///
    /// It honours exactly the same wrap policy: `.all` wraps round to the last
    /// track, `.off`/`.one` come to rest at the front rather than sweeping the
    /// queue a second time. (`playCurrent`'s `visited` set already bounds the
    /// walk; this keeps the two directions' POLICY identical so a listener cannot
    /// tell them apart except by which way they move.)
    private func previousPlayableCursor(before cursor: Int) -> Int? {
        if cursor > 0 {
            return cursor - 1
        }
        switch repeatMode {
        case .all:
            return playlist.count - 1
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
        // Nothing is rendering, so there is no finish left to disbelieve.
        playbackStartedAt = nil
        promisedSeconds = 0
    }
}
