import AppKit
import Foundation
import XCTest
@testable import SkinAppKit

// MARK: - AppDarkPinCallSiteTests
//
// WHY THIS FILE EXISTS (regression guard for the shipped appearance defect).
//
// `DarkAppearancePinTests` proves the SEAM behaves — `DarkAppearance.pin(on:)`
// lands a dark appearance, descendants inherit it, it beats a light system
// appearance. What it CANNOT reach is the one line that actually invokes the
// seam in the shipped product:
//
//     AppDelegate.applicationWillFinishLaunching(_:)
//         → DarkAppearance.pin(on: NSApplication.shared)
//
// That line lives in the App target (`App/DwanimIt/DwanimItApp.swift`), and the
// App target has NO unit-test bundle (see `App/project.yml`: a single
// `DwanimIt` application target). So the mutation "delete the pin call" used to
// be COMPLETELY INVISIBLE to the automated suite: the reported defect came back
// in full — a pure-white titlebar strip above the dark deck on a Light Mac —
// while `swift test` stayed green. A defect with no failing test is a defect
// that ships twice.
//
// This file closes that hole from the only tier that can see the file at all.
// It is a SOURCE-CONTRACT test: it reads the committed App source and asserts
// the wiring is present and in the right launch hook. That is a different kind
// of evidence from a behavioural test, and the trade is deliberate:
//
//   • It CAN fail on the exact regression that shipped (the call deleted, or
//     quietly relocated to a hook that runs too late — see below), which is the
//     whole point, and it fails during a plain `swift test` with no app launch,
//     no window server and no system-appearance change.
//   • It CANNOT prove the running app renders dark. Nothing in a unit test can:
//     the titlebar material is composited by the window server. The RUNTIME half
//     of the guard is `AppDelegate.applicationDidFinishLaunching(_:)`, which
//     calls `DarkAppearance.repairIfNeeded(on:)` — it RE-PINS anything that came
//     up light and logs, identically in Debug and Release. It used to end in
//     `assertionFailure` instead; that crashed the app twice on a Light Mac
//     during acceptance testing and did nothing whatever in Release, where the
//     assertion is compiled out. Both of those call sites are asserted below, and
//     the seam itself is behaviourally tested in `DarkAppearancePinTests`.
//   • Being textual, it is blind to a rename of the seam that keeps the call
//     spelled the same, and to a call that is present but unreachable. Those are
//     not the regression that shipped; the shipped one is covered.
//
// WHY THE HOOK IDENTITY IS ASSERTED, NOT JUST THE CALL
// `DarkAppearancePinTests.testB2_pinningTheApplicationReachesWindowsCreatedAfterIt`
// pins the AppKit fact that an ALREADY-CREATED window does not re-resolve when
// `NSApp.appearance` changes afterwards. Moving the pin from
// `applicationWillFinishLaunching` to `applicationDidFinishLaunching` therefore
// reintroduces the defect on the main window while looking harmless in review.
// So this test locates the call inside the WILL hook's body specifically.
final class AppDarkPinCallSiteTests: XCTestCase {

    // MARK: The guard

    /// Given the committed App target source,
    /// When the launch path is read,
    /// Then `applicationWillFinishLaunching(_:)` pins the shared application dark.
    ///
    /// Deleting `DarkAppearance.pin(on: NSApplication.shared)` — the mutation that
    /// restores the shipped defect — fails HERE.
    func testWillFinishLaunchingPinsTheSharedApplicationDark() throws {
        let source = try appSource()
        let body = try functionBody(named: "applicationWillFinishLaunching", in: source)

        XCTAssertTrue(
            body.contains("DarkAppearance.pin(on:"),
            """
            App/DwanimIt/DwanimItApp.swift no longer pins a dark appearance in \
            applicationWillFinishLaunching(_:). Without it the Mac's system \
            appearance drives every system-drawn surface, and on a Light Mac the \
            app draws a white titlebar strip above its unconditionally dark deck. \
            Body was:
            \(body)
            """
        )
        XCTAssertTrue(
            body.contains("NSApplication.shared") || body.contains("NSApp"),
            "the pin must target the shared APPLICATION so every window, popover, "
                + "context menu, panel and sheet inherits it — a per-window pin is "
                + "silently missed by the next window someone adds. (The MENU BAR's "
                + "own menus are outside any app pin; see DarkAppearancePinTests"
                + ".testE1_*.) Body was:\n\(body)"
        )
    }

    /// Given the committed App target source,
    /// When the post-launch hook is read,
    /// Then it REPAIRS the appearance if the pin did not take.
    ///
    /// This is the half of the guard a text scan cannot supply: it catches a pin
    /// that is present in source but ineffective at runtime (overwritten later,
    /// applied to the wrong object, or defeated by an OS behaviour change) — and,
    /// unlike the check it replaced, it fixes that condition in the SHIPPED build
    /// rather than only complaining about it in Debug.
    func testDidFinishLaunchingRepairsTheAppearanceIfThePinDidNotTake() throws {
        let source = try appSource()
        let body = try functionBody(named: "applicationDidFinishLaunching", in: source)

        XCTAssertTrue(
            body.contains("DarkAppearance.repairIfNeeded("),
            """
            App/DwanimIt/DwanimItApp.swift no longer repairs its appearance at \
            launch. That call is what turns "the pin silently stopped working" \
            into a re-pin — in Release as well as Debug — instead of the white \
            titlebar the user reported. Body was:
            \(body)
            """
        )
        XCTAssertTrue(
            body.contains("NSApplication.shared.windows") || body.contains("NSApp.windows"),
            """
            the repair must judge the WINDOWS too, not just the application. A \
            window created before the pin landed keeps its light appearance for \
            life (DarkAppearancePinTests.testB2_*), so a launch where only the \
            window is stranded looks perfectly healthy from NSApp alone — and \
            that is the launch the user sees the defect on. Body was:
            \(body)
            """
        )
    }

    /// Given the committed App target source,
    /// When the post-launch hook is read,
    /// Then it does NOT trap.
    ///
    /// WHY THIS IS A TEST AND NOT A CODE-REVIEW NOTE. This hook shipped for one
    /// iteration ending in `assertionFailure`, and it hard-crashed the Debug app
    /// twice on a Light Mac during ordinary acceptance testing (EXC_BREAKPOINT out
    /// of `applicationDidFinishLaunching`, Apple-event open path). A light
    /// titlebar is COSMETIC; killing the app at launch — with a macOS crash-report
    /// dialog in front of the user — is not a proportionate response to it, and in
    /// Release the trap is compiled out entirely, so it protected nothing where it
    /// mattered. Trapping on a cosmetic condition in a launch hook is the mistake;
    /// this is the guard that it does not come back.
    func testDidFinishLaunchingDoesNotTrapOnACosmeticCondition() throws {
        let source = try appSource()
        let body = try functionBody(named: "applicationDidFinishLaunching", in: source)

        for trap in ["assertionFailure", "preconditionFailure", "fatalError"] {
            XCTAssertFalse(
                body.contains(trap),
                """
                applicationDidFinishLaunching(_:) calls \(trap). A light titlebar \
                is a cosmetic defect: it must be REPAIRED and logged, never trapped \
                on. In Debug a trap crashes the app at launch; in Release it is \
                compiled out and the defect ships silently. Body was:
                \(body)
                """
            )
        }
    }

    /// The App target cannot call the seam at all without linking/importing the
    /// AppKit-owning tier. Cheap, but it is the other way the wiring can rot.
    func testAppTargetImportsTheAppKitTier() throws {
        let source = try appSource()
        XCTAssertTrue(
            source.contains("import SkinAppKit"),
            "App/DwanimIt/DwanimItApp.swift must import SkinAppKit to reach DarkAppearance"
        )
    }

    // MARK: - Reading the committed App source

    /// Resolve `<repo>/App/DwanimIt/DwanimItApp.swift` from this test file's own
    /// location (`<repo>/SkinKit/Tests/SkinAppKitTests/...`).
    ///
    /// Skips rather than fails when the repo layout is absent, matching
    /// `AppIconSizesTests` — the SkinKit package is buildable on its own, and a
    /// checkout without the App/ directory should not report a red suite. In the
    /// real repo the file is always there, so the mutation this guards against
    /// still fails loudly.
    private func appSource() throws -> String {
        // …/SkinKit/Tests/SkinAppKitTests/AppDarkPinCallSiteTests.swift
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SkinAppKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SkinKit
            .deletingLastPathComponent()  // repo root
        let url = repoRoot.appendingPathComponent("App/DwanimIt/DwanimItApp.swift")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: url.path),
            "App target source not found at \(url.path) (unexpected checkout layout)"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The lines of `func <name>`'s body, comments removed.
    ///
    /// Brace-counted from the declaration line until the depth returns to zero, so
    /// nested closures and `if` blocks are included and the NEXT declaration is
    /// not. Comments are stripped first for two reasons: the pin's own doc comment
    /// names `DarkAppearance` in prose (a naive whole-file `contains` would pass on
    /// the comment alone even after the call was deleted), and a commented-out call
    /// must not count as wiring.
    ///
    /// Line-based comment stripping is exact for `//` and `///` as this file uses
    /// them; it would mis-handle a `//` inside a string literal, of which the App's
    /// launch hooks contain none.
    private func functionBody(named name: String, in source: String) throws -> String {
        let lines = source.components(separatedBy: .newlines).map(strippingLineComment)
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)") }) else {
            XCTFail("App/DwanimIt/DwanimItApp.swift declares no func \(name)")
            throw CallSiteScanError.declarationNotFound(name)
        }

        var depth = 0
        var opened = false
        var body: [String] = []
        for line in lines[start...] {
            body.append(line)
            depth += line.filter { $0 == "{" }.count
            if depth > 0 { opened = true }
            depth -= line.filter { $0 == "}" }.count
            if opened && depth <= 0 { return body.joined(separator: "\n") }
        }
        XCTFail("unbalanced braces scanning func \(name)")
        throw CallSiteScanError.unbalancedBraces(name)
    }

    private func strippingLineComment(_ line: String) -> String {
        guard let marker = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<marker.lowerBound])
    }

    private enum CallSiteScanError: Error {
        case declarationNotFound(String)
        case unbalancedBraces(String)
    }
}
