import AppKit

// MARK: - ChromelessSkinWindow
//
// The shared NSWindow subclass for every classic-skin window (main, EQ,
// playlist). All three are BORDERLESS — the skin's own title-bar art carries the
// drag handle and the window buttons — and a plain `[.borderless]` NSWindow
// refuses key/main status (`canBecomeKey`/`canBecomeMain` return `false` when
// there is no title bar). Without this override the skin windows could never
// become key: keyboard events, key-window ordering, and window-focus behavior
// would silently not work (mouse clicks still reach views in non-key windows of
// the active app, which is why buttons appear to work regardless — but that is
// not something to rely on).
//
// One primary type per file (§12): just the subclass; the per-window styleMask /
// masking decisions stay at the construction sites (`RegionWindowBuilder`,
// `showEQWindow`, `showPlaylistWindow`).

/// A borderless skin window that can still become key / main, so the chromeless
/// classic windows behave like normal focusable windows.
public final class ChromelessSkinWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}
