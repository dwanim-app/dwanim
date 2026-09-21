import AppKit
import Foundation
import SwiftUI
import XCTest
import GUIFocusHarness

// MARK: - ZzGUIFocusEnvironmentSentinelTests
//
// The ONE case in the whole suite that FAILS when the GUI click environment was
// not available — and the only thing that makes a denied run reach the person
// who reads the morning mail.
//
// ## Why a failure, when every other gated case skips
// The two halves of this are in tension, and both were learned the hard way:
//
//   - Per-test: an environment problem must never be reported as a product bug.
//     On 2026-09-21 seven cases failed with EFFECT assertions ("engine.play
//     called exactly once") because no window was ever key; the mail read as
//     "the playlist and the equalizer are broken". Those cases now SKIP, loudly
//     (`GUIFocusHarness.skipMarker`), naming the missing precondition.
//
//   - Per-run: a run that skipped the entire acceptance layer must NOT read as
//     a clean morning. Measured against the real report generator's own
//     functions: a fully-denied run produces `Total 1198 / Failed 0 / Skipped
//     59 / Pass rate 100.0%`, banner ALL GREEN, no FAILED TESTS block, no
//     mention of the skip marker anywhere in `summary.txt` — and, worse, it
//     PROMOTES the coverage baseline (77.1% -> 75.2%, because 187 production
//     lines are never executed), so the next unlocked day reads "+1.9%" as if
//     someone had added tests.
//
// `summary.txt` prints failures and not skips, and `automation/` belongs to
// another session, so the only lever on this side of the fence is a FAILING
// case. Exactly one exists, this one, and its message says in its FIRST line —
// the only line the report quotes — that it is an environment problem and not a
// product bug. The reader sees one named failure instead of seven mysterious
// ones, and `RUN_FAILED=true` keeps the coverage baseline from ratcheting down.
//
// ## Why it cannot mask a regression
// It hosts NO product view. Its window is an empty `NSWindow` built here, and
// `isKeyWindow` is granted by WindowServer to the process, so nothing in
// `DwanimItUI`, `PlayerCore` or `PlaybackKit` can make this test fail — or make
// it pass.
//
// ## The name is load-bearing
// XCTest runs suites in ASCII order of their class names (observed across every
// daily log: `AVAudio…` < `AppDark…` < … < `ZipArchiveTests`). This class must
// run LAST so that denials recorded by suites that ran earlier are already in
// the ledger when it looks. `Zz…` sorts after `Zip…` because lowercase `z`
// (122) > `i` (105). `testTheSentinelSortsLastSoItSeesEveryDenial` pins that.
@MainActor
final class ZzGUIFocusEnvironmentSentinelTests: XCTestCase {

    /// The run-level canary. Fails — never skips — when this process could not
    /// obtain a key window, or when any gated harness was denied one earlier in
    /// the run.
    func testTheGUIClickEnvironmentWasAvailableToThisRun() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        addTeardownBlock { @MainActor in
            window.orderOut(nil)
            window.close()
        }

        let observation = GUIFocusHarness.establishFocus(window, harness: "ZzGUIFocusEnvironmentSentinelTests")
        let denials = GUIFocusHarness.DenialLedger.shared.entries

        if observation.windowIsKey && denials.isEmpty { return }   // the run really did click things

        XCTFail(GUIFocusHarness.environmentFailureMessage(observation: observation, denials: denials))
    }

    /// The ordering contract, enforced rather than trusted: if some future
    /// suite sorts after this one, its denials would land in the ledger too
    /// late to be reported and this sentinel would go quietly green.
    ///
    /// The class names are read from the SOURCES rather than from the ObjC
    /// runtime: `objc_copyClassList` + `class_getSuperclass` realizes every
    /// lazily-loaded class in the process and crashed the runner (SIGTRAP)
    /// when it reached one of them.
    func testTheSentinelSortsLastSoItSeesEveryDenial() throws {
        let mine = String(describing: Self.self)
        let declared = try Self.declaredTestCaseClassNames()

        XCTAssertTrue(declared.contains(mine), "the scan must find this very class; it found \(declared.count) suites")
        XCTAssertEqual(declared.filter { $0 > mine }, [],
                       "XCTest runs suites in name order; \(mine) must be the last one, or the "
                       + "denials recorded by a later suite would never reach the report")
    }

    /// Every `XCTestCase` subclass declared under `Tests/`.
    private static func declaredTestCaseClassNames() throws -> [String] {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DwanimItUITests
            .deletingLastPathComponent()   // Tests
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: testsRoot, includingPropertiesForKeys: nil),
            "cannot walk \(testsRoot.path) (unexpected checkout layout)"
        )
        let declaration = try NSRegularExpression(pattern: #"\bclass\s+(\w+)\s*:\s*XCTestCase\b"#)

        var names: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in declaration.matches(in: source, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
                names.append(String(source[nameRange]))
            }
        }
        XCTAssertGreaterThan(names.count, 50, "the scan found suspiciously few suites")
        return names
    }
}
