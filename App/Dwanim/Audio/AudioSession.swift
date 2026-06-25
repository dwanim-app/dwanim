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
// A file is playable only inside an open security scope. We keep ONE scope open
// for the *currently loaded* file (the "session scope"): `beginSession(for:)`
// calls `startAccessingSecurityScopedResource()` once and stashes the URL; the
// scope stays open while that file is loaded/playing/paused, and is closed
// (matching `stopAccessing…`) only when we replace it with another file or the
// app quits (`endSession()`). Short, self-contained touches (minting a bookmark
// at open time) use the transient `withAccess` bracket instead. This avoids
// re-opening/closing the scope on every transport tick while still keeping the
// bracket balanced.
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

    /// The spectrum pipeline: the lock-guarded latest-PCM box the tap writes and
    /// the analyzer the tick reads it through, plus the shared redraw cadence.
    private let analyzer: SpectrumAnalyzer
    private let latestSamples = SpectrumFeed()
    private var redrawLoop: RedrawLoop?

    /// The URL whose security scope is currently held open for the session, or
    /// `nil` when no file is loaded, paired with whether the matching
    /// `startAccessingSecurityScopedResource()` actually opened a scope. We only
    /// issue the balancing `stop…` when it did — mirroring the `withAccess`
    /// bracket discipline (don't decrement a scope another owner holds, e.g. the
    /// live panel grant for a freshly-picked URL). See the lifetime note above.
    private var sessionScopedURL: URL?
    private var sessionScopeDidStart = false

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
        self.access = SecurityScopedFileAccess()
        self.store = BookmarkStore()
        self.resolver = BookmarkResolver(access: access)
        self.analyzer = SpectrumAnalyzer(barCount: AudioSession.barCount)

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
    }

    /// Tear the session down on quit: stop the feed and release the session
    /// security scope. Mirrors `DefaultSkinController.tearDown`. Idempotent: a
    /// `.onDisappear` with no live session returns early.
    func stop() {
        guard started else { return }
        started = false
        redrawLoop?.stop()
        endSession()
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

    /// Show an NSOpenPanel filtered to audio files; on pick, record + play.
    ///
    /// The panel itself grants access to the picked URL for this launch, so we
    /// can mint a bookmark from it directly (a transient `withAccess` bracket
    /// guards the mint). We persist that bookmark as `.lastAudio`, then open the
    /// long-lived session scope and load + play.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioSession.audioContentTypes
        panel.prompt = "Open"
        panel.message = "Choose an audio file to play."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openAndPlay(url: url)
    }

    /// Record `url` as the last audio (minting + persisting its bookmark), open
    /// the session scope, then load and play it.
    private func openAndPlay(url: URL) {
        // Mint + persist the bookmark while the panel grant is live. The transient
        // bracket is belt-and-suspenders: the panel already grants access, but
        // bracketing the mint keeps the contract uniform.
        var current = store.load()
        do {
            current = try access.withAccess(to: url) {
                try resolver.record(url: url, as: .lastAudio, in: current)
            }
            store.save(current)
        } catch {
            // Minting failed (vanished file / missing entitlement). We can still
            // play this launch's pick (the panel grant is live), it just will not
            // be remembered across relaunch. Fall through to play.
        }

        beginSession(for: url)
        core.load([trackForURL(url)])
        core.play()
    }

    // MARK: Launch resolve

    /// On launch: resolve the `.lastAudio` bookmark; if it yields a URL, open its
    /// session scope and load it **ready/paused** (do NOT auto-play), so the app
    /// reopens the last song across launches. Persist the store if the resolver
    /// refreshed (stale re-mint) or dropped (failed resolve) the entry.
    private func resolveLastAudioOnLaunch() {
        let loaded = store.load()
        let resolution = resolver.resolve(role: .lastAudio, in: loaded)

        // The resolver hands back a possibly-updated store; write it back only
        // when it actually changed (refresh/drop), per the resolver's contract.
        if resolution.store != loaded {
            store.save(resolution.store)
        }

        guard let url = resolution.url else { return }
        beginSession(for: url)
        // Load (selects index 0) WITHOUT play: the scene shows the reopened title
        // and an empty/ready transport until the user presses play.
        core.load([trackForURL(url)])
    }

    // MARK: Session scope lifetime

    /// Open the long-lived security scope for `url`, closing any previously held
    /// session scope first (so we never leak a scope across a file replacement).
    private func beginSession(for url: URL) {
        endSession()
        // Start the scope for the duration the file is loaded. For a URL freshly
        // picked in this launch this may return `false` (already accessible);
        // stash that result so `endSession` issues a balancing stop only when we
        // truly opened a scope here. The resolved-from-bookmark case is the one
        // that returns `true` and needs the matching stop.
        let didStart = url.startAccessingSecurityScopedResource()
        sessionScopedURL = url
        sessionScopeDidStart = didStart
    }

    /// Close the held session security scope, if any. Idempotent. Only issues the
    /// balancing `stop…` when `beginSession` actually started a scope.
    private func endSession() {
        if let url = sessionScopedURL {
            if sessionScopeDidStart {
                url.stopAccessingSecurityScopedResource()
            }
            sessionScopedURL = nil
            sessionScopeDidStart = false
        }
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
