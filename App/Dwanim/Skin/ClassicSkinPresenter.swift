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
//   - The window CONSTRUCTION + the live controller live one tier down, in
//     `SkinAppKit` (`showInteractiveWindow`). This presenter just calls it with
//     `terminatesAppOnClose: false` so closing the classic window tears it down
//     and drops the handle WITHOUT quitting the app (the default scene survives).
//
// ## Shared core
// The shared `PlayerCore` (and the engine's opt-in PCM-tap / format sources) are
// injected from `AudioSession`, so the classic window and the default scene are
// two faces of ONE transport: pressing play in either drives the same playback.
//
// ## Security-scope lifetime
// The skin file is only read at OPEN time (decoded into memory once; the live
// window draws from the in-memory `Skin`, never re-reading the archive). So,
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

    /// The live classic-window handle (controller + window) while one is open, held
    /// so it is not deallocated for the window's lifetime. Dropped on close (the
    /// `onClose` callback) so reopening builds a fresh one. `nil` when no classic
    /// window is open.
    private var handle: InteractiveWindowHandle?

    /// Integer zoom for the hosted classic window. Matches the harness's default
    /// `--interactive --scale 2` so the in-app window reads at the same size as the
    /// dev path.
    private static let scale = 2

    /// The hosted classic window's title-bar text used ONLY when a skin declares
    /// no custom region (the titled-fallback path). A neutral, brand-free label —
    /// the skin filename is NOT used (filenames may carry third-party brand names).
    private static let windowTitle = "Skin"

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

    // MARK: Window hosting

    /// Load the skin at `url` (inside its security scope) and host the classic main
    /// window driven by the shared core. Replaces any window already open.
    private func openWindow(for url: URL) {
        let skin: Skin
        do {
            skin = try access.withAccess(to: url) {
                let data = try Data(contentsOf: url)
                return try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
            }
        } catch {
            // Could not read / decode the skin (vanished file, malformed archive).
            // Surface a non-fatal alert and leave any existing window untouched.
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

        // Close any window already open before building a new one, so reopening a
        // skin never stacks two classic windows on the one shared core.
        closeCurrentWindow()

        // Normalize an empty-polygon region to nil (same as the harness path).
        let region = skin.region.flatMap { $0.polygons.isEmpty ? nil : $0 }

        do {
            handle = try showInteractiveWindow(
                skin: skin,
                core: core,
                tap: tap,
                format: format,
                region: region,
                scale: ClassicSkinPresenter.scale,
                title: ClassicSkinPresenter.windowTitle,
                // HOSTED mode: closing the classic window tears it down + drops our
                // handle WITHOUT quitting the app (the default scene survives). The
                // controller is NOT installed as the app's NSApplicationDelegate.
                terminatesAppOnClose: false,
                onClose: { [weak self] in self?.handle = nil }
            )
        } catch {
            presentLoadFailure(error)
            return
        }
    }

    /// Programmatically close the currently-hosted classic window, if any. Closing
    /// the window triggers `windowWillClose` → `tearDown()` → our `onClose`, which
    /// nils the handle; we proactively nil it here too so the path is idempotent.
    func closeCurrentWindow() {
        guard let handle else { return }
        self.handle = nil
        handle.window.close()
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
