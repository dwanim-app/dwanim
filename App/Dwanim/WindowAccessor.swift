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
struct WindowAccessor: NSViewRepresentable {

    /// Invoked on the main actor with the enclosing `NSWindow` once the accessor
    /// view has settled into the window hierarchy. The App's session stores it as
    /// a weak `defaultWindow` so the classic-skin presenter can hide / restore the
    /// default face.
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Defer until the view is in the window hierarchy (see the note above).
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Re-report on updates too: if the first read happened before the view was
        // attached (window was nil), a later update catches it. Capturing the same
        // window again is harmless — the session just re-stores the same reference.
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                onWindow(window)
            }
        }
    }
}
