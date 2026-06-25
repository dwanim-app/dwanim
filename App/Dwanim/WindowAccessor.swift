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
// ## Why this lives in the App target (not DwanimUI)
// Poking the AppKit window — capturing the `NSWindow`, later `orderOut` /
// `makeKeyAndOrderFront` to hide/show it while a classic `.wsz` skin is the
// active face — is an APP-SHELL concern. DwanimUI and PlayerCore stay PURE (no
// AppKit imports). So this representable, and the window coordination it feeds,
// live entirely in `App/Dwanim`. The default scene attaches it via
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
// DwanimUI / PlayerCore remain pure SwiftUI + PlayerCore.
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

        /// Report the window to the session, and on the FIRST sighting force the
        /// window compact (defeat frame restoration) so it opens hugging the panel.
        func handle(_ window: NSWindow, report: (NSWindow) -> Void) {
            report(window)
            guard !didForceCompact else { return }
            didForceCompact = true
            forceCompact(window)
        }

        /// Disable frame autosave/restore and, if the window is larger than its
        /// content's fitting size, shrink it to fit and re-center. Runs once.
        private func forceCompact(_ window: NSWindow) {
            // Stop macOS from restoring / persisting a stale large frame.
            window.setFrameAutosaveName("")

            guard let contentView = window.contentView else { return }
            let fitting = contentView.fittingSize
            // Only shrink — never grow past what the content wants. A zero fitting
            // size (content not laid out yet) is ignored so we never collapse it.
            guard fitting.width > 0, fitting.height > 0 else { return }
            let current = contentView.frame.size
            if current.width > fitting.width + 1 || current.height > fitting.height + 1 {
                window.setContentSize(fitting)
                window.center()
            }
        }
    }
}
