import AppKit
import SwiftUI

// MARK: - WindowAccessor
//
// A zero-size `NSViewRepresentable` whose only job is to hand the App layer the
// `NSWindow` that hosts the default SwiftUI scene. SwiftUI does not expose the
// backing `NSWindow` directly, so we attach a tiny invisible `NSView` to the
// scene content and read `view.window` once it has been added to the window's
// view hierarchy.
//
// ## Why this lives in the App target (not DwanimItUI)
// Poking the AppKit window — capturing the `NSWindow`, later `orderOut` /
// `makeKeyAndOrderFront` to hide/show it while a classic `.wsz` skin is the
// active face — is an APP-SHELL concern. DwanimItUI and PlayerCore stay PURE (no
// AppKit imports). So this representable, and the window coordination it feeds,
// live entirely in `App/DwanimIt`. The default scene attaches it via
// `.background(WindowAccessor { window in session.setDefaultWindow(window) })`,
// which keeps the only window-poking on the app side.
//
// ## Why `DispatchQueue.main.async`
// At the moment SwiftUI calls `makeNSView` / `updateNSView`, the view may not yet
// be installed in a window (`view.window` is `nil` until the view is added to the
// hierarchy). Deferring the read to the next main-loop turn lets the view settle
// into its window first, so `view.window` is populated. The callback is invoked
// only when a window is actually present — a `nil` window is simply skipped (it
// will resolve on a later `updateNSView`), so capture is robust to ordering.
//
// ## Defeating frame restoration so the default scene OPENS COMPACT (P2-5 redo)
// `.windowResizability(.contentSize)` makes the window hug the SwiftUI scene's
// fitting size, but macOS can RESTORE a previously-saved large frame (window
// state restoration) and apply it AFTER the content size is set, leaving the
// compact glass panel floating in a big empty gradient. On the FIRST capture we:
//   1. Disable the autosave/restore so a stale large frame can never win again
//      (`setFrameAutosaveName("")`).
//   2. If the window is larger than the content's fitting size, shrink it to fit
//      (`setContentSize(contentView.fittingSize)`) and re-center.
// This is done ONCE (guarded by `Coordinator.didForceCompact`) so it does not
// fight `.contentSize` on every SwiftUI update — after the one forced fit, the
// content size drives the window (it still grows when the in-scene queue expands
// and shrinks back when it collapses). This window-poking stays in the App layer;
// DwanimItUI / PlayerCore remain pure SwiftUI + PlayerCore.
struct WindowAccessor: NSViewRepresentable {

    /// Invoked on the main actor with the enclosing `NSWindow` once the accessor
    /// view has settled into the window hierarchy. The App's session stores it as
    /// a weak `defaultWindow` so the classic-skin presenter can hide / restore the
    /// default face.
    let onWindow: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Defer until the view is in the window hierarchy (see the note above).
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                context.coordinator.handle(window, report: onWindow)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Re-report on updates too: if the first read happened before the view was
        // attached (window was nil), a later update catches it. Capturing the same
        // window again is harmless — the session just re-stores the same reference,
        // and the compact-fit force runs at most once (Coordinator guard).
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                context.coordinator.handle(window, report: onWindow)
            }
        }
    }

    /// Per-representable state so the one-time compact fit fires only once even
    /// though `updateNSView` may report the same window many times.
    @MainActor
    final class Coordinator {
        /// Whether the one-time autosave-disable + shrink-to-fit has already run for
        /// the captured window. Guards against re-running on every `updateNSView`.
        private var didForceCompact = false

        /// Report the window to the session, and on the FIRST sighting disable frame
        /// autosave/restore so a stale large frame can never win again. The window's
        /// actual SIZE is driven by the scene's pure-SwiftUI content-SIZE report
        /// (`onContentSizeChange` -> `session.setDefaultContentSize`): a SwiftUI
        /// `Window` hosted in an `NSHostingView` reports `fittingSize == 0` (measured
        /// on every layout pass), so AppKit cannot shrink-to-fit on its own — the
        /// scene measures its intrinsic panel size in SwiftUI and the session applies
        /// it. This method only stops frame restoration from fighting that.
        func handle(_ window: NSWindow, report: (NSWindow) -> Void) {
            report(window)
            guard !didForceCompact else { return }
            didForceCompact = true
            // Stop macOS from restoring / persisting a stale large frame so the
            // content-size report path is the single source of truth for the size.
            window.setFrameAutosaveName("")
            // Disable full-screen for this fixed-width (560px) deck — full screen
            // leaves the compact panel stranded in a huge black field and looks
            // broken. `.fullScreenNone` removes the capability entirely: the green
            // traffic-light and the View menu's "Enter Full Screen" both stop
            // offering it. Belt-and-suspenders: strip `.fullScreen` from the style
            // mask (harmless if absent) and disable the green zoom button so it
            // can't maximize the fixed-width panel either. The window stays movable,
            // minimisable, and closable.
            var behavior = window.collectionBehavior
            behavior.remove([.fullScreenPrimary, .fullScreenAuxiliary])
            behavior.insert(.fullScreenNone)
            window.collectionBehavior = behavior
            window.styleMask.remove(.fullScreen)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            // NON-RESIZABLE by the USER: the deck is a fixed-width (560px) glass
            // panel whose height is driven PROGRAMMATICALLY by the scene's
            // content-size measurement (`onContentSizeChange` ->
            // `session.setDefaultContentSize` -> `setContentSize`/`setFrame`).
            // Letting the user drag the border stretches the deck ugly. Removing
            // `.resizable` from the style mask blocks ONLY the user's drag-to-resize
            // (and the border/corner grow handles); programmatic `setFrame` /
            // `setContentSize` still resize the window (they never consult the
            // resizable bit), so the EQ-always-visible / playlist-growth height
            // changes keep resizing the window. The window stays movable,
            // minimisable, and closable (those masks are untouched).
            window.styleMask.remove(.resizable)
        }
    }
}
