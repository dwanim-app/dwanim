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
/// ## Why the height is REPORTED (fix-5 dynamic height)
/// A SwiftUI `Window` hosted in an `NSHostingView` does NOT reliably expose its
/// fitting/intrinsic size to AppKit (measured: `fittingSize == 0`,
/// `intrinsicContentSize == noIntrinsicMetric`). So `.windowResizability(.content
/// Size)` pins the window to the size measured at first layout and does NOT grow
/// it when the in-scene queue expands at runtime (measured: stuck at the collapsed
/// 580×148 across a real expand). The fix is to MEASURE the scene's rendered
/// height here in pure SwiftUI (a background `GeometryReader` writing a preference)
/// and REPORT it up via `onContentHeightChange`; the App layer resizes the window
/// to that height (window-poking stays in the App's `WindowAccessor`/session). The
/// window uses `.contentMinSize` (not `.contentSize`) so that App-layer resize is
/// honoured rather than snapped back. This callback is pure (`(CGFloat) -> Void`):
/// `DwanimUI` still imports only SwiftUI + `PlayerCore`.
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
    /// Reports the scene's current rendered HEIGHT (in points) whenever it changes
    /// — e.g. when the in-scene queue expands or collapses. The App layer wires
    /// this to a window content-height resize so the window grows/shrinks with the
    /// content (fix-5). A pure SwiftUI closure: `DwanimUI` never touches AppKit.
    /// Optional so the headless harness can host the scene without it.
    private let onContentHeightChange: ((CGFloat) -> Void)?

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        onOpenAudio: (() -> Void)? = nil,
        onOpenSkin: (() -> Void)? = nil,
        onContentHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.core = core
        self.model = model
        self.onOpenAudio = onOpenAudio
        self.onOpenSkin = onOpenSkin
        self.onContentHeightChange = onContentHeightChange
    }

    public var body: some View {
        DefaultPlayerView(
            core: core,
            model: model,
            onOpenAudio: onOpenAudio,
            onOpenSkin: onOpenSkin
        )
        // ZERO surrounding margin (fix-5): the gradient is the panel's own
        // background, NOT a frame around it. The window thus hugs the panel
        // edge-to-edge — no surrounding gradient strip. The backdrop fills the
        // whole scene (behind the glass and the four corner slivers left by its
        // rounded-rect), so the gradient + soft gold glows read in those corners
        // and the window reads as one solid rounded window.
        .background(DwanimBackdrop())
        // Pin the scene to its content's height (the collapsed bar, or taller when
        // the queue expands) so the window opens compact rather than stretching to
        // a flexible fill.
        .fixedSize(horizontal: false, vertical: true)
        // Measure the scene's rendered height (pure SwiftUI) and report it up so
        // the App layer can resize the window when the queue expands/collapses —
        // SwiftUI's own window resizability does not track this reliably (see the
        // type doc). The reader sits in an overlay so it measures the SAME laid-out
        // height the window must adopt, without affecting layout.
        .overlay(
            GeometryReader { proxy in
                Color.clear.preference(key: SceneHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SceneHeightKey.self) { height in
            guard let onContentHeightChange, height > 0 else { return }
            onContentHeightChange(height)
        }
    }
}

// MARK: - SceneHeightKey

/// Carries the scene's measured rendered height up to `onPreferenceChange`. The
/// default of 0 is treated as "not yet measured" and never reported.
private struct SceneHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
