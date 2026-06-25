import AppKit
import Foundation
import PlayerCore
import SkinAppKit
import SkinKit
import SkinKitImageIO
import SkinRender
import UniformTypeIdentifiers

// MARK: - ClassicSkinPresenter
//
// The app-layer coordinator for the OPTIONAL classic `.wsz` skin window. It is
// the "Open Skin…" counterpart to the default-skin scene: the user picks a `.wsz`
// archive, and this type loads it and hosts the classic MAIN window IN-APP,
// driven by the SAME shared `PlayerCore` the default scene plays through. So the
// classic window shows the CURRENTLY-LOADED song — its marquee / time / spectrum
// animate and its transport buttons drive the one shared core.
//
// ## What lives here vs. elsewhere
//   - The skin LOAD (`SkinLoader` + the concrete `ImageIOBitmapDecoder`) and the
//     SECURITY-SCOPED bookmark machinery (mint / persist / resolve the `.lastSkin`
//     slot) live HERE, in the app layer — exactly where the `.lastAudio` open
//     machinery lives (`AudioSession`). The pure resolve/record policy stays in
//     `BookmarkResolver`; the platform calls stay in `SecurityScopedFileAccess` /
//     `BookmarkStore`.
//   - The window CONSTRUCTION + the live controllers live one tier down, in
//     `SkinAppKit` (`showInteractiveWindow` / `showPlaylistWindow` /
//     `showEQWindow`). This presenter just calls them with
//     `terminatesAppOnClose: false` so closing a classic window tears it down and
//     drops that window's handle WITHOUT quitting the app (the default scene and
//     the other classic windows survive).
//
// ## The three-window CLUSTER
// A single loaded skin drives a cluster of up to THREE classic windows — the MAIN
// window, the PLAYLIST window, and the EQ window — all built from the SAME loaded
// `Skin` and driven by the SAME shared `PlayerCore`. The presenter keeps:
//   - the loaded `skin` (so the playlist / EQ windows can be opened on demand, and
//     so an "Open Skin…" re-skin can rebuild any open window with the new skin),
//   - one independent handle per window (`mainHandle` / `playlistHandle` /
//     `eqHandle`), each held while its window is open and dropped on that window's
//     own close. Closing one window does NOT close the others or quit the app.
// The main window opens immediately when a skin is applied; the playlist and EQ
// windows are TOGGLED open/closed by the host (the View menu).
//
// ## Re-skin strategy (Open Skin… with windows already open)
// Opening a NEW skin while windows are open RE-SKINS the cluster: the presenter
// records which windows are currently open (main is always open after a load; the
// playlist / EQ open-state is captured first), tears every open window down, swaps
// in the new `skin`, then REBUILDS each window that was open — same shared core,
// new skin bitmaps. This is simpler and more robust than mutating a live
// controller's skin in place (the controllers cache composed geometry derived from
// the old skin), and it keeps one construction path. Window position is not
// preserved across a re-skin (each rebuilt window re-centers) — an acceptable
// trade for this increment.
//
// ## Shared core
// The shared `PlayerCore` (and the engine's opt-in PCM-tap / format sources) are
// injected from `AudioSession`, so every classic window and the default scene are
// faces of ONE transport: pressing play in any of them drives the same playback,
// and dragging an EQ band changes the SAME audio (the EQ controller pushes to the
// shared core, which drives the real `AVAudioUnitEQ`).
//
// ## Security-scope lifetime
// The skin file is only read at OPEN time (decoded into memory once; the live
// windows draw from the in-memory `Skin`, never re-reading the archive). So,
// unlike the audio session, NO long-lived skin scope is held — the transient
// `withAccess` bracket around the load is sufficient. The freshly-picked panel
// URL is already accessible for this launch; the bracket re-arms the grant for a
// URL recovered from the `.lastSkin` bookmark.
//
// NO brand words appear in any user-facing string here (§12).
@MainActor
final class ClassicSkinPresenter {

    /// The shared transport the classic window drives (same instance the default
    /// scene plays through). Injected; never created here.
    private let core: PlayerCore

    /// The engine's opt-in PCM-tap + track-format sources for the classic window's
    /// spectrum bars and kbps / kHz number boxes. `nil` is tolerated (the window
    /// simply renders no spectrum / format facts).
    private let tap: AudioTapProviding?
    private let format: TrackFormatProviding?

    /// The same security-scope + persistence seams `AudioSession` uses, so the
    /// `.lastSkin` slot is minted / persisted / resolved through one set of
    /// platform objects (and one `UserDefaults`-backed store).
    private let access: SecurityScopedFileAccess
    private let store: BookmarkStore
    private let resolver: BookmarkResolver

    /// The currently-loaded skin, kept so the playlist / EQ windows can be opened
    /// on demand and so an "Open Skin…" re-skin can rebuild any open window with the
    /// new bitmaps. `nil` until the first successful load. Its presence is what the
    /// host's View menu consults to enable the Playlist / Equalizer toggles.
    private var loadedSkin: Skin?

    /// Per-window handles (controller + window) of the three-window cluster. Each is
    /// held while its window is open (so it is not deallocated for the window's
    /// lifetime) and dropped on that window's own close (the `onClose` callback), so
    /// reopening builds a fresh one. Closing one leaves the others untouched.
    private var mainHandle: InteractiveWindowHandle?
    private var playlistHandle: PlaylistWindowHandle?
    private var eqHandle: EQWindowHandle?

    /// Integer zoom for the hosted classic windows. Matches the harness's default
    /// `--scale 2` so the in-app windows read at the same size as the dev path.
    private static let scale = 2

    /// The hosted classic windows' title-bar text used on the titled-fallback path
    /// (and for the playlist / EQ windows, which are always titled). Neutral,
    /// brand-free labels — the skin filename is NOT used (filenames may carry
    /// third-party brand names).
    private static let mainWindowTitle = "Skin"
    private static let playlistWindowTitle = "Playlist"
    private static let eqWindowTitle = "Equalizer"

    /// The content types the open panel accepts. A `.wsz` skin archive has no
    /// system-declared UTI (this app deliberately does NOT claim it as a document
    /// type — see project.yml), so we derive the type from the `wsz` filename
    /// extension. `UTType(filenameExtension:)` yields a dynamic type that still
    /// filters the panel to `.wsz` files; if the platform ever can't synthesize one
    /// we fall back to `.zip` (a `.wsz` IS a zip) so the panel is never unfiltered.
    private static let skinContentTypes: [UTType] = {
        if let wsz = UTType(filenameExtension: "wsz") {
            return [wsz]
        }
        return [.zip]
    }()

    // MARK: Init

    init(
        core: PlayerCore,
        tap: AudioTapProviding?,
        format: TrackFormatProviding?,
        access: SecurityScopedFileAccess,
        store: BookmarkStore,
        resolver: BookmarkResolver
    ) {
        self.core = core
        self.tap = tap
        self.format = format
        self.access = access
        self.store = store
        self.resolver = resolver
    }

    // MARK: Open Skin… (the panel flow)

    /// Show an `NSOpenPanel` filtered to `.wsz`; on pick, record + open.
    ///
    /// The panel grants access to the picked URL for this launch, so the bookmark
    /// can be minted from it directly. We persist that bookmark as `.lastSkin`,
    /// then load the skin and host the classic main window driven by the shared
    /// core.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ClassicSkinPresenter.skinContentTypes
        panel.prompt = "Open"
        panel.message = "Choose a skin archive (.wsz) to apply."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        recordAndOpen(url: url)
    }

    /// Record `url` as the last skin (minting + persisting its `.lastSkin`
    /// bookmark), then load and host the classic window. Mirrors
    /// `AudioSession.openAndPlay`'s record-then-use shape.
    private func recordAndOpen(url: URL) {
        // Mint + persist while the panel grant is live. Belt-and-suspenders: the
        // panel already grants access, but bracketing keeps the contract uniform.
        var current = store.load()
        do {
            current = try access.withAccess(to: url) {
                try resolver.record(url: url, as: .lastSkin, in: current)
            }
            store.save(current)
        } catch {
            // Minting failed (vanished file / missing entitlement). We can still
            // open this launch's pick (the panel grant is live); it just will not
            // be remembered across relaunch. Fall through to open.
        }

        openWindow(for: url)
    }

    // MARK: Launch resolve

    /// On launch: resolve the `.lastSkin` bookmark and persist the store when the
    /// resolver refreshed (stale re-mint) or dropped (failed resolve) the entry —
    /// the same shape as `AudioSession.resolveLastAudioOnLaunch`.
    ///
    /// DELIBERATE CHOICE for this increment (M5-prep ⑥b-2): we only *remember* the
    /// last skin; we do NOT auto-open the classic window on launch. Auto-open is a
    /// UX decision (which window is primary, whether to restore the classic face)
    /// that can land later; for now launch resolve is side-effect-free beyond
    /// keeping the persisted bookmark fresh. The returned URL is intentionally
    /// ignored.
    func resolveLastSkinOnLaunch() {
        let loaded = store.load()
        let resolution = resolver.resolve(role: .lastSkin, in: loaded)
        // Write back only when the resolve actually changed something (refresh /
        // drop), per the resolver's contract.
        if resolution.store != loaded {
            store.save(resolution.store)
        }
        // resolution.url is deliberately NOT acted on — see the doc comment.
    }

    // MARK: Cluster state (read by the host's View menu)

    /// Whether a skin is currently loaded — i.e. whether the Playlist / Equalizer
    /// toggles can do anything. The host's View menu reads this to enable/disable
    /// (or gate) those commands.
    var isSkinLoaded: Bool { loadedSkin != nil }

    // MARK: Window hosting

    /// Load the skin at `url` (inside its security scope), remember it, and host the
    /// cluster. The MAIN window always (re)opens; if a playlist / EQ window was open
    /// under the previous skin it is RE-SKINNED (rebuilt with the new skin), so
    /// "Open Skin…" swaps the whole visible cluster to the new look. Leaves any
    /// existing windows untouched on a load failure.
    private func openWindow(for url: URL) {
        let skin: Skin
        do {
            skin = try access.withAccess(to: url) {
                let data = try Data(contentsOf: url)
                return try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
            }
        } catch {
            // Could not read / decode the skin (vanished file, malformed archive).
            // Surface a non-fatal alert and leave any existing windows untouched.
            presentLoadFailure(error)
            return
        }

        // A skin with no composable main background cannot be hosted; the
        // constructor would throw `RenderError`. Guard with a friendly alert rather
        // than letting the throw bubble.
        guard MainWindowComposer.compose(skin) != nil else {
            presentLoadFailure(nil)
            return
        }

        // Re-skin: capture which auxiliary windows are open BEFORE tearing the old
        // cluster down, so we can rebuild exactly those with the new skin. (The main
        // window is always (re)opened after a load.)
        let hadPlaylist = playlistHandle != nil
        let hadEQ = eqHandle != nil

        // Close any windows already open before building new ones, so reopening a
        // skin never stacks two clusters on the one shared core.
        closeAllWindows()

        loadedSkin = skin
        openMainWindow(skin: skin)
        if hadPlaylist { openPlaylistWindow(skin: skin) }
        if hadEQ { openEQWindow(skin: skin) }
    }

    /// Build the classic MAIN window from `skin`, driven by the shared core, and
    /// hold its handle. A failure surfaces an alert and leaves the handle `nil`.
    private func openMainWindow(skin: Skin) {
        // Normalize an empty-polygon region to nil (same as the harness path).
        let region = skin.region.flatMap { $0.polygons.isEmpty ? nil : $0 }
        do {
            mainHandle = try showInteractiveWindow(
                skin: skin,
                core: core,
                tap: tap,
                format: format,
                region: region,
                scale: ClassicSkinPresenter.scale,
                title: ClassicSkinPresenter.mainWindowTitle,
                // HOSTED mode: closing this window tears it down + drops just this
                // handle WITHOUT quitting the app (the default scene + the other
                // classic windows survive). The controller is NOT installed as the
                // app's NSApplicationDelegate.
                terminatesAppOnClose: false,
                onClose: { [weak self] in self?.mainHandle = nil }
            )
        } catch {
            presentLoadFailure(error)
        }
    }

    /// Build the classic PLAYLIST window from `skin`, driven by the shared core, and
    /// hold its handle. A failure surfaces an alert and leaves the handle `nil`.
    private func openPlaylistWindow(skin: Skin) {
        do {
            playlistHandle = try showPlaylistWindow(
                skin: skin,
                core: core,
                scale: ClassicSkinPresenter.scale,
                title: ClassicSkinPresenter.playlistWindowTitle,
                terminatesAppOnClose: false,
                onClose: { [weak self] in self?.playlistHandle = nil }
            )
        } catch {
            presentLoadFailure(error)
        }
    }

    /// Build the classic EQ window from `skin`, driven by the shared core, and hold
    /// its handle. A failure surfaces an alert and leaves the handle `nil`. The EQ
    /// controller pushes slider / preamp / ON gestures straight to the SHARED core,
    /// so moving a band changes the SAME playing audio.
    private func openEQWindow(skin: Skin) {
        do {
            eqHandle = try showEQWindow(
                skin: skin,
                core: core,
                scale: ClassicSkinPresenter.scale,
                title: ClassicSkinPresenter.eqWindowTitle,
                terminatesAppOnClose: false,
                onClose: { [weak self] in self?.eqHandle = nil }
            )
        } catch {
            presentLoadFailure(error)
        }
    }

    // MARK: Playlist / EQ toggles (the View menu)

    /// Toggle the PLAYLIST window: close it if open, else open it (when a skin is
    /// loaded). A no-op when no skin is loaded — the host gates the command on
    /// `isSkinLoaded`, but this guards the path defensively too.
    func togglePlaylistWindow() {
        if playlistHandle != nil {
            closePlaylistWindow()
        } else if let skin = loadedSkin {
            openPlaylistWindow(skin: skin)
        }
    }

    /// Toggle the EQ window: close it if open, else open it (when a skin is loaded).
    /// A no-op when no skin is loaded.
    func toggleEQWindow() {
        if eqHandle != nil {
            closeEQWindow()
        } else if let skin = loadedSkin {
            openEQWindow(skin: skin)
        }
    }

    // MARK: Programmatic close

    /// Close the hosted playlist window, if any. Closing routes through
    /// `windowWillClose` → `tearDown()` → our `onClose` (which nils the handle); we
    /// proactively nil it here too so the path is idempotent.
    private func closePlaylistWindow() {
        guard let playlistHandle else { return }
        self.playlistHandle = nil
        playlistHandle.window.close()
    }

    /// Close the hosted EQ window, if any. Idempotent (see `closePlaylistWindow`).
    private func closeEQWindow() {
        guard let eqHandle else { return }
        self.eqHandle = nil
        eqHandle.window.close()
    }

    /// Close the hosted main window, if any. Idempotent (see `closePlaylistWindow`).
    private func closeMainWindow() {
        guard let mainHandle else { return }
        self.mainHandle = nil
        mainHandle.window.close()
    }

    /// Close EVERY hosted classic window (the whole cluster). Used on app teardown
    /// and before a re-skin so a hosted window never outlives the session that
    /// drives it. The loaded skin is intentionally KEPT (a re-skin replaces it; a
    /// teardown does not need to clear it).
    func closeAllWindows() {
        closeMainWindow()
        closePlaylistWindow()
        closeEQWindow()
    }

    // MARK: Failure UI

    /// Show a brief modal alert that the chosen skin could not be opened. Kept
    /// generic and brand-free; the underlying error (if any) is appended as
    /// informative text for the curious.
    private func presentLoadFailure(_ error: Error?) {
        let alert = NSAlert()
        alert.messageText = "Could not open this skin."
        alert.informativeText = error.map { "\($0.localizedDescription)" }
            ?? "The file is not a usable skin archive."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
