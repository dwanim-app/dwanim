import AppKit

// MARK: - DarkAppearance
//
// Pins a DARK `NSAppearance` on an AppKit object so its system-drawn chrome stops
// following the Mac's system appearance.
//
// ## Why the app needs this at all
// dwanim it is deliberately a dark product. All three built-in themes are dark
// (Graphite #12161a, Amber Deck #1a1613, Indigo Glass #14151f), the classic `.wsz`
// face is skin-drawn bitmap art, and there is NO light theme to switch to. The
// app's CONTENT is therefore unconditionally dark — but until this seam existed
// the app never declared an appearance, so every SYSTEM-drawn surface (titlebar
// material, traffic-light well, context menus, popover backgrounds, sheets,
// scroller knobs) followed the SYSTEM appearance instead. On a Mac set to Light that drew
// a pure-white 16 pt titlebar strip (measured luminance 255) directly above the
// dark deck (measured luminance ~59) — it read as a broken window.
//
// ## Why the pin goes on `NSApp`, not on each window
// `NSAppearanceCustomization` is INHERITED: an object with no appearance of its
// own resolves its ancestor's. Pinning the shared `NSApplication` once therefore
// reaches the app's own surfaces in one place — the default SwiftUI window, the
// theme popover, the app's CONTEXT menus, alerts and sheets, panels, scroller
// knobs, and the classic `.wsz` main / playlist / EQ window cluster that
// `ClassicSkinPresenter` creates later at runtime. A per-window pin would have to
// be repeated in each of those construction sites and would be silently forgotten
// by the next window someone adds.
//
// ## The one surface this CANNOT reach: the menu bar's own menus
// The menu bar is OS-owned chrome, and its menus keep following the SYSTEM
// appearance no matter what the app pins. This is measured, not assumed, and it
// is asserted by `DarkAppearancePinTests.testE1_*`. On a Light Mac:
//
//     detached NSMenu, pinned dark        → resolves darkAqua
//     …installed as `NSApp.mainMenu`      → resolves aqua, though the pin is
//                                            still SET on the menu object
//     …re-pinned after installation       → still aqua
//     …with `NSApp` pinned dark too       → still aqua
//
// So on a Light Mac the "dwanim it" / File / 檔案 menus drop down LIGHT over the
// dark deck, and there is no public API that changes it — an explicit pin on the
// `NSMenu` is overridden, and the private `_NSMenuWindow` route is not something
// a Mac App Store build may touch. The app's own right-click context menus are a
// different object and DO take the pin (`testE2_*`). Wherever this file or its
// call sites say "menus", they mean context menus; the menu bar is called out
// explicitly. Every other system-drawn surface in the acceptance list — titlebar
// and traffic lights, theme popover, open panel, sheets, scrollers, the `.wsz`
// cluster — is covered.
//
// ## Why this lives in SkinAppKit
// SkinKit's tier rules put ALL AppKit ownership in SkinAppKit: `PlayerCore` is
// pure, `DwanimItUI` is pure SwiftUI + PlayerCore with no AppKit import, and only
// SkinAppKit (and the App target) may touch AppKit. Keeping the logic here also
// makes it TESTABLE — the App target has no unit-test bundle, whereas
// `SkinAppKitTests` can exercise this against real `NSWindow` / `NSView` /
// `NSApplication` objects.
//
// ## What this does NOT do
// It does not use `NSRequiresAquaSystemAppearance` (that Info.plist key opts the
// app OUT of dark mode — the exact opposite), and it does not disable the user's
// system-appearance switching. A live Light↔Dark switch still reaches the app;
// the pin simply keeps winning, so the window stays dark either way.
public enum DarkAppearance {

    /// Pin `NSAppearance.Name.darkAqua` on `customization`, so it — and every
    /// descendant that has not pinned an appearance of its own — resolves dark
    /// regardless of the Mac's system appearance.
    ///
    /// Idempotent: applying it again replaces the pin with an equivalent one, so
    /// it is safe to call from a launch hook that may run more than once.
    ///
    /// - Parameter customization: any AppKit appearance host — in production this
    ///   is the shared `NSApplication`; `NSWindow` and `NSView` conform too, which
    ///   is what the tests use.
    public static func pin(on customization: NSAppearanceCustomization) {
        customization.appearance = NSAppearance(named: .darkAqua)
    }

    /// Whether `customization` actually RESOLVES dark right now.
    ///
    /// `pin(on:)` sets an appearance; this answers the different, load-bearing
    /// question of what the window server will read back — `effectiveAppearance`,
    /// which folds in inheritance and any later override. The two can disagree:
    /// a pin that was applied to the wrong object, replaced by a subsequent
    /// `appearance = nil`, or defeated by an OS behaviour change leaves the call
    /// site looking correct in source while the app renders the defect.
    ///
    /// It is the predicate `repairIfNeeded(on:)` judges hosts with, and the
    /// runtime half of the pin's regression guard; the source half is
    /// `AppDarkPinCallSiteTests`.
    ///
    /// - Parameter customization: the appearance host to interrogate — in
    ///   production the shared `NSApplication`.
    /// - Returns: `true` when the resolved appearance is the dark aqua family.
    public static func resolvesDark(_ customization: NSAppearanceCustomization) -> Bool {
        customization.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// What `repairIfNeeded(on:)` had to do.
    public enum Repair: Equatable {

        /// Every host already resolved dark; nothing was touched. The normal
        /// launch, and the only outcome the App expects to see.
        case alreadyDark

        /// At least one host resolved light and now resolves dark.
        case repaired

        /// At least one host resolved light, accepted the pin, and STILL resolves
        /// light. Nothing more the app can do about that one from here — the App
        /// logs it at fault level so a user report is diagnosable.
        case failed
    }

    /// Re-pin any host that is not resolving dark, and report what happened.
    ///
    /// ## Why this exists rather than a launch-time assertion
    /// The App runs this once from `applicationDidFinishLaunching(_:)`, after
    /// AppKit/SwiftUI has finished building the first window. The version this
    /// replaced called `resolvesDark(_:)` there and ended in `assertionFailure`,
    /// which was wrong twice over:
    ///
    ///   • in DEBUG it turned a purely COSMETIC condition — a light titlebar —
    ///     into a hard launch crash, which is exactly what happened: the app
    ///     trapped twice on a Light Mac during ordinary acceptance testing;
    ///   • in RELEASE `assertionFailure` is compiled out, so the same condition
    ///     silently restored the original white-titlebar defect. The check did
    ///     nothing at all for the shipped build.
    ///
    /// Repairing is strictly better in both: the shipped build heals itself, and
    /// the developer build behaves the same way instead of dying.
    ///
    /// ## Why it takes a LIST and not just `NSApp`
    /// A window that already existed when `NSApp` was pinned does not re-resolve
    /// (`DarkAppearancePinTests.testB2_*`). A launch where the app is dark but one
    /// window came up light therefore reads as perfectly healthy from `NSApp`
    /// alone — while the user is looking at the defect. So the App hands over
    /// `NSApp` AND `NSApp.windows`, and every one of them is judged.
    ///
    /// Hosts that already resolve dark are left completely untouched, so the
    /// healthy path (every launch, on every Mac) mutates nothing.
    ///
    /// - Parameter hosts: the appearance hosts to check — in production the
    ///   shared `NSApplication` followed by its windows.
    /// - Returns: `.alreadyDark`, `.repaired`, or `.failed`.
    @discardableResult
    public static func repairIfNeeded(on hosts: [NSAppearanceCustomization]) -> Repair {
        let light = hosts.filter { !resolvesDark($0) }
        guard !light.isEmpty else { return .alreadyDark }
        light.forEach(pin(on:))
        return light.allSatisfy(resolvesDark) ? .repaired : .failed
    }
}
