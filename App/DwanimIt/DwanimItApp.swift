import AppKit
import DwanimItUI
import os
import SkinAppKit
import SwiftUI

// MARK: - DwanimItApp
//
// The real sandboxed AUDIO player (the default-skin face). It hosts the default
// `DwanimItPlayerScene` in a SINGLE window and owns an `AudioSession` — the
// app-layer coordinator that wires the live PlayerCore + AVAudioEnginePlayer,
// the spectrum/clock feed, the security-scoped bookmark persistence, the
// "Open Audio…" panel, and launch-resolve of the last song.
//
// What lives where:
//   - The transport core, the view-model, the engine tap feed, and all of the
//     sandbox/bookmark machinery are inside `AudioSession` (this file just owns
//     and drives it).
//   - The window's content is the unchanged `DwanimItPlayerScene`, which observes
//     `session.core` (transport state + actions) and `session.model` (live clock
//     + spectrum). The in-scene transport buttons drive the core directly.
//
// ## Lifecycle ownership (single owner for the shared session)
// The default face is a single `Window` scene (NOT a `WindowGroup`), so the one
// shared `@State AudioSession` has EXACTLY ONE window lifecycle owner. A
// `WindowGroup` is a multi-window template: closing one window/tab of the group
// would tear down the shared session out from under any still-open window. With a
// single `Window` there is no second window of the group to do that.
//
// Session teardown is driven from genuine app TERMINATION, not window
// disappearance: the `AppDelegate` (installed via `@NSApplicationDelegateAdaptor`)
// calls `session.stop()` in `applicationWillTerminate(_:)`, and
// `applicationShouldTerminateAfterLastWindowClosed(_:)` returns `true` so closing
// the single main window quits the app — which then tears the session down exactly
// once. `.onAppear` still starts the feed (and resolves the last song once per
// process); `.onDisappear` no longer stops anything.
//
// The default scene stays the app's PRIMARY window. "Open Skin…" (⌘⇧O) is an
// ADDITIVE path: it hosts the classic `.wsz` MAIN window as an extra AppKit window
// driven by the same shared core (see ClassicSkinPresenter); closing that window
// does NOT quit the app. Those classic cluster windows are independent NSWindows
// that manage their own close and are torn down on real app termination (via the
// session teardown / process exit) — no window-disappear path force-closes them.
// The View menu's "Playlist" (⌘P) / "Equalizer" (⌘G) toggles show/hide the two
// other classic windows of the loaded-skin cluster (when no skin is loaded yet
// they fall back to presenting "Open Skin…", since a playlist / EQ face only exists
// for a loaded skin). NO brand words appear anywhere in the UI text.
@main
struct DwanimItApp: App {

    /// The single audio session for the app's lifetime. `@State` so the one
    /// instance (core + engine + feed + scopes) lives as long as the app does.
    @State private var session = AudioSession()

    /// The player's theme store (F16), OWNED here (as App `@State`, like `session`)
    /// so the chosen appearance persists across launches. Built wired to a
    /// UserDefaults-backed `AppearancePersistenceStore`: `restoring:` re-applies the
    /// last selection at launch (nil / corrupt ⇒ Graphite default) and `onPersist`
    /// writes every later change back. The one instance is passed DOWN into
    /// `DwanimItPlayerScene` → `DefaultPlayerView` (held as a plain reference, read in
    /// `body`; Observation still tracks it). Previously scene-private `@State`, so the
    /// selection was lost on relaunch.
    @State private var appearance = DwanimItApp.makeAppearanceStore()

    /// The AppKit delegate that drives session teardown from genuine app
    /// termination (NOT window disappearance) and quits the app when the single
    /// main window closes. SwiftUI owns this instance for the app's lifetime.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Build the persisting `AppearanceStore` (F16): create the UserDefaults-backed
    /// `AppearancePersistenceStore`, restore the last-saved selection from it, and
    /// wire `onPersist` to write future changes back. The persistence store is
    /// captured by the `onPersist` closure, so it lives as long as the returned
    /// `AppearanceStore` does. `@MainActor` because both stores are main-actor types
    /// (mirrors the `AudioSession()` `@State` default, which runs on the same actor).
    @MainActor
    private static func makeAppearanceStore() -> AppearanceStore {
        let persistence = AppearancePersistenceStore()
        return AppearanceStore(
            restoring: persistence.load(),
            onPersist: { persistence.save($0) }
        )
    }

    var body: some Scene {
        // SINGLE Window (not WindowGroup): one lifecycle owner for the shared
        // session. `Window` is macOS 13+ — fine for the 14.0 floor.
        Window("dwanim it", id: "main") {
            DwanimItPlayerScene(
                core: session.core,
                model: session.model,
                // F16: the App-owned, UserDefaults-persisting theme store (see the
                // `appearance` @State above) — passed down so the selection survives
                // relaunch. The Appearance popover still calls `store.load` in the
                // Open Theme… panel completion; the store is now this App-owned
                // instance, so a load both retints the deck AND persists.
                appearance: appearance,
                // The playlist context menu's "Add Songs…" / "Add Folder…" APPEND to
                // the queue (never replace) and "Clear Queue" empties it — all routing
                // to the same session calls the File / Skin menus use, then re-persisting
                // the live queue. Plumbed as closures so DwanimItUI never imports AppKit.
                // (Open Audio ⌘O / Open Skin ⌘⇧O stay MENU-BAR commands below.)
                onAddFiles: { session.presentAddFilesPanel() },
                onAddFolder: { session.presentAddFolderPanel() },
                onPlaylistEdited: { session.persistCurrentPlaylist() },
                // The playlist's drag-over "Add to library" overlay routes dropped
                // file URLs through the SAME session handler the window-level drop
                // uses (a `.wsz` applies as a skin, audio files load) — so a drop on
                // the playlist behaves identically to a drop anywhere else.
                onAddURLs: { session.handleDroppedURLs($0) },
                // The Appearance popover's "Open Theme…" row presents a colour-theme
                // (.dwtheme / .json; legacy .dwskin still opens) file panel through the
                // session (App owns the panel;
                // DwanimItUI stays AppKit-free), reads the picked file's text, and
                // hands (text, filename) to the completion the popover supplied — which
                // parses + applies it via the AppearanceStore. Distinct from the
                // menu-bar "Open Skin…" (⌘⇧O) command, which applies a classic .wsz
                // bitmap skin.
                onOpenAppearanceFile: { completion in session.presentOpenAppearancePanel(completion) },
                // The Appearance popover's "Open Skin…" row (directly below "Open
                // Theme…") opens the classic `.wsz` skin picker — the SAME session
                // call the File ▸ Open Skin… (⌘⇧O) menu command uses (one source of
                // truth; the panel/AppKit logic stays App-side, DwanimItUI stays
                // pure). Fire-and-forget: loading a `.wsz` swaps the whole face, so no
                // completion is threaded back. Distinct from onOpenAppearanceFile
                // above, which loads a nine-token COLOUR theme for the default face.
                onOpenSkin: { session.presentOpenSkinPanel() },
                // F7: the empty state's "Play Sample" appends the bundled sample and
                // plays it. Nil (button hidden) when the resource does not ship.
                onPlaySample: session.canPlaySample ? { session.playSample() } : nil,
                // fix-5 dynamic size: the scene measures its panel's intrinsic SIZE
                // (pure SwiftUI) and reports it here whenever it changes (first
                // layout + EQ/queue expand/collapse). The session resizes the
                // captured default window to that size — a SwiftUI `Window` reports
                // `fittingSize == 0`, so it opens at a large platform default and the
                // App layer must size it (width AND height) to hug the panel. The
                // window-poking stays App-side; DwanimItUI stays pure.
                onContentSizeChange: { size in session.setDefaultContentSize(size) }
            )
                // Compact resize floor only. Under `.windowResizability(.contentMinSize)`
                // the App-layer content-SIZE report (`onContentSizeChange` ->
                // `session.setDefaultContentSize`) drives the opening size (the panel's
                // intrinsic `compactWidth` 560 × its content height) — this frame just
                // sets how small the user can drag it. No max: expanding the in-scene
                // EQ / queue grows the window (App-layer resize); collapsing shrinks it
                // back.
                .frame(minWidth: 440, minHeight: 120)
                // File-URL DROP onto the default scene window: hand the dropped URLs
                // to the session's one drop handler (the same one every hosted
                // classic window routes to). The handler classifies them — a `.wsz`
                // applies as a skin, audio files play (multiple become the playlist),
                // a mix does both, unsupported types are ignored — minting +
                // persisting a security-scoped bookmark per file exactly as the open
                // panels do (a drop grants sandbox access just like a panel pick).
                // Filter to file URLs only (matching the AppKit ScaledImageView
                // path's `urlReadingFileURLsOnly: true`): a dragged web link is not a
                // file and must be rejected. Return `true` only when at least one file
                // URL survives the filter, so the acceptance value is honest; a
                // non-file / empty drop returns `false` and never reaches the handler.
                .dropDestination(for: URL.self) { urls, _ in
                    let files = urls.filter(\.isFileURL)
                    guard !files.isEmpty else { return false }
                    session.handleDroppedURLs(files)
                    return true
                }
                // Start the feed + launch-resolve (once per process) when the window
                // appears, and hand the delegate the session so it can tear down at
                // real termination. We do NOT stop the session on `.onDisappear`:
                // teardown is driven from `applicationWillTerminate(_:)` so closing
                // (or SwiftUI re-creating) the window never kills the shared audio /
                // spectrum feed or resets the live playlist.
                .onAppear {
                    appDelegate.session = session
                    // Wire the "Open With" / drag-drop THEME apply: the App owns the
                    // `AppearanceStore` (DwanimItUI stays AppKit-free), so hand the
                    // session a closure that forwards a read `.dwtheme`/`.dwskin`
                    // file's (text, filename) into `AppearanceStore.load`.
                    session.onApplyTheme = { text, filename in
                        appearance.load(text: text, filename: filename)
                    }
                    session.start()
                    // Flush any files that LaunchServices delivered via
                    // `application(_:open:)` BEFORE this scene appeared (a cold
                    // `open -a "dwanim it" file…` can fire the open event before the
                    // session is captured) — now that the session + theme seam are
                    // wired, route the buffered opens.
                    appDelegate.flushPendingOpenURLs()
                }
                // P2-6 (one-face-at-a-time): capture the default scene's backing
                // NSWindow into the session at launch. A zero-size accessor view in
                // the background reports its enclosing window up to the session, which
                // stores it weakly so the classic-skin presenter can HIDE the default
                // face while a classic `.wsz` main window is shown and RESTORE it when
                // that window closes. The AppKit window-poking stays in the App target
                // (this accessor + the session), so DwanimItUI / PlayerCore stay pure.
                .background(WindowAccessor { window in
                    session.setDefaultWindow(window)
                })
        }
        // P2-5: drop the title-bar strip + title text so the glass bar is
        // full-bleed to the top. The traffic lights stay (faint, working) for
        // close/minimise/zoom — `.hiddenTitleBar` hides the chrome, not the
        // window buttons.
        .windowStyle(.hiddenTitleBar)
        // P2-5 / fix-5: the content's fitting size drives the window's MINIMUM (and
        // opening) size — the definite width on `DefaultPlayerView` (560) plus the
        // compact-bar height open the window hugging the panel. We use
        // `.contentMinSize` rather than `.contentSize` ON PURPOSE: a SwiftUI `Window`
        // hosted in an `NSHostingView` does NOT reliably grow itself when the content
        // height changes at runtime (measured: `.contentSize` pinned the window to the
        // collapsed 560-wide panel and SNAPPED BACK any App-layer resize).
        // `.contentMinSize` keeps the compact opening size as a floor while letting the
        // App layer GROW the window when the in-scene queue / EQ expands and SHRINK it
        // back when it collapses, driven by the scene's `onContentSizeChange` ->
        // `session.setDefaultContentSize` (see those). Frame restoration to a stale
        // large frame can't reappear: `WindowAccessor.forceCompact` disables the
        // autosave on first capture.
        .windowResizability(.contentMinSize)
        .commands {
            // Replace the standard "New" item with the app's open commands, so
            // File ▸ Open Audio… (⌘O) presents the audio NSOpenPanel,
            // File ▸ Open Skin… (⌘⇧O) presents the .wsz skin panel that hosts the
            // classic main window (driven by the same shared core; closing it does
            // NOT quit the app), and File ▸ Open Playlist… (⌘⌥O) presents the .m3u
            // playlist panel that REPLACES the queue (load-only; nothing auto-plays)
            // — the SAME session call the playlist window's LIST OPTS > Open List…
            // uses (one source of truth). File ▸ Save Playlist… (⌘S) writes the live
            // queue out as a `.m3u` (the same LIST OPTS > Save List… call).
            CommandGroup(replacing: .newItem) {
                Button("Open Audio…") {
                    session.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Skin…") {
                    session.presentOpenSkinPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Open Playlist…") {
                    session.presentOpenPlaylistPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])

                // Save Playlist… writes the live queue as a `.m3u` (the SAME session
                // call the playlist window's LIST OPTS > "Save List…" uses — one
                // source of truth). ⌘S is free here (this is not a document-based
                // app, so there is no standard Save item to collide with). Disabled
                // on an empty queue (saving an empty queue would write an empty m3u).
                Button("Save Playlist…") {
                    session.presentSaveListPanel()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(session.core.playlist.isEmpty)
            }

            // Add the two auxiliary-window toggles into the STANDARD View menu (the
            // one SwiftUI auto-creates for sidebar / toolbar / full-screen items),
            // rather than spawning a SECOND "View" menu. `.toolbar` is the standard
            // View-menu group, so `after: .toolbar` appends our items at the bottom
            // of that one menu — a single coherent View menu.
            //
            // The items are always enabled: with a skin loaded they toggle the
            // hosted Playlist / Equalizer windows show/hide; with no skin loaded yet
            // they fall back to presenting "Open Skin…" (the auxiliary faces only
            // exist for a loaded skin), so the items are never dead.
            CommandGroup(after: .toolbar) {
                // The classic MAIN window may be built BORDERLESS for a region skin
                // (no titlebar, no close button), so this toggle is the only host
                // affordance to close (and reopen) it without a re-skin or quit. Like
                // the others, it falls back to "Open Skin…" when no skin is loaded.
                Button("Skin Window") {
                    session.toggleMainWindow()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Playlist") {
                    session.togglePlaylistWindow()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Equalizer") {
                    session.toggleEQWindow()
                }
                .keyboardShortcut("g", modifiers: [.command])
            }

            // P2-7: a top-level "Skin" menu. Closing the classic skin's MAIN window
            // now QUITS the app (the user disliked the default face popping back), so
            // this menu is the standard-mac way to leave a classic skin WITHOUT
            // quitting: "Default View" (⌘⇧D) closes the classic cluster and restores
            // the default SwiftUI face. The cluster close is programmatic, so the
            // presenter's close→quit guard (an internal switching flag) keeps it from
            // terminating. "Open Skin…" / "Open Audio…" / "Open Playlist…" / "Save
            // Playlist…" are mirrored here for one coherent home for the skin commands
            // (same session calls the File menu uses — one source of truth). NO brand
            // words (§12).
            CommandMenu("Skin") {
                Button("Default View") {
                    session.switchToDefaultSkin()
                }
                // ⌘⇧D (not plain ⌘D): the macOS-standard ⌘D is Duplicate / "Don't
                // Save", so the Default View command takes the shifted chord to avoid
                // colliding with it. Unique across the menu bar.
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                // "Open Skin…" / "Open Audio…" / "Open Playlist…" / "Save Playlist…"
                // are mirrored here as clickable items for a coherent Skin-menu home,
                // but their accelerators (⌘⇧O / ⌘O / ⌘⌥O / ⌘S) live on the File-menu
                // items above (the conventional home) — declared there ONCE. Declaring
                // the same chord on these duplicates too would be an accelerator
                // ambiguity, so these carry NO `.keyboardShortcut`.
                Button("Open Skin…") {
                    session.presentOpenSkinPanel()
                }

                Button("Open Audio…") {
                    session.presentOpenPanel()
                }

                Button("Open Playlist…") {
                    session.presentOpenPlaylistPanel()
                }

                // Mirror of File ▸ Save Playlist… — its ⌘S accelerator lives on the
                // File-menu item above (declared ONCE), so this carries none, like
                // the other Skin-menu mirrors. Same empty-queue guard.
                Button("Save Playlist…") {
                    session.presentSaveListPanel()
                }
                .disabled(session.core.playlist.isEmpty)
            }
        }
    }
}

// MARK: - AppDelegate
//
// A minimal `NSApplicationDelegate` installed via `@NSApplicationDelegateAdaptor`
// so the app's lifecycle is driven by GENUINE termination, not window
// disappearance:
//
//   • `applicationShouldTerminateAfterLastWindowClosed(_:)` returns `true` ONLY
//     when no hosted classic window remains, so closing the single default `Window`
//     quits the app — UNLESS a classic skin / playlist / EQ window is still open, in
//     which case it returns `false` and the app keeps running on that cluster.
//   • `applicationWillTerminate(_:)` tears the shared `AudioSession` down EXACTLY
//     ONCE, when the process is actually quitting — releasing the security scope,
//     stopping the feed, and closing the hosted classic-window cluster.
//
// P2-7 note: this method governs the DEFAULT face's close. Closing the CLASSIC
// MAIN window does NOT go through here — it routes through the presenter's
// `onClose` → `NSApp.terminate(nil)` (the close→quit rule), which then drives
// `applicationWillTerminate` below. So the two faces quit by different paths but
// both end in the same single teardown.
//
// The `session` is handed in from the scene's `.onAppear` (the App owns the one
// `@State` instance; this delegate only holds a weak back-reference to drive
// teardown). Holding it weak avoids a retain cycle and is harmless: if the App's
// `@State` is gone the process is already tearing down.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The shared session to tear down at termination. Set by the scene's
    /// `.onAppear`. Weak: the App's `@State` is the real owner.
    weak var session: AudioSession?

    /// Files delivered by `application(_:open:)` BEFORE the session was captured
    /// (a cold `open -a "dwanim it" file…` / Finder "Open With" can fire the open
    /// event before the scene's `.onAppear` runs). Buffered here and flushed by
    /// `flushPendingOpenURLs()` once the session is wired, so a launch-time open is
    /// never dropped. Empty in the common warm case (the session is already set, so
    /// opens route straight through).
    private var pendingOpenURLs: [URL] = []

    /// PIN THE APP DARK (appearance fix). dwanim it is deliberately a dark
    /// product: all three built-in themes are dark (Graphite / Amber Deck /
    /// Indigo Glass), the classic `.wsz` face is skin-drawn bitmap art, and there
    /// is no light theme. Until this pin existed the app declared no appearance,
    /// so the app's CONTENT was unconditionally dark while every SYSTEM-drawn
    /// surface followed the MAC's appearance — on a Light Mac that painted a pure
    /// white 16 pt titlebar strip (measured luminance 255) straight above the
    /// dark deck (~59) and read as a broken window.
    ///
    /// WHY `willFinishLaunching` AND NOT `didFinishLaunching`: an NSWindow that
    /// ALREADY EXISTS does not re-resolve its appearance when `NSApp.appearance`
    /// changes afterwards (pinned by `DarkAppearancePinTests.testB2_*`). This hook
    /// runs before AppKit/SwiftUI has built the default `Window` scene, so every
    /// window the app ever creates inherits the pin from birth — including the
    /// classic `.wsz` main / playlist / EQ cluster the presenter opens later.
    ///
    /// WHY ON `NSApp` AND NOT ON THE WINDOW: appearance is inherited, so one
    /// app-level pin covers the system-drawn surfaces the app OWNS (titlebar and
    /// traffic-light well, the theme popover, the playlist context menu, alerts
    /// and sheets, the open panel, scroller knobs) instead of a per-window pin
    /// that the next new window would silently miss. The user's system-appearance
    /// switching is untouched — a live Light/Dark switch still reaches the app,
    /// the pin just keeps winning.
    ///
    /// WHAT IT DOES NOT COVER — THE MENU BAR. The menu bar is OS-owned chrome:
    /// its menus follow the SYSTEM appearance, so on a Light Mac the "dwanim it"
    /// / File / 檔案 menus drop down light over the dark deck. That is not a bug
    /// in this pin and it is not fixable from here — a menu stops honouring even
    /// an explicit `NSMenu.appearance` the moment it is installed as
    /// `NSApp.mainMenu` (measured; asserted by
    /// `DarkAppearancePinTests.testE1_menuBarMenusOverrideThePinWithTheSystemAppearance`),
    /// and the private `_NSMenuWindow` route is off-limits for a Mac App Store
    /// build. The app's own right-click context menus are a different object and
    /// DO take the pin (`testE2_*`).
    ///
    /// WHAT GUARDS THIS ONE LINE: the App target has no unit-test bundle, so a
    /// deletion here is invisible to `swift test` unless something reaches across
    /// the tier boundary. Two things now do —
    ///   • `AppDarkPinCallSiteTests` (SkinAppKitTests) reads this very file and
    ///     asserts the pin is called from THIS hook, so deleting or relocating
    ///     the call fails a plain `swift test`;
    ///   • `applicationDidFinishLaunching(_:)` below re-reads the resolved
    ///     appearance and REPAIRS it if the pin did not take.
    /// The pixels themselves are still evidence only a visual sweep can produce.
    func applicationWillFinishLaunching(_ notification: Notification) {
        DarkAppearance.pin(on: NSApplication.shared)
    }

    /// LAUNCH-TIME SELF-REPAIR for the pin above. `pin(on:)` sets an appearance;
    /// this asks what the window server will actually READ BACK once launch is
    /// complete and the first window exists. The two can disagree — a pin applied
    /// to the wrong object, overwritten later in launch, or landing after a window
    /// was already built leaves the call site looking right in review while the
    /// app draws the white-titlebar defect again. When that happens, this re-pins
    /// whatever came up light instead of merely complaining about it.
    ///
    /// WHY IT REPAIRS AND DOES NOT ASSERT. This hook ended in `assertionFailure`
    /// for one iteration, and that was wrong in both configurations — the app
    /// hard-crashed twice on a Light Mac during ordinary acceptance testing
    /// (EXC_BREAKPOINT out of this method on the Apple-event open path):
    ///   • DEBUG — a purely COSMETIC condition became a dead app plus a macOS
    ///     crash-report dialog. Wildly disproportionate to a light titlebar.
    ///   • RELEASE — `assertionFailure` is compiled out under `-O`, so the exact
    ///     same condition silently restored the ORIGINAL defect. The check did
    ///     nothing whatsoever for the build that ships.
    /// Repairing is better in both: the shipped build heals itself and the
    /// developer build behaves identically instead of dying. Guarded by
    /// `AppDarkPinCallSiteTests.testDidFinishLaunchingDoesNotTrapOnACosmeticCondition`.
    ///
    /// WHY THE WINDOWS ARE HANDED OVER TOO: a window that already existed when
    /// `NSApp` was pinned never re-resolves (`DarkAppearancePinTests.testB2_*`),
    /// so a launch where only the window came up light looks perfectly healthy
    /// from `NSApp` alone — and that is precisely the launch the user sees the
    /// defect on. Hosts that already resolve dark are left untouched, so the
    /// normal launch mutates nothing.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosts: [NSAppearanceCustomization] =
            [NSApplication.shared] + NSApplication.shared.windows
        // NB: `Logger` messages take an `OSLogMessage`, built from a string
        // LITERAL — a `+`-concatenated `String` does not type-check here. Hence the
        // multi-line literals with line continuations rather than concatenation.
        switch DarkAppearance.repairIfNeeded(on: hosts) {
        case .alreadyDark:
            break  // the normal launch: the pin took, nothing was touched.
        case .repaired:
            Self.appearanceLog.notice(
                """
                dwanim it came up resolving a LIGHT appearance despite the dark \
                pin in applicationWillFinishLaunching; re-pinned at didFinishLaunching.
                """
            )
        case .failed:
            Self.appearanceLog.fault(
                """
                dwanim it is resolving a LIGHT appearance and would not take the \
                dark pin. System-drawn chrome (titlebar, popovers, sheets) will \
                not match the dark deck.
                """
            )
        }
    }

    /// Subsystem log for the appearance self-repair above. Scoped to this
    /// delegate because it is the only thing in the app that logs today.
    private static let appearanceLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "tw.com.yuzhitech.dwanimit",
        category: "appearance"
    )

    /// The OS OPEN event: a file opened via Finder ▸ "Open With ▸ dwanim it", a
    /// double-click on a type we declare (see CFBundleDocumentTypes in Info.plist),
    /// or `open -a "dwanim it" file…`. All `urls` arrive in ONE call, so a
    /// multi-file open is handled together. Routes through the session's
    /// `handleOpenedURLs` (same `DropRouter` classification as a drag-drop, but an
    /// explicit open also starts the opened audio playing). If the session is not
    /// captured yet (open fired before `.onAppear`), BUFFER the URLs and let
    /// `flushPendingOpenURLs()` replay them once it is.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let session else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        session.handleOpenedURLs(urls)
    }

    /// Replay any opens buffered before the session was captured (see
    /// `pendingOpenURLs`). Called from the scene's `.onAppear` right after the
    /// session + theme seam are wired. Idempotent: clears the buffer, so repeated
    /// `.onAppear`s (SwiftUI may re-create the scene) do not re-open the same files.
    /// `@MainActor` (unlike the protocol's `application(_:open:)`, a custom method
    /// does not inherit the delegate's isolation) so it can drive the main-actor
    /// `handleOpenedURLs`; both callers (`.onAppear`) are already on the main actor.
    @MainActor
    func flushPendingOpenURLs() {
        guard let session, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        session.handleOpenedURLs(urls)
    }

    /// Closing the default SwiftUI `Window` should quit the app — but ONLY when no
    /// hosted classic window remains. If a classic skin / playlist / EQ window is
    /// still open, closing the default window must keep the app alive on that
    /// cluster, so we return `false`; once the last classic window has also closed
    /// (no classic window left), we return `true` and the app quits, tearing the
    /// session down cleanly via `applicationWillTerminate`.
    ///
    /// AppKit calls this whenever the app's window count reaches zero AND when a
    /// window close leaves a window-less SwiftUI scene; gating on
    /// `isAnyClassicWindowOpen` means: closing the LAST remaining window (default
    /// plus all classic) quits, while closing the default with a classic still up
    /// does not. ⌘Q is unaffected — it routes through `terminate(_:)` directly and
    /// never consults this method, so it always quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // No session yet (pre-`.onAppear`) means no classic window is open, so it is
        // safe to quit on the last window close.
        guard let session else { return true }
        return !session.isAnyClassicWindowOpen
    }

    /// Dock-reopen / app-reactivation guard (P2-6, one-face-at-a-time). AppKit's
    /// default reopen behaviour re-fronts a hidden window when the user clicks the
    /// Dock icon or reactivates the app — which would un-hide the default `Window`
    /// that the classic-skin presenter `orderOut`-ed, leaving BOTH faces visible at
    /// once. So while a classic window is open we return `false` (do NOT let AppKit
    /// un-hide / re-front the default window); when no classic window is open the
    /// default IS the face, so we return `true` and normal reopen proceeds.
    ///
    /// Reads the SAME `session.isAnyClassicWindowOpen` signal that drives
    /// `applicationShouldTerminateAfterLastWindowClosed`. No session yet
    /// (pre-`.onAppear`) means no classic window, so normal reopen is allowed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return !(session?.isAnyClassicWindowOpen ?? false)
    }

    /// Genuine termination: tear the shared session down exactly once (feed off,
    /// security scope released, hosted classic cluster closed). This is the ONLY
    /// teardown trigger — no window-disappear path stops the session.
    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }
}
