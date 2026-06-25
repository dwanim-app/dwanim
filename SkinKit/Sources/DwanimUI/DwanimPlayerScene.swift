import PlayerCore
import SwiftUI

// MARK: - DwanimPlayerScene

/// The full default-skin scene: the glass `DefaultPlayerView` sitting on the
/// colourful `DwanimBackdrop`, which is BOUNDED to the panel (a small gradient
/// margin around the glass) rather than an infinite full-bleed fill. This is the
/// single view the harness hosts in an `NSHostingView`, so the backdrop and the
/// glass live in the same SwiftUI tree and the materials blur the gradient
/// correctly.
///
/// ## Why the gradient is a BACKGROUND, not a floating ZStack layer (P2-5 redo)
/// Previously this was `ZStack { DwanimBackdrop(); DefaultPlayerView() }` where
/// `DwanimBackdrop` was a size-FLEXIBLE gradient with `.ignoresSafeArea()`. A
/// flexible gradient fills ANY frame it is given, so the ZStack had NO compact
/// intrinsic size for `.windowResizability(.contentSize)` to hug — the window
/// opened large with the panel floating in a big empty gradient expanse.
///
/// Now the gradient is the `.background` of the panel plus a modest
/// `Self.gradientMargin` of padding, so the scene's intrinsic size is the panel
/// size (idealWidth ~580 from `DefaultPlayerView`) by the panel's collapsed
/// content height, plus that margin. `.fixedSize(horizontal: false, vertical:
/// true)` pins the scene to its content height so the window opens compact and
/// hugs the panel. The look (gold panel on the teal-indigo gradient with the two
/// soft gold glows) is preserved — just bounded to the window.
///
/// Keeping the composition here (rather than in the AppKit harness) means the
/// harness only needs to know one public entry point, and the
/// backdrop-behind-glass relationship stays defined in `DwanimUI`.
public struct DwanimPlayerScene: View {

    /// The gradient margin painted AROUND the glass panel, so the colourful
    /// backdrop reads as a small frame rather than a large empty expanse. Modest
    /// on purpose: enough for the gold glows to register at the corners, not so
    /// much that the window opens large again.
    private static let gradientMargin: CGFloat = 18

    private let core: PlayerCore
    private let model: PlayerViewModel
    /// App-layer "Open Audio…" action, forwarded to the gear menu in
    /// `DefaultPlayerView`. Optional so the headless harness can host the scene
    /// without an AppKit panel; the app wires it to `session.presentOpenPanel()`.
    private let onOpenAudio: (() -> Void)?
    /// App-layer "Open Skin…" action; the app wires it to
    /// `session.presentOpenSkinPanel()`.
    private let onOpenSkin: (() -> Void)?

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        onOpenAudio: (() -> Void)? = nil,
        onOpenSkin: (() -> Void)? = nil
    ) {
        self.core = core
        self.model = model
        self.onOpenAudio = onOpenAudio
        self.onOpenSkin = onOpenSkin
    }

    public var body: some View {
        DefaultPlayerView(
            core: core,
            model: model,
            onOpenAudio: onOpenAudio,
            onOpenSkin: onOpenSkin
        )
        // A small gradient margin around the glass: the backdrop reads as a frame,
        // not a big empty expanse. The panel already carries 12pt of its own outer
        // padding, so this is the extra colour beyond that.
        .padding(Self.gradientMargin)
        // The gradient as a BOUNDED background — it fills only the panel + margin,
        // giving the scene a compact intrinsic size for `.contentSize` to hug.
        .background(DwanimBackdrop())
        // Pin the scene to its content's height (the collapsed bar, or taller when
        // the queue expands) so the window opens compact and grows/shrinks with the
        // content rather than stretching to a flexible fill.
        .fixedSize(horizontal: false, vertical: true)
    }
}
