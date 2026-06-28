import PlayerCore
import SwiftUI

// MARK: - DwanimPlayerScene

/// The full default-skin scene: the glass `DefaultPlayerView` sitting on the
/// colourful `DwanimBackdrop`, which is its BACKGROUND (the gradient fills the
/// panel edge-to-edge with ZERO surrounding margin) rather than an infinite
/// full-bleed fill. This is the single view the harness hosts in an
/// `NSHostingView`, so the backdrop and the glass live in the same SwiftUI tree
/// and the materials blur the gradient correctly.
///
/// ## Why the gradient is a BACKGROUND, not a floating ZStack layer (P2-5 redo)
/// Previously this was `ZStack { DwanimBackdrop(); DefaultPlayerView() }` where
/// `DwanimBackdrop` was a size-FLEXIBLE gradient with `.ignoresSafeArea()`. A
/// flexible gradient fills ANY frame it is given, so the ZStack had NO compact
/// intrinsic size for `.windowResizability` to hug — the window opened large with
/// the panel floating in a big empty gradient expanse.
///
/// Now the gradient is simply the `.background` of the panel (ZERO surrounding
/// margin — fix-5), so the scene's intrinsic size is exactly the panel size
/// (definite width ~580 from `DefaultPlayerView`) by the panel's content height.
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
/// default (~900×450) with the 580 panel floating inside, and `.contentSize` does
/// NOT grow it when an in-scene section expands at runtime. The fix is to MEASURE
/// the PANEL's intrinsic size here in pure SwiftUI — a `.background` `GeometryReader`
/// on the `.fixedSize()`-pinned panel (so it reads the TRUE intrinsic size, not the
/// window-filled size, which would be a circular measurement) writing a preference —
/// and REPORT it up via `onContentSizeChange`; the App layer sizes the window
/// (width AND height) to it (window-poking stays in the App's `WindowAccessor`/
/// session). The window uses `.contentMinSize` (not `.contentSize`) so that
/// App-layer resize is honoured rather than snapped back. This callback is pure
/// (`(CGSize) -> Void`): `DwanimUI` still imports only SwiftUI + `PlayerCore`.
public struct DwanimPlayerScene: View {

    private let core: PlayerCore
    private let model: PlayerViewModel
    /// App-layer "Open Audio…" action, forwarded to the gear menu in
    /// `DefaultPlayerView`. Optional so the headless harness can host the scene
    /// without an AppKit panel; the app wires it to `session.presentOpenPanel()`.
    private let onOpenAudio: (() -> Void)?
    /// App-layer "Open Skin…" action; the app wires it to
    /// `session.presentOpenSkinPanel()`.
    private let onOpenSkin: (() -> Void)?
    /// Reports the PANEL's intrinsic content SIZE (in points) whenever it changes
    /// — e.g. when the in-scene EQ or queue expands or collapses. The App layer
    /// wires this to a window content-size resize so the window grows/shrinks to
    /// hug the panel (fix-5, extended to width for the 3-up default). A pure
    /// SwiftUI closure: `DwanimUI` never touches AppKit. Optional so the headless
    /// harness can host the scene without it.
    ///
    /// Why a SIZE (not just height): a SwiftUI `Window` hosted in an `NSHostingView`
    /// reports `fittingSize == 0` (measured), so AppKit's own shrink-to-fit cannot
    /// derive the compact WIDTH either — without a saved frame the window opens at a
    /// large platform default (~900×450) with the 580 panel floating inside. So the
    /// scene measures the panel's intrinsic size in pure SwiftUI and the App layer
    /// sets the window content size to it.
    private let onContentSizeChange: ((CGSize) -> Void)?

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        onOpenAudio: (() -> Void)? = nil,
        onOpenSkin: (() -> Void)? = nil,
        onContentSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.core = core
        self.model = model
        self.onOpenAudio = onOpenAudio
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
            onOpenAudio: onOpenAudio,
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
        .background(DwanimBackdrop())
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
