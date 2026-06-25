import AppKit
import CoreGraphics
import Foundation
import SkinKit

// MARK: - RegionWindowBuilder
//
// The shared NSWindow build helper for the main-window skin path: a skin that
// declares a non-rectangular region gets a BORDERLESS, non-opaque,
// movable-by-background window whose content view layer is masked by a
// `CAShapeLayer` (the content stays opaque; only the layer is masked). A skin
// with no fillable region gets a plain titled/closable/miniaturizable window.
//
// This is the exact branch the static window path (`runWindowMode`) and the live
// interactive window duplicated. The mask layer itself is built by the caller
// (so it can size it to the scaled image and reuse it), and passed in; this
// helper only applies the window chrome + masking decision.

public enum RegionWindowBuilder {

    /// Build the main-window NSWindow for `contentView`, shaping it to a region
    /// mask when one is provided.
    ///
    /// - Parameters:
    ///   - contentRect: the window content rect (scaled pixel size).
    ///   - contentView: the content view to host (and, when masked, layer-back).
    ///   - maskLayer: the region mask layer, or `nil` for a plain titled window.
    ///   - title: the titled-window title (ignored when a mask is applied — the
    ///     borderless region window shows no title bar).
    /// - Returns: a configured, not-yet-shown `NSWindow`.
    public static func make(
        contentRect: NSRect,
        contentView: NSView,
        maskLayer: CAShapeLayer?,
        title: String
    ) -> NSWindow {
        let window: NSWindow
        if let maskLayer {
            // Shaped window: borderless + non-opaque + clear background so the
            // area outside the region's layer mask reads through as transparent.
            // The CONTENT image is unchanged (opaque); only the LAYER is masked.
            window = NSWindow(
                contentRect: contentRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            contentView.wantsLayer = true
            contentView.layer?.mask = maskLayer
        } else {
            window = NSWindow(
                contentRect: contentRect,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
        }
        window.contentView = contentView
        return window
    }
}
