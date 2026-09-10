import AppKit
import Foundation
import XCTest
@testable import SkinAppKit

// MARK: - DarkAppearancePinTests
//
// The app is DELIBERATELY dark: every built-in theme (Graphite #12161a, Amber
// Deck #1a1613, Indigo Glass #14151f) is dark and there is no light theme, so a
// window that follows the SYSTEM appearance draws a light system titlebar strip
// above a dark deck when the Mac is in Light mode. `DarkAppearance.pin(on:)` is
// the production seam that stops that: it pins a dark `NSAppearance` on the
// object it is handed, which the App target calls once on `NSApp` so the
// system-drawn surfaces the app OWNS (titlebar and traffic-light well, popovers,
// context menus, panels, sheets, scroller knobs, the classic `.wsz` window
// cluster) resolve dark in both system appearances.
//
// ONE SURFACE IS OUT OF REACH, and it is asserted rather than assumed: the MENU
// BAR's own menus. A menu resolves the system appearance the moment it is
// installed as `NSApp.mainMenu`, overriding an explicit pin on the menu object
// itself — measured, and pinned by `testE1_*` below. So "menus" in this file
// means the app's CONTEXT menus (`testE2_*`), never the menu bar's.
//
// WHAT THIS TEST CAN AND CANNOT PROVE
// It pins the SEAM, not the pixels. A unit test cannot assert what the window
// server composites into the titlebar material, so the visual acceptance sweep
// (Light + Dark captures of every surface) is the evidence for the rendering.
// What IS assertable, and asserted here against REAL AppKit objects:
//   • the pin lands a dark appearance on the object (`appearance`),
//   • the object then RESOLVES dark (`effectiveAppearance` best-matches
//     `.darkAqua`, not `.aqua`) — this is the property the window server reads,
//   • the pin is INHERITED by descendants (a view inside a pinned window), which
//     is why a single app-level call covers every window the app creates,
//   • the pin is INDEPENDENT of the current system appearance — the whole point
//     of the fix, so it is asserted while the process is forced to each in turn.
//
// The App target itself has NO test target (see App/project.yml — the single
// `DwanimIt` application target, no unit-test target), so the one-line call site
// in `AppDelegate.applicationWillFinishLaunching(_:)` is not reachable from any
// test bundle by ordinary means. Keeping the LOGIC here, in the AppKit-owning
// tier, is what makes it testable at all. The CALL SITE is guarded separately by
// `AppDarkPinCallSiteTests` in this same bundle, which reads the committed App
// source and fails `swift test` if the pin is deleted or moved to a launch hook
// that runs too late — without it, the mutation that restores the shipped defect
// left the whole suite green.
@MainActor
final class DarkAppearancePinTests: XCTestCase {

    // MARK: Helpers

    /// Which of the two aqua appearances an object actually RESOLVES to. This is
    /// the question the window server asks when it picks titlebar material, so it
    /// is the meaningful assertion — `appearance` alone only says what was set.
    private func resolvedAqua(of customization: NSAppearanceCustomization) -> NSAppearance.Name? {
        customization.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    }

    /// Run `body` with the PROCESS forced to `name` as its system appearance, then
    /// restore whatever was there before. `NSApp.appearance` is the process-wide
    /// system-appearance override AppKit itself consults, so this lets the tests
    /// prove the pin wins in BOTH system appearances without touching the user's
    /// real System Settings.
    private func withSystemAppearance(_ name: NSAppearance.Name, _ body: () -> Void) {
        let saved = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = saved }
        NSApplication.shared.appearance = NSAppearance(named: name)
        body()
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
    }

    // MARK: A. The pin lands, and the object resolves dark

    /// Given a real titled `NSWindow` with NO appearance of its own,
    /// When `DarkAppearance.pin(on:)` is applied,
    /// Then the window carries a dark appearance AND resolves to `.darkAqua`.
    func testA1_pinSetsDarkAppearanceOnWindow() {
        let window = makeWindow()
        XCTAssertNil(window.appearance, "precondition: a fresh window inherits, it does not pin")

        DarkAppearance.pin(on: window)

        XCTAssertEqual(window.appearance?.name, .darkAqua)
        XCTAssertEqual(resolvedAqua(of: window), .darkAqua)
    }

    /// The pin must be INDEPENDENT of the system appearance — that is the defect.
    /// Given the process forced to LIGHT (`.aqua`), When a window is pinned,
    /// Then it still resolves `.darkAqua`; and the same holds under DARK.
    func testA2_pinWinsUnderBothSystemAppearances() {
        withSystemAppearance(.aqua) {
            let window = makeWindow()
            XCTAssertEqual(resolvedAqua(of: window), .aqua, "precondition: unpinned follows the system")
            DarkAppearance.pin(on: window)
            XCTAssertEqual(resolvedAqua(of: window), .darkAqua, "pin must beat a LIGHT system appearance")
        }
        withSystemAppearance(.darkAqua) {
            let window = makeWindow()
            DarkAppearance.pin(on: window)
            XCTAssertEqual(resolvedAqua(of: window), .darkAqua, "pin must be a no-op change under DARK")
        }
    }

    // MARK: B. Inheritance — why ONE app-level call covers every surface

    /// Given a view inside a pinned window, When the window is pinned,
    /// Then the view (which has no appearance of its own) RESOLVES dark too.
    /// This inheritance is why pinning `NSApp` once reaches every window, popover,
    /// context menu and panel the app owns instead of needing a per-window pin.
    /// (The menu bar's own menus are the documented exception — `testE1_*`.)
    func testB1_descendantViewInheritsThePin() {
        withSystemAppearance(.aqua) {
            let window = makeWindow()
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            window.contentView?.addSubview(view)
            XCTAssertEqual(resolvedAqua(of: view), .aqua, "precondition: the view follows the system")

            DarkAppearance.pin(on: window)

            XCTAssertEqual(resolvedAqua(of: view), .darkAqua)
            XCTAssertNil(view.appearance, "inheritance, not a second pin on the descendant")
        }
    }

    /// Given the APPLICATION object — the exact type the App target hands the seam
    /// at launch — When it is pinned, Then a window created AFTERWARDS with no
    /// appearance of its own resolves dark by inheritance from the app.
    ///
    /// This also pins the AppKit fact that dictates WHERE production calls the
    /// seam: a window that already existed when the app was pinned does NOT
    /// retroactively re-resolve (asserted below). That is precisely why the App
    /// target pins in `applicationWillFinishLaunching(_:)` — the earliest launch
    /// hook, before AppKit/SwiftUI has created the default window — rather than in
    /// `applicationDidFinishLaunching(_:)`, by which time the window can already
    /// exist and would keep the system's light appearance.
    func testB2_pinningTheApplicationReachesWindowsCreatedAfterIt() {
        let app = NSApplication.shared
        let saved = app.appearance
        defer { app.appearance = saved }

        app.appearance = NSAppearance(named: .aqua)   // simulate a LIGHT Mac
        let preexisting = makeWindow()
        XCTAssertEqual(resolvedAqua(of: preexisting), .aqua, "precondition: light system, light window")

        DarkAppearance.pin(on: app)

        let created = makeWindow()
        XCTAssertEqual(app.appearance?.name, .darkAqua)
        XCTAssertEqual(resolvedAqua(of: created), .darkAqua, "a window made after the pin inherits dark")
        XCTAssertEqual(
            resolvedAqua(of: preexisting), .aqua,
            "documented AppKit behaviour: an ALREADY-CREATED window keeps its resolved appearance, "
                + "so the pin must be applied before any window exists"
        )
    }

    // MARK: B'. The runtime self-check the App runs after launch

    /// `DarkAppearance.resolvesDark(_:)` is the predicate the App calls in
    /// `applicationDidFinishLaunching(_:)` to confirm the pin actually TOOK. A
    /// source-level guard can only prove the pin call is written; this predicate
    /// is what notices a pin that is present but ineffective at runtime.
    ///
    /// Given a window with no appearance of its own on a LIGHT Mac,
    /// When it is asked whether it resolves dark,
    /// Then it says NO — and says YES once pinned.
    func testB3_resolvesDarkReportsWhetherThePinTook() {
        withSystemAppearance(.aqua) {
            let window = makeWindow()
            XCTAssertFalse(
                DarkAppearance.resolvesDark(window),
                "an unpinned window on a LIGHT Mac is exactly the shipped defect — the check must catch it"
            )

            DarkAppearance.pin(on: window)

            XCTAssertTrue(DarkAppearance.resolvesDark(window))
        }
    }

    /// The check must not raise a false alarm on a Mac that is already DARK —
    /// that is where the app runs most of the time, and a self-check that cries
    /// wolf gets deleted.
    func testB4_resolvesDarkIsTrueUnderADarkSystemEvenBeforeThePin() {
        withSystemAppearance(.darkAqua) {
            let window = makeWindow()
            XCTAssertTrue(DarkAppearance.resolvesDark(window))
            DarkAppearance.pin(on: window)
            XCTAssertTrue(DarkAppearance.resolvesDark(window))
        }
    }

    /// The predicate must accept the APPLICATION object — the exact type the App
    /// hands it at launch — not just windows.
    func testB5_resolvesDarkAcceptsTheApplication() {
        let app = NSApplication.shared
        let saved = app.appearance
        defer { app.appearance = saved }

        app.appearance = NSAppearance(named: .aqua)
        XCTAssertFalse(DarkAppearance.resolvesDark(app))

        DarkAppearance.pin(on: app)

        XCTAssertTrue(DarkAppearance.resolvesDark(app))
    }

    // MARK: C. Idempotence / liveness

    /// Applying the pin twice is a no-op the second time, and an already-pinned
    /// object is not disturbed. Matters because the App calls it once at launch
    /// but AppKit may re-evaluate appearance on a LIVE system-appearance switch.
    func testC1_pinIsIdempotent() {
        let window = makeWindow()
        DarkAppearance.pin(on: window)
        let first = window.appearance
        DarkAppearance.pin(on: window)
        XCTAssertEqual(window.appearance?.name, first?.name)
        XCTAssertEqual(resolvedAqua(of: window), .darkAqua)
    }

    // MARK: D. The self-healing repair the App runs after launch
    //
    // WHY A REPAIR AND NOT AN ASSERTION. The first cut of this fix ended
    // `applicationDidFinishLaunching(_:)` with `assertionFailure` when the pin had
    // not taken. That was wrong in BOTH configurations, and it was caught the
    // honest way — by the app hard-crashing twice (EXC_BREAKPOINT out of
    // `applicationDidFinishLaunching`, on the Apple-event open path, on a LIGHT
    // Mac) during ordinary acceptance testing:
    //
    //   • Debug — it escalated a purely COSMETIC condition (a light titlebar)
    //     into a dead app plus a macOS crash-report dialog.
    //   • Release — `assertionFailure` is compiled out under `-O`, so the very
    //     same condition silently restored the ORIGINAL white-titlebar defect.
    //     The check protected the one configuration that was already survivable
    //     and did nothing at all for the shipped build.
    //
    // `repairIfNeeded(on:)` replaces it: it FIXES the condition instead of
    // reporting it, identically in Debug and Release, and returns what happened so
    // the caller can log. The tests below are the contract.

    /// Given hosts that already resolve dark (the normal launch),
    /// When the repair runs,
    /// Then it reports `.alreadyDark` and MUTATES NOTHING.
    ///
    /// The no-mutation half matters: this runs on every single launch, so the
    /// healthy path must not go around stamping appearances on windows that were
    /// fine — that would be a second, silent behaviour change riding along.
    func testD1_repairIsANoOpWhenEverythingAlreadyResolvesDark() {
        withSystemAppearance(.darkAqua) {
            let window = makeWindow()
            XCTAssertEqual(DarkAppearance.repairIfNeeded(on: [window]), .alreadyDark)
            XCTAssertNil(window.appearance, "a healthy launch must not mutate anything")
        }
    }

    /// Given a LIGHT host — the reported defect,
    /// When the repair runs,
    /// Then the host is re-pinned, now resolves dark, and `.repaired` is reported.
    func testD2_repairRepinsALightHostAndSaysSo() {
        withSystemAppearance(.aqua) {
            let window = makeWindow()
            XCTAssertFalse(DarkAppearance.resolvesDark(window), "precondition: the defect")

            XCTAssertEqual(DarkAppearance.repairIfNeeded(on: [window]), .repaired)

            XCTAssertTrue(DarkAppearance.resolvesDark(window))
        }
    }

    /// The case that actually shipped the crash: the APP resolves dark but a
    /// window created before the pin landed does not (see `testB2_*` — an
    /// already-created window never re-resolves). A check that looks only at
    /// `NSApp` calls that launch healthy; a repair that walks only `NSApp` leaves
    /// the white titlebar on screen. So the repair takes the whole host LIST and
    /// judges every one of them.
    func testD3_repairReachesAWindowThatMissedTheAppPin() {
        let app = NSApplication.shared
        let saved = app.appearance
        defer { app.appearance = saved }

        app.appearance = NSAppearance(named: .aqua)      // a LIGHT Mac
        let stranded = makeWindow()                      // …window born light…
        DarkAppearance.pin(on: app)                      // …pin lands too late for it
        XCTAssertTrue(DarkAppearance.resolvesDark(app), "precondition: the APP looks fine")
        XCTAssertFalse(DarkAppearance.resolvesDark(stranded), "precondition: the WINDOW does not")

        XCTAssertEqual(DarkAppearance.repairIfNeeded(on: [app, stranded]), .repaired)

        XCTAssertTrue(DarkAppearance.resolvesDark(stranded))
    }

    /// A host that ACCEPTS the pin and keeps resolving light must be reported as
    /// `.failed`, not silently swallowed — that is the only outcome the App logs
    /// at fault level. Not hypothetical: `NSApp.mainMenu` behaves exactly like
    /// this (`testE1_*`), which is why the enum has three cases and not two.
    func testD4_repairReportsFailureWhenAHostRefusesThePin() {
        XCTAssertEqual(DarkAppearance.repairIfNeeded(on: [UnpinnableHost()]), .failed)
    }

    /// Degenerate input must not trap — the App builds the host list from
    /// `NSApp.windows`, which is legitimately empty on some launches.
    func testD5_repairWithNoHostsIsAlreadyDark() {
        XCTAssertEqual(DarkAppearance.repairIfNeeded(on: []), .alreadyDark)
    }

    /// Models the real AppKit object that swallows an appearance pin: it stores
    /// what it is given and goes on resolving light.
    private final class UnpinnableHost: NSObject, NSAppearanceCustomization {
        var appearance: NSAppearance?
        var effectiveAppearance: NSAppearance { NSAppearance(named: .aqua)! }
    }

    // MARK: E. The documented LIMIT of the pin — the menu bar's own menus

    /// Given an `NSMenu` pinned dark while the Mac is in Light appearance,
    /// When it is installed as `NSApp.mainMenu`,
    /// Then it stops honouring the pin and resolves the SYSTEM appearance —
    /// while a menu that is NOT in the menu bar honours the pin normally.
    ///
    /// WHY THIS TEST EXISTS. The first cut of this fix claimed in four separate
    /// places that the app-level pin covers "menus". Half of that was false, and
    /// the acceptance captures proved it: the playlist right-click CONTEXT menu is
    /// dark under the pin, the "dwanim it" / "檔案" MENU-BAR menus are light on a
    /// Light Mac. This test is the executable version of the boundary, so the
    /// wrong claim cannot quietly come back. Measured directly (Light Mac):
    ///
    ///     detached NSMenu, pinned          → resolves darkAqua
    ///     …the same menu as NSApp.mainMenu → resolves aqua, pin still SET
    ///     …re-pinned after installation    → still aqua
    ///     …with NSApp pinned dark as well  → still aqua
    ///
    /// So the menu bar is OS-owned chrome: it overrides the app's pin rather than
    /// inheriting it, and there is no public API that changes that. The app
    /// deliberately does not reach for the private `_NSMenuWindow` route — this
    /// ships on the Mac App Store.
    ///
    /// The assertion is written against the CURRENT system appearance so it is
    /// meaningful on a Light test host and true on a Dark one. If a future macOS
    /// starts honouring the pin, this test fails on a Light host and tells us the
    /// documented limit — and the four call-site comments — need revisiting.
    func testE1_menuBarMenusOverrideThePinWithTheSystemAppearance() {
        let app = NSApplication.shared
        let savedMenu = app.mainMenu
        let savedAppearance = app.appearance
        defer {
            app.mainMenu = savedMenu
            app.appearance = savedAppearance
        }

        app.appearance = nil                    // read the REAL system appearance
        let system = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])

        let menu = NSMenu(title: "root")
        let item = NSMenuItem()
        menu.addItem(item)
        let submenu = NSMenu(title: "File")
        item.submenu = submenu

        DarkAppearance.pin(on: menu)
        XCTAssertEqual(resolvedAqua(of: menu), .darkAqua, "detached, an NSMenu DOES honour the pin")
        XCTAssertEqual(resolvedAqua(of: submenu), .darkAqua, "…and its submenus inherit it")

        app.mainMenu = menu
        DarkAppearance.pin(on: menu)
        DarkAppearance.pin(on: submenu)

        XCTAssertEqual(menu.appearance?.name, .darkAqua, "the pin is still SET on the menu…")
        XCTAssertEqual(
            resolvedAqua(of: menu), system,
            "…but a menu in the MENU BAR resolves the system appearance regardless — "
                + "this is the documented limit of the fix, not a bug in the pin"
        )
        XCTAssertEqual(resolvedAqua(of: submenu), system, "submenus of the main menu follow it")
    }

    /// The context menus the app puts up itself (the playlist right-click menu)
    /// are NOT in the menu bar, so they DO take the pin — the other side of the
    /// boundary, and the reason the claim is "context menus" rather than "menus".
    func testE2_aContextMenuTakesThePin() {
        withSystemAppearance(.aqua) {
            let menu = NSMenu(title: "playlist context")
            XCTAssertFalse(DarkAppearance.resolvesDark(menu), "precondition: follows the light system")

            DarkAppearance.pin(on: menu)

            XCTAssertTrue(DarkAppearance.resolvesDark(menu))
        }
    }
}
