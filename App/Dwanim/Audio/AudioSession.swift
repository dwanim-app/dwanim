import AppKit
import DwanimUI
import Foundation
import PlaybackKit
import PlayerCore
import SkinAppKit
import SpectrumKit
import UniformTypeIdentifiers

// MARK: - AudioSession
//
// The app-layer coordinator that turns the default-skin scene into a REAL
// sandboxed audio player. It owns the live wiring the seed (DwanimApp) only
// hinted at:
//
//   • the PlayerCore + AVAudioEnginePlayer transport (created here, observed by
//     the SwiftUI scene),
//   • the PlayerViewModel the scene reads for the live clock + spectrum levels,
//   • the security-scoped bookmark machinery (mint / persist / resolve) via the
//     injected `SecurityScopedFileAccess` + `BookmarkStore` + pure
//     `BookmarkResolver`,
//   • the RedrawLoop feed (engine tap -> SpectrumFeed -> analyzer -> model),
//   • the "Open Audio…" panel flow, and
//   • launch-resolve (reopen the last song, ready/paused).
//
// It mirrors SkinHarness's `DefaultSkinController` pattern for the feed, but is
// driven by the SwiftUI App lifecycle rather than an AppKit window controller.
//
// ## Security-scope lifetime (documented)
// A file is playable only inside an open security scope. We keep scopes open for
// the *currently loaded playlist* (the "session scopes"): `beginSession(for:)`
// takes the loaded URLs, calls `startAccessingSecurityScopedResource()` once per
// URL, and stashes each (with whether it actually opened a scope). The scopes
// stay open while that playlist is loaded — so the playlist window can select +
// play ANY queued track, not just the first — and are closed (matching
// `stopAccessing…`) only when we replace the playlist or the app quits
// (`endSession()`). A single-file open is just a one-element playlist. Short,
// self-contained touches (minting a bookmark at open time) use the transient
// `withAccess` bracket instead. This avoids re-opening/closing scopes on every
// transport tick while still keeping every bracket balanced.
@MainActor
final class AudioSession {

    /// The live transport. Created with the real engine so the wiring is honest;
    /// the SwiftUI scene observes this for `isPlaying` / `currentTrack` / actions.
    let core: PlayerCore

    /// The presentation bridge for the live clock + spectrum levels. The scene
    /// observes this for `progress` / `levels`.
    let model: PlayerViewModel

    /// The concrete audio engine, retained both as the transport's engine and as
    /// the `AudioTapProviding` source the RedrawLoop installs its PCM tap on.
    private let engine: AVAudioEnginePlayer

    /// Platform seams: security-scoped access + the JSON/UserDefaults store, and
    /// the pure resolve/record/refresh policy that sits on top of them.
    private let access: SecurityScopedFileAccess
    private let store: BookmarkStore
    private let resolver: BookmarkResolver

    /// The optional classic `.wsz` skin window coordinator. It drives the SAME
    /// shared `core` (and the same engine tap/format sources + bookmark seams), so
    /// the classic main window — when opened via "Open Skin…" — is just a second
    /// face on this one transport. Created here so the shared dependencies are
    /// injected once; the window itself is opened on demand.
    private let classicSkin: ClassicSkinPresenter

    /// The spectrum pipeline: the lock-guarded latest-PCM box the tap writes and
    /// the analyzer the tick reads it through, plus the shared redraw cadence.
    private let analyzer: SpectrumAnalyzer
    private let latestSamples = SpectrumFeed()
    private var redrawLoop: RedrawLoop?

    /// The URLs whose security scopes are currently held open for the session
    /// (the loaded playlist — one element for a single-file open), each paired with
    /// whether the matching `startAccessingSecurityScopedResource()` actually opened
    /// a scope. We only issue the balancing `stop…` for the ones that did — mirroring
    /// the `withAccess` bracket discipline (don't decrement a scope another owner
    /// holds, e.g. the live panel grant for a freshly-picked URL). Empty when nothing
    /// is loaded. See the lifetime note above.
    private var sessionScopes: [(url: URL, didStart: Bool)] = []

    /// Whether `start()` has run without a matching `stop()`. Guards against a
    /// second window's `.onAppear` double-starting the shared `@State` session
    /// (and a stray `.onDisappear` double-stopping it).
    private var started = false

    /// Spectrum bar count for the compact default-skin row (matches the harness).
    private static let barCount = 24
    /// ~22 Hz feed cadence (matches the harness default-skin player).
    private static let tickInterval: TimeInterval = 0.045

    // MARK: Init

    init() {
        let engine = AVAudioEnginePlayer()
        self.engine = engine
        self.core = PlayerCore(engine: engine)
        self.model = PlayerViewModel()
        let access = SecurityScopedFileAccess()
        let store = BookmarkStore()
        let resolver = BookmarkResolver(access: access)
        self.access = access
        self.store = store
        self.resolver = resolver
        self.analyzer = SpectrumAnalyzer(barCount: AudioSession.barCount)

        // The classic-skin coordinator shares this session's transport + engine
        // (the engine is both the PCM-tap and track-format source, exactly as the
        // harness passes it) and the one set of bookmark seams, so "Open Skin…"
        // hosts a classic main window driven by the SAME core the default scene
        // plays through.
        //
        // SINGLE-TAP RULE: this session owns THE one engine tap (installed by the
        // RedrawLoop below, writing `latestSamples`). The shared feed is injected so
        // the hosted classic MAIN window reads THIS already-fed snapshot rather than
        // installing its own tap. AVAudioEngine allows only one tap per node bus, so
        // a second tap would steal it (freezing the default scene) and removing it on
        // window close would kill it permanently. With the feed injected the hosted
        // window's redraw loop is timer-only and touches no tap.
        self.classicSkin = ClassicSkinPresenter(
            core: core, tap: engine, format: engine,
            sharedFeed: latestSamples,
            access: access, store: store, resolver: resolver
        )

        // The feed: install the engine's PCM tap (audio thread stashes into the
        // feed) and run a main-thread tick that copies the clock + spectrum into
        // the model. `assumeIsolated` is sound because RedrawLoop fires onTick on
        // the main run loop (same pattern as DefaultSkinController).
        redrawLoop = RedrawLoop(
            interval: AudioSession.tickInterval,
            tap: engine,
            feed: latestSamples
        ) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: Lifecycle

    /// Start the feed and reopen the last song (ready/paused). Call once when the
    /// app's window appears. Idempotent: a second window's `.onAppear` on the
    /// shared session returns early rather than double-starting.
    func start() {
        guard !started else { return }
        started = true
        redrawLoop?.start()
        resolveLastAudioOnLaunch()
        // Remember (but do NOT auto-open) the last classic skin — see
        // ClassicSkinPresenter.resolveLastSkinOnLaunch for why auto-open is
        // deliberately deferred.
        classicSkin.resolveLastSkinOnLaunch()
    }

    /// Tear the session down on quit: stop the feed and release the session
    /// security scope. Mirrors `DefaultSkinController.tearDown`. Idempotent: a
    /// `.onDisappear` with no live session returns early.
    func stop() {
        guard started else { return }
        started = false
        redrawLoop?.stop()
        endSession()
        // Close every hosted classic window (main + playlist + EQ) too, so a hosted
        // window never outlives the session that drives it.
        classicSkin.closeAllWindows()
    }

    // MARK: Open Skin…

    /// Present the "Open Skin…" panel and host the picked classic `.wsz` window,
    /// driven by THIS session's shared core. Pass-through to the classic-skin
    /// coordinator (which owns the panel + load + window-hosting). Closing that
    /// window does NOT quit the app (it is hosted, not the harness's single
    /// window).
    func presentOpenSkinPanel() {
        classicSkin.presentOpenPanel()
    }

    // MARK: View menu (Playlist / Equalizer toggles)

    /// Whether a classic skin is currently loaded — i.e. whether the View-menu
    /// Playlist / Equalizer toggles can host anything. The SwiftUI `.commands`
    /// reads this to gate (and, when absent, redirect to "Open Skin…") those items.
    var isSkinLoaded: Bool { classicSkin.isSkinLoaded }

    /// Toggle the hosted classic PLAYLIST window. When no skin is loaded yet, fall
    /// back to presenting "Open Skin…" (the playlist is a face of a loaded skin, so
    /// there is nothing to show without one) — the menu item stays usable rather
    /// than dead.
    func togglePlaylistWindow() {
        guard classicSkin.isSkinLoaded else {
            classicSkin.presentOpenPanel()
            return
        }
        classicSkin.togglePlaylistWindow()
    }

    /// Toggle the hosted classic EQ window. Same no-skin fallback as the playlist
    /// toggle (present "Open Skin…" when nothing is loaded yet).
    func toggleEQWindow() {
        guard classicSkin.isSkinLoaded else {
            classicSkin.presentOpenPanel()
            return
        }
        classicSkin.toggleEQWindow()
    }

    /// Toggle the hosted classic MAIN window: close it if open, else reopen it (when
    /// a skin is loaded). This is the host's close affordance for the borderless
    /// region main window, which has NO titlebar / close button — without it there
    /// is no way to dismiss a region-skin main window short of a re-skin or quit.
    /// Same no-skin fallback as the other toggles (present "Open Skin…" when nothing
    /// is loaded yet).
    func toggleMainWindow() {
        guard classicSkin.isSkinLoaded else {
            classicSkin.presentOpenPanel()
            return
        }
        classicSkin.toggleMainWindow()
    }

    // MARK: One tick (the feed)

    /// Copy the live engine clock into the model and push fresh spectrum levels.
    /// Main thread, so the `@MainActor` model mutations are safe and SwiftUI
    /// re-renders from the observable changes.
    private func tick() {
        model.updateClock(currentTime: core.currentTime, duration: core.duration)
        let snapshot = latestSamples.latest()
        model.levels = analyzer.process(snapshot.samples, sampleRate: snapshot.sampleRate)
    }

    // MARK: Open + play

    /// Show an NSOpenPanel filtered to audio files, allowing MULTIPLE selection; on
    /// pick, record the whole selection as the ordered playlist + play it.
    ///
    /// The panel grants access to the picked URLs for this launch, so we can mint a
    /// bookmark per file directly (a transient `withAccess` bracket guards each
    /// mint). We persist them as the ordered `PersistedBookmarks.playlist` (and keep
    /// `.lastAudio` pointing at the first file for coherence), then open the
    /// long-lived session scopes and load + play the whole queue.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioSession.audioContentTypes
        panel.prompt = "Open"
        panel.message = "Choose one or more audio files to play."

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        openAndPlay(urls: urls)
    }

    /// Record `urls` as the ordered playlist (minting + persisting a bookmark per
    /// file, plus the first as `.lastAudio` for coherence), open the session scopes,
    /// then load the queue and play from the top.
    ///
    /// ## `.lastAudio` vs the playlist (coherence)
    /// The playlist SUPERSEDES the single `.lastAudio` slot: whenever we open a
    /// selection we also re-point `.lastAudio` at the first file, so the two never
    /// disagree, and launch-resolve prefers the playlist (falling back to
    /// `.lastAudio` only when the playlist is empty — e.g. a store written by an
    /// older build). The single-file open is just a one-element playlist.
    private func openAndPlay(urls: [URL]) {
        recordPlaylist(urls)
        beginSession(for: urls)
        core.load(urls.map(trackForURL))
        core.play()
    }

    /// Mint a bookmark per `url` (each inside its own live panel-grant bracket) and
    /// persist them as the ordered playlist, plus re-point `.lastAudio` at the first
    /// file. A per-file mint failure simply drops that file from the persisted
    /// playlist (it still plays THIS launch via the session scope); a file with no
    /// bookmark just won't reopen on the next launch.
    private func recordPlaylist(_ urls: [URL]) {
        var current = store.load()
        var playlistData: [Data] = []
        for url in urls {
            // Belt-and-suspenders bracket: the panel already grants access, but
            // bracketing the mint keeps the contract uniform with the resolve path.
            if let data = try? access.withAccess(to: url, perform: {
                try access.bookmarkData(for: url)
            }) {
                playlistData.append(data)
            }
        }
        current.setPlaylist(playlistData)
        // Keep the single-slot `.lastAudio` coherent with the playlist head.
        if let first = urls.first {
            current = (try? access.withAccess(to: first) {
                try resolver.record(url: first, as: .lastAudio, in: current)
            }) ?? current
        }
        store.save(current)
    }

    // MARK: Launch resolve

    /// On launch: reopen the last session **ready/paused** (do NOT auto-play). The
    /// ordered PLAYLIST is preferred — if it resolves to one or more URLs we open
    /// their session scopes and load the whole queue. When the playlist is empty
    /// (e.g. a store written by an older single-file build) we fall back to the
    /// `.lastAudio` slot. Either way the store is persisted when the resolver
    /// refreshed (stale re-mint) or dropped (failed resolve) anything.
    private func resolveLastAudioOnLaunch() {
        let loaded = store.load()

        // Prefer the playlist.
        let playlist = resolver.resolvePlaylist(in: loaded)
        if !playlist.urls.isEmpty {
            if playlist.store != loaded {
                store.save(playlist.store)
            }
            beginSession(for: playlist.urls)
            // Load (selects index 0) WITHOUT play: the scene shows the reopened
            // first title and a ready transport until the user presses play.
            core.load(playlist.urls.map(trackForURL))
            return
        }

        // No playlist — fall back to the single `.lastAudio` slot. Resolve over the
        // playlist's possibly-updated store so a playlist drop is not lost.
        let resolution = resolver.resolve(role: .lastAudio, in: playlist.store)
        if resolution.store != loaded {
            store.save(resolution.store)
        }
        guard let url = resolution.url else { return }
        beginSession(for: [url])
        core.load([trackForURL(url)])
    }

    // MARK: Session scope lifetime

    /// Open the long-lived security scopes for `urls` (the loaded playlist; one
    /// element for a single-file open), closing any previously held session scopes
    /// first (so we never leak scopes across a playlist replacement). Holding a
    /// scope for EVERY queued file — not just the first — is what lets the playlist
    /// window select + play any track under the sandbox.
    private func beginSession(for urls: [URL]) {
        endSession()
        // Start each scope for the duration the playlist is loaded. For a URL
        // freshly picked in this launch this may return `false` (already
        // accessible); stash that result so `endSession` issues a balancing stop
        // only when we truly opened a scope. The resolved-from-bookmark case is the
        // one that returns `true` and needs the matching stop.
        sessionScopes = urls.map { url in
            (url: url, didStart: url.startAccessingSecurityScopedResource())
        }
    }

    /// Close every held session security scope, if any. Idempotent. Only issues the
    /// balancing `stop…` for the scopes `beginSession` actually started.
    private func endSession() {
        for scope in sessionScopes where scope.didStart {
            scope.url.stopAccessingSecurityScopedResource()
        }
        sessionScopes = []
    }

    // MARK: Helpers

    /// Build a `Track` whose title is the file's own name stem (the user's file —
    /// fine to display; NO brand title is invented), matching the harness.
    private func trackForURL(_ url: URL) -> Track {
        let stem = url.deletingPathExtension().lastPathComponent
        return Track(url: url, title: stem)
    }

    /// The audio UTTypes the open panel accepts. `.audio` is the broad umbrella;
    /// the common concrete types are listed so files that do not advertise the
    /// umbrella conformance (and are still openable by the engine) are selectable.
    private static let audioContentTypes: [UTType] = {
        var types: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        if let flac = UTType("org.xiph.flac") { types.append(flac) }
        if let m4a = UTType("com.apple.m4a-audio") { types.append(m4a) }
        return types
    }()
}
