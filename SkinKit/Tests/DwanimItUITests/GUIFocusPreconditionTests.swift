import AppKit
import SwiftUI
import XCTest
import GUIFocusHarness

// MARK: - GUIFocusPreconditionTests
//
// The tests OF the skip gate itself.
//
// WHY THIS FILE EXISTS
// The in-process click harnesses (CadencePlaylistDoubleClickTests,
// FirstRunAcceptanceTests, the three CadenceTransport* suites and
// RealQueueTransportClickThroughTests) can only work while this process owns a
// KEY window, which macOS grants only to an application it lets come to the
// front. On 2026-09-21 the daily 07:00 job ran behind a locked screen,
// WindowServer logged 162 × "Denying xctest the right to be in front because
// cursor securing is active", no window ever became key, and the harnesses
// reported EFFECT failures ("engine.play called exactly once") — which reads as
// "double-click is broken in the app" when the truth was "the harness never got
// a window".
//
// The fix is a gate that makes the missing precondition the FIRST and ONLY
// thing reported. The danger of any such gate is the opposite failure — a real
// regression quietly becoming a green skip, which has bitten this project
// before (see `AudioOutputDeviceProbe`'s doc comment).
//
// So the gate gets its own tests, and they pin ALL FOUR directions:
//   - no key window, this process not the front app -> SKIP, loudly;
//   - no key window WHILE this process IS the front app -> RUN (and fail): the
//     environment is not what is denying us, so it is the product's problem;
//   - key window + a dead control                   -> FAILURE, never a skip;
//   - the gate sits at the point of USE (the click), so a test that never
//     synthesizes an event can never be skipped by it.
@MainActor
final class GUIFocusPreconditionTests: XCTestCase {

    // MARK: - The verdict is a pure function, so every direction is testable

    /// The ONLY thing that may open the skip gate is the absence of a key window.
    /// Everything else about the environment may look hostile — the process
    /// reporting inactive, another app frontmost — and the harness must still
    /// RUN, so that a product failure observed through a key window is reported
    /// as a failure.
    func testVerdict_aKeyWindowAlwaysProceeds_evenWhenTheRestLooksHostile() {
        let observation = GUIFocusHarness.Observation(
            activationPolicy: "prohibited",
            processIsActive: false,
            applicationIsActive: false,
            windowIsKey: true,
            frontmostApplication: "com.apple.loginwindow",
            waited: 4.9
        )

        XCTAssertEqual(
            GUIFocusHarness.verdict(for: observation, harness: "AnyHarness"),
            .proceed,
            "a key window is the whole precondition: with one, the test must run and be allowed to fail"
        )
    }

    /// No key window AND no front: the one skippable state.
    func testVerdict_noKeyWindowAndNoFrontSkips() {
        let verdict = GUIFocusHarness.verdict(for: Self.deniedObservation, harness: "AnyHarness")

        guard case .skip = verdict else {
            return XCTFail("without a key window the harness cannot click anything, so it must skip")
        }
    }

    /// THE COUNTER-REQUIREMENT, at the level of the decision.
    ///
    /// If this process IS the active application and its window is still not
    /// key, the environment is not denying anything — something inside the
    /// process took key (a panel the product opened, a window the product
    /// closed). That is the product's business and must be REPORTED, not
    /// skipped. Measured on 2026-09-21 and again under the focus-hog repro: a
    /// genuine denial always reads `isKeyWindow=false processIsActive=false
    /// NSApp.isActive=false`, never a mixture.
    func testVerdict_noKeyWindowWhileThisProcessIsTheFrontApp_proceedsSoTheProductIsReported() {
        let observation = GUIFocusHarness.Observation(
            activationPolicy: "regular",
            processIsActive: true,
            applicationIsActive: true,
            windowIsKey: false,
            frontmostApplication: "xctest",
            waited: 5.0
        )

        XCTAssertEqual(
            GUIFocusHarness.verdict(for: observation, harness: "AnyHarness"),
            .proceed,
            "the front was granted, so a missing key window is in-process — the product's problem, not the environment's"
        )
    }

    /// A skip that reads as "fine" is the failure mode this gate must not create.
    /// The message names the harness, the precondition, the OBSERVED state, the
    /// remedy, and says in so many words that nothing was verified.
    func testSkipMessage_isLoudSpecificAndGreppable() throws {
        let verdict = GUIFocusHarness.verdict(
            for: Self.deniedObservation, harness: "CadencePlaylistDoubleClickTests"
        )
        guard case .skip(let message) = verdict else {
            return XCTFail("expected a skip for the denied observation")
        }

        XCTAssertTrue(message.hasPrefix(GUIFocusHarness.skipMarker),
                      "the marker leads the message so CI can grep and COUNT these: \(message)")
        XCTAssertEqual(GUIFocusHarness.skipMarker, "[GUI-FOCUS-SKIP]",
                       "the marker is a stable contract with the CI report — changing it is a breaking change")

        for expected in [
            "CadencePlaylistDoubleClickTests",       // which harness
            "isKeyWindow",                           // the precondition, by name
            "isKeyWindow=false",                     // the observed state
            "processIsActive=false",
            "NSApp.isActive=false",
            "frontmost=com.apple.loginwindow",
            "4.9",                                   // how long it waited
            "interactive GUI session",               // the remedy
            "unlocked",
            "NOT verified"                           // no reader may mistake this for a pass
        ] {
            XCTAssertTrue(message.contains(expected),
                          "the skip message must state '\(expected)'; it said:\n\(message)")
        }
    }

    /// The remedy names the actual cause found on 2026-09-21, so the next reader
    /// does not have to re-derive it from WindowServer logs.
    func testSkipMessage_explainsWhyMacOSDeniesTheKeyWindow() throws {
        guard case .skip(let message) = GUIFocusHarness.verdict(
            for: Self.deniedObservation, harness: "AnyHarness"
        ) else {
            return XCTFail("expected a skip")
        }
        XCTAssertTrue(message.lowercased().contains("lock"),
                      "the message points at the locked session, the real cause: \(message)")
    }

    /// Each phase says WHERE the front was lost, because "never got one" and
    /// "had one and lost it mid-click" are different diagnoses with different
    /// remedies, and the second one is the 09-21 signature that survived the
    /// first version of this gate (setUp said yes, the click landed nowhere).
    func testSkipMessage_namesThePhaseTheFrontWasLostIn() throws {
        let phrasing: [GUIFocusHarness.Phase: String] = [
            .precondition: "never got one",
            .beforeEvent: "lost the front before",
            .afterEvent: "lost the front while"
        ]
        for (phase, expected) in phrasing {
            let message = GUIFocusHarness.skipMessage(
                for: Self.deniedObservation, harness: "AnyHarness", phase: phase
            )
            XCTAssertTrue(message.hasPrefix(GUIFocusHarness.skipMarker), "\(phase) message must be greppable")
            XCTAssertTrue(message.contains(expected),
                          "the \(phase) skip must say '\(expected)'; it said:\n\(message)")
            XCTAssertTrue(message.contains("NOT verified"), "\(phase): every skip says nothing was verified")
        }
    }

    private static let deniedObservation = GUIFocusHarness.Observation(
        activationPolicy: "regular",
        processIsActive: false,
        applicationIsActive: false,
        windowIsKey: false,
        frontmostApplication: "com.apple.loginwindow",
        waited: 4.9
    )

    // MARK: - The gate sits at the point of USE, and re-observes there

    /// A denial BEFORE the event: the event is never delivered (so no effect
    /// assertion can run against a click that went nowhere) and the test skips.
    func testGuardedEvent_deniedBeforeTheEvent_neverDeliversItAndSkips() throws {
        var delivered = 0
        let ledger = GUIFocusHarness.DenialLedger()

        XCTAssertThrowsError(
            try GUIFocusHarness.guardedEvent(
                harness: "StubHarness", ledger: ledger,
                isKeyWindow: { false },
                reacquire: {},
                observe: { Self.deniedObservation },
                deliver: { delivered += 1 }
            )
        ) { error in
            guard let skip = error as? XCTSkip else {
                return XCTFail("a denied gate must throw XCTSkip, got \(error)")
            }
            XCTAssertTrue((skip.message ?? "").contains(GUIFocusHarness.skipMarker),
                          "the skip carries the loud message: \(skip.message ?? "")")
        }

        XCTAssertEqual(delivered, 0, "a click that cannot land must not be synthesized at all")
    }

    /// THE 09-21 REGRESSION, pinned. The front is there when the gate looks, and
    /// gone by the time the effect would be asserted. A one-shot setUp check
    /// called this a product failure; re-observing AFTER the event turns it back
    /// into the environment skip it always was.
    func testGuardedEvent_frontLostWhileTheEventWasInFlight_skipsInsteadOfBlamingTheProduct() throws {
        var keyWindow = true
        var delivered = 0
        let ledger = GUIFocusHarness.DenialLedger()

        XCTAssertThrowsError(
            try GUIFocusHarness.guardedEvent(
                harness: "StubHarness", ledger: ledger,
                isKeyWindow: { keyWindow },
                reacquire: {},
                observe: { Self.deniedObservation },
                deliver: {
                    delivered += 1
                    keyWindow = false          // another app takes the front mid-click
                }
            )
        ) { error in
            guard let skip = error as? XCTSkip else {
                return XCTFail("a front lost mid-click is an environment skip, got \(error)")
            }
            XCTAssertTrue((skip.message ?? "").contains("lost the front while"),
                          "the skip names the phase: \(skip.message ?? "")")
        }

        XCTAssertEqual(delivered, 1, "the event WAS delivered; what failed is the environment behind it")
        XCTAssertEqual(ledger.entries.map(\.phase), [.afterEvent], "the denial is recorded for the run's sentinel")
    }

    /// A transient loss (the previous suite's window closing, a notification) is
    /// RECOVERED, not skipped: the gate re-takes the front once and proceeds.
    /// Without this, every flake would become a hole in the acceptance layer.
    func testGuardedEvent_reacquiresTheFrontOnceBeforeGivingUp() throws {
        var keyWindow = false
        var reacquisitions = 0
        var delivered = 0
        let ledger = GUIFocusHarness.DenialLedger()

        try GUIFocusHarness.guardedEvent(
            harness: "StubHarness", ledger: ledger,
            isKeyWindow: { keyWindow },
            reacquire: { reacquisitions += 1; keyWindow = true },
            observe: { Self.deniedObservation },
            deliver: { delivered += 1 }
        )

        XCTAssertEqual(reacquisitions, 1, "the gate tries to take the front back before it gives up")
        XCTAssertEqual(delivered, 1, "…and once it has it, the click is delivered")
        XCTAssertEqual(ledger.entries, [], "a recovered transient is not a hole in the run")
    }

    /// The happy path delivers, returns the body's value, and records nothing.
    func testGuardedEvent_keyWindowThroughout_deliversAndRecordsNothing() throws {
        let ledger = GUIFocusHarness.DenialLedger()

        let result = try GUIFocusHarness.guardedEvent(
            harness: "StubHarness", ledger: ledger,
            isKeyWindow: { true },
            reacquire: { XCTFail("nothing to reacquire: the window was key all along") },
            observe: { Self.deniedObservation },
            deliver: { "delivered" }
        )

        XCTAssertEqual(result, "delivered")
        XCTAssertEqual(ledger.entries, [], "a clean click is not a denial")
    }

    /// Every denial lands in a ledger, because the run-level sentinel — not the
    /// individual skip — is what makes the morning report red.
    func testGuardedEvent_recordsWhichHarnessWasDeniedAndWhere() throws {
        let ledger = GUIFocusHarness.DenialLedger()

        for harness in ["AHarness", "BHarness"] {
            XCTAssertThrowsError(
                try GUIFocusHarness.guardedEvent(
                    harness: harness, ledger: ledger,
                    isKeyWindow: { false }, reacquire: {},
                    observe: { Self.deniedObservation }, deliver: {}
                )
            )
        }

        XCTAssertEqual(ledger.entries.map(\.harness), ["AHarness", "BHarness"])
        XCTAssertEqual(ledger.entries.map(\.phase), [.beforeEvent, .beforeEvent])
        XCTAssertTrue(ledger.entries.allSatisfy { $0.observation.contains("isKeyWindow=false") },
                      "each entry carries what was observed, so the sentinel can quote it")
    }

    // MARK: - The run-level sentinel's message (what the OWNER actually reads)

    /// The skip is loud in `swift_test.log`, which is not mailed. The mailed
    /// `summary.txt` prints a FAILED TESTS block and nothing about skips, so the
    /// sentinel's FAILURE is the only line that reaches the reader — and the
    /// FIRST line of it is all the report quotes. It therefore has to stand on
    /// its own: what happened, that it is not a product bug, and what to do.
    func testEnvironmentFailureMessage_firstLineStandsAloneInTheMailedReport() throws {
        let message = GUIFocusHarness.environmentFailureMessage(
            observation: Self.deniedObservation,
            denials: [
                GUIFocusHarness.Denial(harness: "FirstRunAcceptanceTests", phase: .beforeEvent,
                                       observation: Self.deniedObservation.summary),
                GUIFocusHarness.Denial(harness: "CadencePlaylistDoubleClickTests", phase: .afterEvent,
                                       observation: Self.deniedObservation.summary)
            ]
        )
        let firstLine = try XCTUnwrap(message.split(separator: "\n", omittingEmptySubsequences: false).first)

        XCTAssertTrue(firstLine.hasPrefix(GUIFocusHarness.environmentMarker),
                      "the mailed line leads with its own marker: \(firstLine)")
        XCTAssertNotEqual(GUIFocusHarness.environmentMarker, GUIFocusHarness.skipMarker,
                          "the run-level failure and the per-test skip are different signals")
        for expected in ["NOT a product failure", "2 ", "unlocked", "caffeinate"] {
            XCTAssertTrue(firstLine.contains(expected),
                          "the first line must state '\(expected)'; it said:\n\(firstLine)")
        }
        XCTAssertTrue(message.contains("FirstRunAcceptanceTests"),
                      "the body names every harness that was denied:\n\(message)")
    }

    /// With nothing denied and no key window of its own, the sentinel still has
    /// to say the environment was the problem — that is the 07:00 case, where
    /// the gate skipped every click test before any ledger entry could matter.
    func testEnvironmentFailureMessage_worksWithAnEmptyLedger() {
        let message = GUIFocusHarness.environmentFailureMessage(
            observation: Self.deniedObservation, denials: []
        )
        XCTAssertTrue(message.hasPrefix(GUIFocusHarness.environmentMarker))
        XCTAssertTrue(message.contains("isKeyWindow=false"), "it quotes what it saw:\n\(message)")
    }

    // MARK: - End to end: with the precondition MET, a dead control still FAILS

    /// Fidelity control for the test below: the same harness, the same click, a
    /// control that is wired — the click lands and the test PASSES. Without this,
    /// `testDeadControl…` would prove nothing (a click that never lands would
    /// also "fail as expected").
    func testLiveControl_takesTheClickAndPasses() throws {
        let probe = hostButton(live: true)

        try probe.click()

        XCTAssertEqual(probe.actions, 1, "a wired button takes the synthesized click")
    }

    /// The counter-requirement, proven rather than asserted: once the gate has
    /// let the click through (window IS key), a control that swallows it is
    /// reported as a FAILURE. `XCTExpectFailure` is strict — if the assertion
    /// below did NOT fail (i.e. the gate had somehow turned a regression into a
    /// skip or a pass), this test fails instead.
    func testDeadControl_isReportedAsAFailureNotASkip() throws {
        let probe = hostButton(live: false)   // the simulated product regression

        try probe.click()                     // gated; a denied environment skips HERE, before the claim below

        XCTExpectFailure("a key window whose control swallows the click is a product FAILURE") {
            XCTAssertEqual(probe.actions, 1, "a dead button must be reported, not skipped")
        }
    }

    // MARK: Probe plumbing (the established in-process click model, via the shared seam)

    /// A real window hosting one SwiftUI `Button` that fills it. Note what this
    /// does NOT do: it does not gate. `establishFocus` cannot throw, so hosting
    /// a window can never skip a test; only `click()` can, and only if the front
    /// is really gone.
    private func hostButton(live: Bool) -> ButtonProbe {
        let counter = ClickCounter()
        let view = VStack {
            Button("probe") { if live { counter.value += 1 } }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        addTeardownBlock { @MainActor in
            window.orderOut(nil)
            window.close()
        }

        GUIFocusHarness.establishFocus(window, harness: "GUIFocusPreconditionTests")
        GUIFocusHarness.pump(0.2)

        return ButtonProbe(window: window, counter: counter)
    }

    private final class ClickCounter {
        var value = 0
    }

    private struct ButtonProbe {
        let window: NSWindow
        let counter: ClickCounter

        var actions: Int { counter.value }

        @MainActor
        func click(file: StaticString = #filePath, line: UInt = #line) throws {
            let point = NSPoint(x: window.frame.width / 2, y: 40)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                guard let e = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                ) else { fatalError("NSEvent.mouseEvent returned nil for \(type)") }
                return e
            }
            try GUIFocusHarness.synthesize(
                in: window, harness: "GUIFocusPreconditionTests", file: file, line: line
            ) {
                NSApp.postEvent(event(.leftMouseUp), atStart: false)
                window.sendEvent(event(.leftMouseDown))
                GUIFocusHarness.pump(0.25)
            }
        }
    }

    // MARK: - Source guards: no harness may gate anywhere but the point of use

    /// Guard 1. The five silent `repeat { makeKeyAndOrderFront } while
    /// !window.isKeyWindow` loops are exactly what made 2026-09-21 unreadable:
    /// each fell through without a word when the deadline expired. Every
    /// synthesized event must instead go through the shared seam, which
    /// re-observes the front on both sides of the event.
    func testEverySynthesizedEventGoesThroughTheSharedGate() throws {
        var offenders: [String] = []

        for url in try Self.harnessSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent
            guard source.contains("window.sendEvent(") else { continue }
            if !source.contains("GUIFocusHarness.synthesize") {
                offenders.append("\(name): synthesizes events without GUIFocusHarness.synthesize")
            }
            if source.contains("while !window.isKeyWindow") {
                offenders.append("\(name): still has its own silent wait-for-key loop")
            }
            if source.contains("setActivationPolicy(") {
                offenders.append("\(name): keeps its own activation ritual instead of establishFocus")
            }
        }

        XCTAssertEqual(offenders, [],
                       "every in-process click harness must take its precondition from the shared seam")
    }

    /// Guard 2, and the fix for the second defect of 2026-09-21's first attempt:
    /// gating in `setUp` skipped EVERY test in a class, including the 22 that
    /// never click (`testColdStart_titleLineSaysNothingLoadedAndClocksShowDashes`,
    /// the repeat-pill bitmap tests, the l10n checks) — so behind the 07:00 lock
    /// a real regression in them would have been swallowed by the skip path.
    /// A `setUp` may ESTABLISH the front; it may not make the whole class
    /// conditional on getting it.
    ///
    /// Only FOCUS gating is forbidden here. `RealQueueTransportClickThroughTests`
    /// legitimately skips its whole class in `setUp` when the machine has no
    /// audio output route — a precondition that really does invalidate every
    /// one of its cases, which is exactly what the key window does not do.
    func testNoSuiteMakesItsWholeClassConditionalOnTheFront() throws {
        var offenders: [String] = []

        for url in try Self.harnessSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent
            for body in Self.setUpBodies(in: source) {
                for forbidden in [
                    "GUIFocusHarness.synthesize", "GUIFocusHarness.guardedEvent",
                    "requireFocus", "isKeyWindow"
                ] where body.contains(forbidden) {
                    offenders.append("\(name): setUp gates the whole class on the front via \(forbidden)")
                }
            }
        }

        XCTAssertEqual(offenders, [],
                       "a denied front may only skip the tests that actually click")
    }

    /// The bodies of every `setUp` overload in a source file, up to the closing
    /// brace at its own indentation.
    private static func setUpBodies(in source: String) -> [String] {
        var bodies: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            defer { index += 1 }
            guard lines[index].contains("func setUp") else { continue }
            var body: [String] = []
            var cursor = index + 1
            while cursor < lines.count, lines[cursor] != "    }" {
                body.append(lines[cursor])
                cursor += 1
            }
            bodies.append(body.joined(separator: "\n"))
        }
        return bodies
    }

    /// Every Swift source under `Tests/`, minus the seam itself and this file
    /// (which quotes all the needles verbatim and would match itself).
    private static func harnessSources() throws -> [URL] {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DwanimItUITests
            .deletingLastPathComponent()   // Tests
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: testsRoot, includingPropertiesForKeys: nil),
            "cannot walk \(testsRoot.path) (unexpected checkout layout)"
        )
        let mine = URL(fileURLWithPath: #filePath).lastPathComponent
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent != "GUIFocusPrecondition.swift" }   // the seam itself
            .filter { $0.lastPathComponent != mine }
        XCTAssertGreaterThan(files.count, 20, "the walk found suspiciously few test sources")
        return files
    }
}
