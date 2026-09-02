import AppKit
import CoreGraphics
import Foundation
import SkinKit

// MARK: - RegionWindowBuilder
//
// The shared NSWindow build helper for the main-window skin path. The classic
// main window is ALWAYS chromeless — a borderless `ChromelessSkinWindow` (no OS
// title bar; the skin's own title-bar strip carries the drag handle and the
// minimize / close buttons). A skin that declares a non-rectangular region
// ADDITIONALLY gets the non-opaque + clear-background + layer-mask treatment so
// the area outside the region reads through as transparent (the content stays
// opaque; only the layer is masked). A skin with no fillable region stays a
// plain OPAQUE borderless rectangle (cheap opaque backing, no mask).
//
// `.miniaturizable` is included in the borderless mask: it adds NO visible
// chrome without `.titled`, but `NSWindow.miniaturize(_:)` is a documented no-op
// without it — and the skin's minimize button routes there.
//
// The mask layer itself is built by the caller (so it can size it to the scaled
// image and reuse it), and passed in; this helper only applies the window
// construction + masking decision.

public enum RegionWindowBuilder {

    /// Build the main-window NSWindow for `contentView`, shaping it to a region
    /// mask when one is provided.
    ///
    /// - Parameters:
    ///   - contentRect: the window content rect (scaled pixel size).
    ///   - contentView: the content view to host (and, when masked, layer-back).
    ///   - maskLayer: the region mask layer, or `nil` for a plain opaque
    ///     borderless window.
    ///   - title: the window's title. Invisible on a borderless window, but kept
    ///     set for accessibility / Mission Control labels.
    /// - Returns: a configured, not-yet-shown `NSWindow`.
    ///
    /// DRAG: BOTH shapes now drag ONLY from the skin's title-bar strip (the
    /// controller's title-bar gate) — NOT from the whole background. The shaped
    /// window used to set `isMovableByWindowBackground`, which let a press-drag in a
    /// TRANSPARENT CUT-OUT move the window; that is removed here so the controller
    /// can confine a shaped window's drag to the title bar (unshaped windows already
    /// dragged only from the title bar, so their behaviour is unchanged).
    ///
    /// SHADOW: a shaped window sets `hasShadow = false` (owner's decision) — a
    /// layer-masked window otherwise casts the RECTANGULAR window shadow around its
    /// transparent cut-outs (`invalidateShadow` does not fix this in layer-backed
    /// mode). The unshaped window keeps the default shadow.
    ///
    /// `@MainActor`: it builds and configures `NSWindow` / `NSView` (main-actor
    /// AppKit). It always ran on the main thread; the annotation makes the AppKit
    /// touches provable rather than relying on the convention.
    @MainActor
    public static func make(
        contentRect: NSRect,
        contentView: NSView,
        maskLayer: CAShapeLayer?,
        title: String
    ) -> NSWindow {
        // Chromeless for BOTH shapes: the skin art is the window chrome. The
        // subclass keeps the borderless window key/main-capable.
        let window = ChromelessSkinWindow(
            contentRect: contentRect,
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        if let maskLayer {
            // Shaped window: non-opaque + clear background so the area outside
            // the region's layer mask reads through as transparent. The CONTENT
            // image is unchanged (opaque); only the LAYER is masked.
            window.isOpaque = false
            window.backgroundColor = .clear
            // No rectangular drop shadow around the transparent cut-outs.
            window.hasShadow = false
            // Rasterize the mask at the window's DEVICE resolution — the actual
            // backing scale, known only now that the window exists — so the
            // pixel-grid-aligned rects stay crisp (no upscaling of a point-
            // resolution mask). A finite, positive scale only (guards a degenerate
            // value from an odd display configuration).
            let backingScale = window.backingScaleFactor
            maskLayer.contentsScale = (backingScale.isFinite && backingScale > 0) ? backingScale : 1
            contentView.wantsLayer = true
            contentView.layer?.mask = maskLayer
        }
        // Invisible on a borderless window, but keeps Mission Control /
        // accessibility labels meaningful.
        window.title = title
        window.contentView = contentView
        return window
    }
}
