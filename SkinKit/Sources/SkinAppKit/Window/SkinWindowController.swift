import AppKit
import Foundation

// MARK: - SkinWindowController
//
// The reusable base for every live skin window controller. It carries the one
// piece of machinery all four harness windows duplicated verbatim: the
// NSWindowDelegate + NSApplicationDelegate TEARDOWN PAIR.
//
//   * windowWillClose  -> tearDown() -> NSApp.terminate(nil)
//   * applicationShouldTerminateAfterLastWindowClosed -> true
//
// `tearDown()` is the single overridable hook: the animating windows (the
// bitmap main window and the default-skin player) override it to stop their
// `RedrawLoop` (invalidate the timer + remove the tap); the static windows
// (playlist, EQ) inherit the default no-op, exactly matching their former
// `windowWillClose` that called only `NSApp.terminate`.
//
// A concrete window supplies ONLY its unique compose/redraw/click logic; the
// window construction itself stays in each window's setup file (the styleMask
// and chrome differ per window), and the process-lifetime hold stays a
// file-private `var` in each setup file as before.
//
// Not actor-isolated: the bitmap-window and EQ controllers are plain (no actor),
// while the default-skin and playlist controllers are `@MainActor`. NSObject's
// delegate-conformance methods are non-isolated, and the `@MainActor` subclasses
// keep their own state main-actor-isolated; the teardown methods here only call
// `tearDown()` (a hop-free open method) and AppKit's `NSApp.terminate`, both of
// which the existing controllers already invoked from these same callbacks.
open class SkinWindowController: NSObject, NSWindowDelegate, NSApplicationDelegate {

    public override init() {
        super.init()
    }

    // MARK: Teardown hook

    /// Per-window teardown, run when the window is closing, BEFORE the app is
    /// asked to terminate. Default: nothing (the static playlist / EQ windows own
    /// no timer or tap). The animating windows override this to stop their
    /// `RedrawLoop`.
    open func tearDown() {}

    // MARK: NSWindowDelegate

    /// The window is closing — tear down (stop any timer + remove any tap) before
    /// the process exits, then terminate so the run loop exits cleanly.
    public func windowWillClose(_ notification: Notification) {
        tearDown()
        NSApp.terminate(nil)
    }

    // MARK: NSApplicationDelegate

    /// Belt-and-suspenders: quit once the last window closes, so any close path
    /// that bypasses `windowWillClose` still exits the process cleanly.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
