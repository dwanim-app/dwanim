import PlayerCore
import SwiftUI

// MARK: - DwanimItPlayerScene

/// The full default-skin scene: the glass `DefaultPlayerView` sitting on the
/// colourful `DwanimItBackdrop`, which is its BACKGROUND (the gradient fills the
/// panel edge-to-edge with ZERO surrounding margin) rather than an infinite
/// full-bleed fill. This is the single view the harness hosts in an
/// `NSHostingView`, so the backdrop and the glass live in the same SwiftUI tree
/// and the materials blur the gradient correctly.
///
/// ## Why the gradient is a BACKGROUND, not a floating ZStack layer (P2-5 redo)
/// Previously this was `ZStack { DwanimItBackdrop(); DefaultPlayerView() }` where
/// `DwanimItBackdrop` was a size-FLEXIBLE gradient with `.ignoresSafeArea()`. A
/// flexible gradient fills ANY frame it is given, so the ZStack had NO compact
/// intrinsic size for `.windowResizability` to hug — the window opened large with
/// the panel floating in a big empty gradient expanse.
///
/// Now the gradient is simply the `.background` of the panel (ZERO surrounding
/// margin — fix-5), so the scene's intrinsic size is exactly the panel size
/// (definite width 560 from `DefaultPlayerView`) by the panel's content height.
/// The window thus HUGS the panel edge-to-edge: no surrounding gradient strip.
/// `.fixedSize(horizontal: false, vertical: true)` pins the scene to its content
/// height so the window opens compact. The look (gold panel on the teal-indigo
/// gradient with the two soft gold glows) is preserved — with no surrounding
/// margin the gradient reads only in the four corner slivers left by the panel's
/// rounded-rect, so the glass + window read as one solid rounded window rather
/// than a panel floating in a frame.
///
/// ## Why the SIZE is REPORTED (fix-5 dynamic size)
/// A SwiftUI `Window` hosted in an `NSHostingView` does NOT expose its
/// fitting/intrinsic size to AppKit (measured: `fittingSize == 0` on EVERY layout
/// pass, `intrinsicContentSize == noIntrinsicMetric`). So AppKit cannot shrink the
/// window to hug the panel: with no saved frame it opens at a large platform
/// default (~900×450) with the 560 panel floating inside, and `.contentSize` does
/// NOT grow it when an in-scene section expands at runtime. The fix is to MEASURE
/// the PANEL's intrinsic size here in pure SwiftUI — a `.background` `GeometryReader`
/// on the `.fixedSize()`-pinned panel (so it reads the TRUE intrinsic size, not the
/// window-filled size, which would be a circular measurement) writing a preference —
/// and REPORT it up via `onContentSizeChange`; the App layer sizes the window
/// (width AND height) to it (window-poking stays in the App's `WindowAccessor`/
/// session). The window uses `.contentMinSize` (not `.contentSize`) so that
/// App-layer resize is honoured rather than snapped back. This callback is pure
/// (`(CGSize) -> Void`): `DwanimItUI` still imports only SwiftUI + `PlayerCore`.
public struct DwanimItPlayerScene: View {

    private let core: PlayerCore
    private let model: PlayerViewModel
    /// App-layer "Add Songs…" action: APPEND picked audio files to the queue. The
    /// app wires it to `session.presentAddFilesPanel()`; the gear menu hides the
    /// item when it is nil (the headless harness). Forwarded to `DefaultPlayerView`.
    private let onAddFiles: (() -> Void)?
    /// App-layer "Add Folder…" action: APPEND a folder's audio files to the queue
    /// (`session.presentAddFolderPanel()`). Same nil-hides-the-item rule as above.
    private let onAddFolder: (() -> Void)?
    /// App-layer hook: RE-PERSIST the live queue after an in-UI edit (e.g. a
    /// context-menu Remove or "Clear Queue"), wired to
    /// `session.persistCurrentPlaylist()`. Forwarded down to the playlist.
    private let onPlaylistEdited: (() -> Void)?
    /// App-layer hook: route dropped file URLs into the library (the playlist's
    /// drag-over "Add to library" overlay), wired to the SAME
    /// `session.handleDroppedURLs` the window-level drop uses. Optional so the
    /// headless harness can host the scene without it.
    private let onAddURLs: (([URL]) -> Void)?
    /// App-layer "Open Theme…" action for the Appearance popover: present a
    /// colour-theme (`.dwtheme` / `.json`; legacy `.dwskin` still opens) file panel,
    /// read the picked file's text,
    /// and hand `(text, filename)` back so the popover can load it into the
    /// `AppearanceStore`. The app wires it to `session.presentOpenAppearancePanel`;
    /// nil in the headless harness (the Open Theme… row is then disabled). Forwarded to
    /// `DefaultPlayerView`. Distinct from the menu-bar "Open Skin…" (⌘⇧O) command,
    /// which applies a classic `.wsz` bitmap skin — this loads the nine-token COLOUR
    /// theme for the default face.
    private let onOpenAppearanceFile: OpenAppearanceFileAction?
    /// App-layer "Open Skin…" action for the Appearance popover: open the classic
    /// `.wsz` skin picker — the SAME command as File ▸ Open Skin… (⌘⇧O). The app wires
    /// it to `session.presentOpenSkinPanel()`; a no-op `{}` default in the headless
    /// harness. Fire-and-forget — loading a `.wsz` swaps the whole face, so no
    /// completion is threaded back. Forwarded to `DefaultPlayerView`. Distinct from
    /// `onOpenAppearanceFile` (the nine-token COLOUR theme for the default face).
    private let onOpenSkin: () -> Void

    /// The player's theme store, INJECTED by the owner (F16). The App tier creates it
    /// wired to UserDefaults persistence (`restoring:` + `onPersist`) and owns it as
    /// `@State`, then passes the one instance down here — it is held as a plain
    /// reference and read in `body` (shared by the panel AND the backdrop), so
    /// switching the theme in the title-bar popover retints the whole scene at once
    /// and Observation still tracks it. The headless harness gets a fresh in-memory
    /// `AppearanceStore()` with no persistence via the init default, so its call site
    /// is unchanged.
    private let appearance: AppearanceStore
    /// Reports the PANEL's intrinsic content SIZE (in points) whenever it changes
    /// — e.g. when the in-scene EQ or queue expands or collapses. The App layer
    /// wires this to a window content-size resize so the window grows/shrinks to
    /// hug the panel (fix-5, extended to width for the 3-up default). A pure
    /// SwiftUI closure: `DwanimItUI` never touches AppKit. Optional so the headless
    /// harness can host the scene without it.
    ///
    /// Why a SIZE (not just height): a SwiftUI `Window` hosted in an `NSHostingView`
    /// reports `fittingSize == 0` (measured), so AppKit's own shrink-to-fit cannot
    /// derive the compact WIDTH either — without a saved frame the window opens at a
    /// large platform default (~900×450) with the 560 panel floating inside. So the
    /// scene measures the panel's intrinsic size in pure SwiftUI and the App layer
    /// sets the window content size to it.
    private let onContentSizeChange: ((CGSize) -> Void)?

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        appearance: AppearanceStore = AppearanceStore(),
        onAddFiles: (() -> Void)? = nil,
        onAddFolder: (() -> Void)? = nil,
        onPlaylistEdited: (() -> Void)? = nil,
        onAddURLs: (([URL]) -> Void)? = nil,
        onOpenAppearanceFile: OpenAppearanceFileAction? = nil,
        onOpenSkin: @escaping () -> Void = {},
        onContentSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.core = core
        self.model = model
        self.appearance = appearance
        self.onAddFiles = onAddFiles
        self.onAddFolder = onAddFolder
        self.onPlaylistEdited = onPlaylistEdited
        self.onAddURLs = onAddURLs
        self.onOpenAppearanceFile = onOpenAppearanceFile
        self.onOpenSkin = onOpenSkin
        self.onContentSizeChange = onContentSizeChange
    }

    public var body: some View {
        // The glass panel at its INTRINSIC size. `.fixedSize()` pins it to its ideal
        // (the definite `compactWidth` × the content-driven height of MAIN + EQ +
        // queue), so the `.background` GeometryReader below measures the panel's TRUE
        // intrinsic size — NOT the window-filled size. (If the reader sat on the
        // backdrop-filled scene it would echo the window's current size, a circular
        // measurement that can never shrink the oversized default window.)
        DefaultPlayerView(
            core: core,
            model: model,
            appearance: appearance,
            onAddFiles: onAddFiles,
            onAddFolder: onAddFolder,
            onPlaylistEdited: onPlaylistEdited,
            onAddURLs: onAddURLs,
            onOpenAppearanceFile: onOpenAppearanceFile,
            onOpenSkin: onOpenSkin
        )
        .fixedSize()
        // Measure the panel's intrinsic size (pure SwiftUI) and report it up so the
        // App layer can size the window to hug it (and re-size it as the EQ / queue
        // collapse/expand) — SwiftUI's own window resizability + AppKit `fittingSize`
        // do not track this reliably for an NSHostingView (see the type doc / the
        // `onContentSizeChange` note). The reader is a `.background` of the pinned
        // panel so it reads the SAME laid-out intrinsic size without affecting layout.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ScenePanelSizeKey.self, value: proxy.size)
            }
        )
        // ZERO surrounding margin (fix-5): the gradient fills the scene BEHIND the
        // pinned panel (and the four corner slivers left by its rounded-rect), so the
        // window reads as one solid rounded window. `.frame(maxWidth/Height: .infinity)`
        // lets the backdrop fill whatever the window becomes; the panel stays pinned
        // at its intrinsic size on top, top-leading so the window hugs it once sized.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DwanimItBackdrop(theme: appearance.current))
        .onPreferenceChange(ScenePanelSizeKey.self) { size in
            guard let onContentSizeChange, size.width > 0, size.height > 0 else { return }
            onContentSizeChange(size)
        }
    }
}

// MARK: - ScenePanelSizeKey

/// Carries the glass panel's measured intrinsic size up to `onPreferenceChange`.
/// A zero size (`width`/`height == 0`) is treated as "not yet measured" and never
/// reported.
private struct ScenePanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}
