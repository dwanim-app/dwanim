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
    /// Region skins keep `isMovableByWindowBackground` (today's drag-anywhere
    /// behavior — the region shape usually swallows the title-bar strip, so
    /// background drag is the reliable handle there). The rectangular window
    /// relies on the explicit title-bar drag gate wired by the controller
    /// instead, so its sliders / posbar can never fight a window move.
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
            window.isMovableByWindowBackground = true
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
