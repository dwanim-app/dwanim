import AppKit
import Foundation

// MARK: - SkinWindowController
//
// The reusable base for every live skin window controller. It carries the one
// piece of machinery all four harness windows duplicated verbatim: the
// NSWindowDelegate + NSApplicationDelegate TEARDOWN PAIR.
//
//   * windowWillClose  -> tearDown() -> NSApp.terminate(nil)   (harness)
//   * applicationShouldTerminateAfterLastWindowClosed -> true  (harness)
//
// `tearDown()` is the single overridable hook: the animating windows (the
// bitmap main window and the default-skin player) override it to stop their
// `RedrawLoop` (invalidate the timer + remove the tap); the static windows
// (playlist, EQ) inherit the default no-op, exactly matching their former
// `windowWillClose` that called only `NSApp.terminate`.
//
// ## Two close behaviors: harness (terminate) vs hosted (notify)
// A concrete controller is built in one of two close modes:
//
//   * `terminatesAppOnClose == true` (the DEFAULT) — the single-window CLI
//     HARNESS path, byte-for-byte the original behavior: `windowWillClose` runs
//     `tearDown()` then `NSApp.terminate(nil)`, and (when the harness installs
//     the controller as `NSApp.delegate`)
//     `applicationShouldTerminateAfterLastWindowClosed` returns `true`. Closing
//     the one window quits the process.
//
//   * `terminatesAppOnClose == false` — a HOSTED window inside a larger app
//     (the SwiftUI app hosting the classic main window). `windowWillClose` runs
//     `tearDown()` then `onClose?()` and does NOT call `NSApp.terminate`, so the
//     host's other windows (the default scene) survive. In this mode the
//     controller must NOT be installed as the app's `NSApplicationDelegate`
//     (the host owns its own delegate / SwiftUI lifecycle); the
//     `applicationShouldTerminateAfterLastWindowClosed` method still returns the
//     mode flag (`false` here) as a belt-and-suspenders guard for the
//     theoretical case where it is consulted, but the host simply never wires it
//     as the delegate.
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
// `tearDown()` (a hop-free open method), the host's `onClose` (a host-supplied
// closure), and AppKit's `NSApp.terminate`, all of which the existing
// controllers already invoked from these same callbacks.
open class SkinWindowController: NSObject, NSWindowDelegate, NSApplicationDelegate {

    /// Whether closing this window should quit the whole process. `true` (the
    /// default) is the harness behavior (terminate on close); `false` is a hosted
    /// window that only tears itself down and notifies the host.
    private let terminatesAppOnClose: Bool

    /// Optional host notification, run AFTER `tearDown()` when the window closes.
    /// Only meaningful in the hosted (`terminatesAppOnClose == false`) mode, where
    /// the host uses it to drop its retained handle. Never set in the harness.
    private let onClose: (() -> Void)?

    /// - Parameters:
    ///   - terminatesAppOnClose: `true` (default) preserves the original harness
    ///     behavior — `windowWillClose` terminates the app. `false` makes this a
    ///     hosted window that, on close, only runs `tearDown()` + `onClose` and
    ///     leaves the app running.
    ///   - onClose: host callback fired after teardown when closing in hosted
    ///     mode (ignored — and expected `nil` — in the harness mode).
    public init(terminatesAppOnClose: Bool = true, onClose: (() -> Void)? = nil) {
        self.terminatesAppOnClose = terminatesAppOnClose
        self.onClose = onClose
        super.init()
    }

    // MARK: Teardown hook

    /// Per-window teardown, run when the window is closing, BEFORE the app is
    /// asked to terminate (or BEFORE `onClose` in the hosted mode). Default:
    /// nothing (the static playlist / EQ windows own no timer or tap). The
    /// animating windows override this to stop their `RedrawLoop`.
    open func tearDown() {}

    // MARK: NSWindowDelegate

    /// The window is closing — tear down (stop any timer + remove any tap) before
    /// anything else. In the harness mode (`terminatesAppOnClose == true`) then
    /// terminate so the single-window run loop exits cleanly; in the hosted mode
    /// instead notify the host (`onClose`) and leave the app running.
    public func windowWillClose(_ notification: Notification) {
        tearDown()
        if terminatesAppOnClose {
            NSApp.terminate(nil)
        } else {
            onClose?()
        }
    }

    // MARK: NSApplicationDelegate

    /// Belt-and-suspenders: in the harness mode, quit once the last window closes,
    /// so any close path that bypasses `windowWillClose` still exits the process
    /// cleanly. A hosted controller is NOT installed as the app delegate, but if
    /// it ever were, returning the mode flag (`false` for hosted) keeps the app
    /// alive on its other windows.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        terminatesAppOnClose
    }
}
