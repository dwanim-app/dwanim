import AppKit
import Carbon
import Foundation
import XCTest
import GUIFocusHarness

// MARK: - SecureEventInputProbeTests
//
// The tests OF the "who holds secure event input" diagnostic.
//
// WHY THIS FILE EXISTS
// On 2026-09-21 the unattended 07:00 run went red because WindowServer refused
// this process the front 162 times with
//
//     CPS: Denying xctest the right to be in front because cursor securing is
//     active, this request was not caused by user activity
//
// "cursor securing" is SECURE EVENT INPUT — an application-level state some
// process holds (a terminal with Secure Keyboard Entry on, a focused password
// field, a pending Keychain or authorization prompt). It is NOT display sleep,
// NOT the screen saver and NOT a screen lock: this Mac was measured with
// `displaysleep=0 sleep=0`, screensaver `idleTime=0` and `screenLock off`, and
// no `caffeinate` flag clears it.
//
// The forensic cost was the whole point: `EnableSecureEventInput` is not logged
// by default and the unified log had already rolled past the night before, so
// the archaeology session ended WITHOUT a name. The next denial must arrive
// with the holder already attached, in the morning mail, or the same session is
// paid for again.
//
// WHAT IS PINNED HERE
// The state is testable IN PROCESS — `EnableSecureEventInput()` lets this test
// become the holder — so every branch is exercised for real rather than mocked:
//   - holding it ourselves: enabled == true AND the probe names THIS pid, this
//     process's real name and bundle id;
//   - nothing holding it: a plain sentence that says so;
//   - every degradation (pid gone, key absent, registry unreadable) yields one
//     short non-empty sentence that still carries the number;
//   - the two places a human actually reads it — the gate's skip reason and the
//     sentinel's mailed failure — carry the holder line, with the existing
//     `skipMarker` grep contract intact;
//   - the probe is NOT run on the happy path.
//
// SAFETY
// Secure event input is a machine-wide state: a test that took it and did not
// give it back would lock the user out of their own keyboard events. Every
// acquisition in this file goes through `holdingSecureEventInput`, which pairs
// the enable with a `defer`-ed disable, so the release happens on a normal
// return, on a thrown error, and on a failed assertion alike. `assertUnheld`
// then re-reads the machine state after the release.
//
// THIS SUITE ESTABLISHES ITS OWN PRECONDITION
// The three cases that assert the probe names THIS process only mean anything
// while this process owns a KEY WINDOW. Measured on this Mac (four variants of
// a stand-alone holder, `scratchpad/secinput/fix/attrib*.swift`):
// `kCGSSessionSecureInputPID` names the CALLER only when the caller owned the
// front at the moment it took the hold; `NSApplication.shared` alone, an
// activation policy alone, `activate` without a window, and even a window put
// on screen with `orderFrontRegardless` but never made key were ALL attributed
// to the frontmost application (Finder) instead.
//
// The first version of this file had no `setUp` and inherited that state from
// whichever GUI suite happened to run earlier in the process, so
// `swift test --filter DwanimItUITests.SecureEventInputProbeTests` — the normal
// thing to do while iterating on this very file — failed three cases on a
// perfectly healthy Mac with no hint why. `setUp` now takes the front through
// the same `GUIFocusHarness.establishFocus` seam every other click harness
// uses, and the three cases consult `SecureEventInputProbe.selfAttributionObstacle`
// so that a machine which genuinely cannot grant a key window SKIPS with the
// mechanism spelled out rather than failing. The guard is on the INDEPENDENT
// precondition (a key window), never on "did the probe name us" — guarding on
// the answer would make the assertion unfalsifiable.
@MainActor
final class SecureEventInputProbeTests: XCTestCase {

    /// The key window this suite takes the front with — its own, not one
    /// inherited from an earlier suite.
    private var window: NSWindow!
    /// What `establishFocus` could actually achieve here. The self-attribution
    /// cases read it to decide between asserting and skipping.
    private var focus: GUIFocusHarness.Observation!

    override func setUp() async throws {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        focus = GUIFocusHarness.establishFocus(window, harness: "SecureEventInputProbeTests")
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.close()
        window = nil
        focus = nil
    }

    // MARK: - The precondition itself (pure, so both directions are pinned)

    /// With a key window, nothing stands in the way of asserting that the
    /// registry names this process.
    func testSelfAttributionObstacle_isNilWhenThisProcessOwnsAKeyWindow() {
        let keyWindow = GUIFocusHarness.Observation(
            activationPolicy: "regular", processIsActive: true, applicationIsActive: true,
            windowIsKey: true, frontmostApplication: "xctest", waited: 0.2
        )

        XCTAssertNil(SecureEventInputProbe.selfAttributionObstacle(keyWindow),
                     "a key window is the whole precondition; nothing else may gate the assertion")
    }

    /// Without one, the suite must say WHY it cannot assert — naming the
    /// attribution rule, not just shrugging.
    func testSelfAttributionObstacle_explainsTheAttributionRuleWhenThereIsNoKeyWindow() throws {
        let obstacle = try XCTUnwrap(
            SecureEventInputProbe.selfAttributionObstacle(Self.deniedObservation),
            "no key window means the registry names the FRONTMOST app, not us — that must be reported"
        )

        XCTAssertFalse(obstacle.isEmpty)
        XCTAssertTrue(obstacle.lowercased().contains("key window"), obstacle)
        XCTAssertTrue(obstacle.lowercased().contains("frontmost"),
                      "the reader has to learn the mechanism, or the skip is just noise: \(obstacle)")
        XCTAssertTrue(obstacle.contains(Self.deniedObservation.summary),
                      "the observed state travels with the reason: \(obstacle)")
    }

    /// The obstacle is a PRECONDITION check, not an answer check: it may never
    /// consult the probe's own verdict, or the three end-to-end cases could
    /// never fail.
    func testSelfAttributionObstacle_ignoresWhetherTheProbeActuallyNamedUs() {
        let activeButNotKey = GUIFocusHarness.Observation(
            activationPolicy: "regular", processIsActive: true, applicationIsActive: true,
            windowIsKey: false, frontmostApplication: "xctest", waited: 1.5
        )

        XCTAssertNotNil(SecureEventInputProbe.selfAttributionObstacle(activeButNotKey),
                        "measured: an active app WITHOUT a key window is still attributed elsewhere")
    }

    // MARK: - Detection, against the real machine state

    /// The case that would have named the 09-21 culprit: while THIS process
    /// holds secure event input, the probe must say so and must name us.
    func testProbe_whileThisProcessHoldsSecureInput_reportsEnabledAndNamesThisProcess() throws {
        try requireUnheldBaseline()
        try requireSelfAttribution()
        let me = ProcessInfo.processInfo.processIdentifier

        let report = holdingSecureEventInput { SecureEventInputProbe.probe() }

        XCTAssertTrue(report.isEnabled, "we were holding it; IsSecureEventInputEnabled() must agree")
        XCTAssertEqual(report.holder, .pid(me),
                       "the IORegistry's kCGSSessionSecureInputPID must name the process that took it")
        let name = try XCTUnwrap(report.holderName, "a known pid must be resolved to something human-readable")
        XCTAssertFalse(name.isEmpty, "an empty holder name is the one thing a diagnostic may never print")
        XCTAssertTrue(report.line.contains("\(me)"),
                      "the line a human reads must carry the pid: \(report.line)")
        XCTAssertTrue(report.line.contains(name),
                      "…and the resolved identity: \(report.line)")
    }

    /// The resolution is not a tautology: it must produce the identity this
    /// process actually has, the way `NSRunningApplication` reports it.
    func testDescribePID_namesTheRunningApplicationForThisProcess() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let description = SecureEventInputProbe.describe(pid: me)

        let expected = NSRunningApplication(processIdentifier: me)?.localizedName
            ?? (ProcessInfo.processInfo.arguments.first as NSString?)?.lastPathComponent
            ?? ProcessInfo.processInfo.processName
        XCTAssertTrue(description.contains(expected),
                      "expected the description of our own pid to contain '\(expected)'; got '\(description)'")
    }

    /// The everyday state, and the one the reader gets when secure input is a
    /// red herring: say it plainly and point somewhere else.
    func testProbe_withNothingHoldingIt_saysSoPlainly() throws {
        try requireUnheldBaseline()

        let report = SecureEventInputProbe.probe()

        XCTAssertFalse(report.isEnabled)
        XCTAssertEqual(report.holder, .none, "nothing holds it, so the registry key is absent")
        XCTAssertNil(report.holderName)
        XCTAssertTrue(report.line.hasPrefix(SecureEventInputProbe.holderMarker))
        XCTAssertTrue(report.line.lowercased().contains("not active"),
                      "the no-holder sentence must be unambiguous: \(report.line)")
    }

    /// Whatever the machine is doing, the probe answers within a test's budget.
    /// A diagnostic that hangs on a denied morning converts one red run into a
    /// timed-out one.
    func testProbe_isCheapEnoughToRunOnEveryDenial() {
        let started = Date()
        for _ in 0..<20 { _ = SecureEventInputProbe.probe().line }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 1.0, "20 probes took \(elapsed)s; this runs once per denied click")
    }

    // MARK: - Graceful degradation: every branch is a short, non-empty sentence

    /// A pid that no longer resolves must still be actionable — the NUMBER is
    /// the thing the reader takes to `ps`, so it may never be swallowed.
    func testLine_anUnresolvablePIDStillNamesTheNumber() {
        let ghost: Int32 = 999_999
        let description = SecureEventInputProbe.describe(pid: ghost)
        let report = SecureEventInputProbe.Report(
            isEnabled: true, holder: .pid(ghost), holderName: description
        )

        XCTAssertFalse(description.isEmpty, "an unresolvable pid degrades to a sentence, never to nothing")
        XCTAssertTrue(report.line.contains("999999"),
                      "the bare pid is the fallback identity: \(report.line)")
        XCTAssertFalse(report.line.contains("\n"), "the line is appended to a one-line mail summary")
    }

    /// Enabled, but the registry names nobody (the key is simply absent, or the
    /// holder belongs to another session). Still a sentence, still says what to
    /// look for.
    func testLine_enabledWithNoRecordedHolder_saysWhatToLookFor() {
        let line = SecureEventInputProbe.Report(isEnabled: true, holder: .none).line

        XCTAssertTrue(line.hasPrefix(SecureEventInputProbe.holderMarker))
        XCTAssertTrue(line.contains("IS active"), line)
        XCTAssertTrue(line.lowercased().contains("secure keyboard entry"),
                      "with no pid, the remedy is the only useful thing left to say: \(line)")
        XCTAssertFalse(line.contains("\n"))
    }

    /// IOKit refused, returned nothing, or the property was not the shape we
    /// expect. The reason travels with the sentence instead of becoming silence.
    func testLine_whenTheRegistryCannotBeRead_saysWhyAndStaysOneLine() {
        let line = SecureEventInputProbe.Report(
            isEnabled: true, holder: .unavailable("IOServiceGetMatchingService returned nothing")
        ).line

        XCTAssertTrue(line.hasPrefix(SecureEventInputProbe.holderMarker))
        XCTAssertTrue(line.contains("IOServiceGetMatchingService returned nothing"),
                      "the failure reason is the diagnostic here: \(line)")
        XCTAssertFalse(line.isEmpty)
        XCTAssertFalse(line.contains("\n"))
    }

    /// The contradiction: the global flag says no, the registry still names a
    /// pid. Report BOTH facts rather than picking one — they are two separate
    /// reads and the gap between them is itself information.
    func testLine_disabledButAPIDIsStillRecorded_reportsBothFacts() {
        let line = SecureEventInputProbe.Report(
            isEnabled: false, holder: .pid(4242), holderName: "Terminal, bundle id com.apple.Terminal"
        ).line

        XCTAssertTrue(line.contains("4242"), line)
        XCTAssertTrue(line.contains("Terminal"), line)
        XCTAssertTrue(line.lowercased().contains("not active"), line)
        XCTAssertFalse(line.contains("\n"))
    }

    // MARK: - The pid is a LEAD, and the sentence has to say so

    /// The sentence that reaches the 07:00 mail names a pid the WindowServer
    /// ATTRIBUTED, which is not always the process that called
    /// `EnableSecureEventInput`. Measured: a holder with no window-server
    /// standing (a launchd agent, a CLI tool over ssh) is recorded as the
    /// FRONTMOST application instead — a foreign `holder_cli` at pid 60419 was
    /// reported as "pid 1881 (Finder)".
    ///
    /// So the line may not issue a bare order. An owner who reads "Quit that
    /// process" at 07:00, quits Finder, and still finds the run red has been
    /// charged MORE than the silence this diagnostic replaced.
    func testLine_whenAPIDIsNamed_hedgesTheAttributionInsteadOfCommanding() {
        let line = SecureEventInputProbe.Report(
            isEnabled: true, holder: .pid(4242), holderName: "Terminal, bundle id com.apple.Terminal"
        ).line

        XCTAssertTrue(line.contains("ps -p 4242"),
                      "the reader must be told how to CONFIRM the pid before acting on it: \(line)")
        XCTAssertTrue(line.lowercased().contains("frontmost"),
                      "…and what the wrong answer looks like when it is wrong: \(line)")
        XCTAssertFalse(line.contains("Quit that process"),
                       "an unhedged imperative on an attributed pid is the defect: \(line)")
        XCTAssertFalse(line.contains("\n"))
    }

    /// The same caveat belongs to the contradiction branch: it names a pid too.
    func testLine_disabledButAPIDIsRecorded_carriesTheSameCaveat() {
        let line = SecureEventInputProbe.Report(
            isEnabled: false, holder: .pid(4242), holderName: "Terminal, bundle id com.apple.Terminal"
        ).line

        XCTAssertTrue(line.contains("ps -p 4242"), line)
        XCTAssertFalse(line.contains("\n"))
    }

    /// Every branch that names a pid hedges it; no branch that names none
    /// offers advice about a pid it does not have.
    func testLine_theCaveatTravelsWithThePIDAndOnlyWithIt() {
        for isEnabled in [true, false] {
            for pid: Int32 in [1, 4242, 999_999] {
                let line = SecureEventInputProbe.Report(
                    isEnabled: isEnabled, holder: .pid(pid),
                    holderName: SecureEventInputProbe.describe(pid: pid)
                ).line
                XCTAssertTrue(line.contains("ps -p \(pid)"),
                              "unhedged pid branch (\(isEnabled)/\(pid)): \(line)")
            }
            for holder: SecureEventInputProbe.Holder in [.none, .unavailable("permission denied")] {
                let line = SecureEventInputProbe.Report(isEnabled: isEnabled, holder: holder).line
                XCTAssertFalse(line.contains("ps -p"),
                               "there is no pid here to confirm (\(isEnabled)/\(holder)): \(line)")
            }
        }
    }

    /// `summary.txt` quotes only the FIRST line, so the caveat has to be on it.
    /// A hedge that lives in a source comment — where the original one did, at
    /// `SecureEventInputProbe.swift:49` — never reaches the person who acts.
    func testEnvironmentFailureMessage_putsTheCaveatOnTheMailedFirstLine() throws {
        let message = GUIFocusHarness.environmentFailureMessage(
            observation: Self.deniedObservation, denials: [],
            secureInput: SecureEventInputProbe.Report(
                isEnabled: true, holder: .pid(4242), holderName: "Terminal, bundle id com.apple.Terminal"
            ).line
        )
        let firstLine = try XCTUnwrap(message.split(separator: "\n", omittingEmptySubsequences: false).first)

        XCTAssertTrue(firstLine.contains("pid 4242"), String(firstLine))
        XCTAssertTrue(firstLine.contains("ps -p 4242"),
                      "the mailed line names a holder; it must hedge it on the same line: \(firstLine)")
    }

    /// And the skip reason, likewise — it is the other place a human reads it.
    func testSkipMessage_carriesTheCaveatWithTheHolderLine() {
        let message = GUIFocusHarness.skipMessage(
            for: Self.deniedObservation, harness: "CadencePlaylistDoubleClickTests",
            secureInput: SecureEventInputProbe.Report(
                isEnabled: true, holder: .pid(4242), holderName: "Terminal"
            ).line
        )

        XCTAssertTrue(message.hasPrefix(GUIFocusHarness.skipMarker))
        XCTAssertTrue(message.contains("ps -p 4242"), message)
    }

    /// No branch of the composition may ever produce an empty or multi-line
    /// string — those are the two shapes that break the mailed summary.
    func testLine_everyBranchIsOneNonEmptyGreppableLine() {
        let holders: [SecureEventInputProbe.Holder] = [
            .none, .pid(1), .pid(999_999), .unavailable("permission denied")
        ]
        for isEnabled in [true, false] {
            for holder in holders {
                let report = SecureEventInputProbe.Report(
                    isEnabled: isEnabled,
                    holder: holder,
                    holderName: { if case .pid(let pid) = holder { return SecureEventInputProbe.describe(pid: pid) } else { return nil } }()
                )
                let line = report.line
                XCTAssertFalse(line.isEmpty, "empty line for \(isEnabled)/\(holder)")
                XCTAssertFalse(line.contains("\n"), "multi-line for \(isEnabled)/\(holder): \(line)")
                XCTAssertTrue(line.hasPrefix(SecureEventInputProbe.holderMarker),
                              "ungreppable for \(isEnabled)/\(holder): \(line)")
            }
        }
    }

    // MARK: - Where a human actually reads it

    /// The gate's skip reason gains the holder line WITHOUT losing the grep
    /// contract CI already counts on.
    func testSkipMessage_keepsTheSkipMarkerAndGainsTheHolderLine() {
        let message = GUIFocusHarness.skipMessage(
            for: Self.deniedObservation,
            harness: "CadencePlaylistDoubleClickTests",
            phase: .beforeEvent,
            secureInput: "\(SecureEventInputProbe.holderMarker) held by pid 4242 (Terminal)"
        )

        XCTAssertTrue(message.hasPrefix(GUIFocusHarness.skipMarker),
                      "the existing grep contract is unchanged: \(message)")
        XCTAssertTrue(message.contains(SecureEventInputProbe.holderMarker),
                      "the second marker makes the holder line findable on its own: \(message)")
        XCTAssertTrue(message.contains("pid 4242"), message)
        XCTAssertTrue(message.contains("NOT verified"), "the existing skip content survives: \(message)")
    }

    /// THE POINT OF THE WHOLE EXERCISE: `summary.txt` quotes only the FIRST LINE
    /// of a failure, so the holder has to be on that line or it never reaches the
    /// morning mail.
    func testEnvironmentFailureMessage_namesTheHolderOnTheLineThatGetsMailed() throws {
        let message = GUIFocusHarness.environmentFailureMessage(
            observation: Self.deniedObservation,
            denials: [GUIFocusHarness.Denial(harness: "FirstRunAcceptanceTests", phase: .beforeEvent,
                                             observation: Self.deniedObservation.summary)],
            secureInput: "\(SecureEventInputProbe.holderMarker) secure event input IS active, "
                + "held by pid 4242 (Terminal, bundle id com.apple.Terminal)"
        )
        let firstLine = try XCTUnwrap(message.split(separator: "\n", omittingEmptySubsequences: false).first)

        XCTAssertTrue(firstLine.hasPrefix(GUIFocusHarness.environmentMarker),
                      "the run-level marker still leads: \(firstLine)")
        XCTAssertTrue(firstLine.contains(SecureEventInputProbe.holderMarker), String(firstLine))
        XCTAssertTrue(firstLine.contains("pid 4242"),
                      "the mailed line must NAME the holder — that is the whole point: \(firstLine)")
        XCTAssertTrue(firstLine.contains("Terminal"), String(firstLine))
    }

    /// End to end, against the real machine: with this process holding secure
    /// input, the message the sentinel would mail names this process.
    func testEnvironmentFailureMessage_endToEnd_namesTheRealHolder() throws {
        try requireUnheldBaseline()
        try requireSelfAttribution()
        let me = ProcessInfo.processInfo.processIdentifier

        let message = holdingSecureEventInput {
            GUIFocusHarness.environmentFailureMessage(
                observation: Self.deniedObservation, denials: []
            )
        }
        let firstLine = try XCTUnwrap(message.split(separator: "\n", omittingEmptySubsequences: false).first)

        XCTAssertTrue(firstLine.contains("pid \(me)"),
                      "the real holder must reach the mailed line: \(firstLine)")
    }

    /// And the gate's skip reason, likewise, against the real machine.
    func testSkipMessage_endToEnd_namesTheRealHolder() throws {
        try requireUnheldBaseline()
        try requireSelfAttribution()
        let me = ProcessInfo.processInfo.processIdentifier

        let message = holdingSecureEventInput {
            GUIFocusHarness.skipMessage(for: Self.deniedObservation, harness: "AnyHarness")
        }

        XCTAssertTrue(message.hasPrefix(GUIFocusHarness.skipMarker))
        XCTAssertTrue(message.contains("pid \(me)"), "the skip reason names the holder:\n\(message)")
    }

    // MARK: - Cost: only when the gate trips

    /// A diagnostic that ran on every passing click would tax 1200 tests to
    /// explain a failure that is not happening. The verdict short-circuits to
    /// `.proceed` without ever asking.
    func testVerdict_doesNotProbeSecureInputOnTheHappyPath() {
        let probes = Counter()
        let keyWindow = GUIFocusHarness.Observation(
            activationPolicy: "regular", processIsActive: true, applicationIsActive: true,
            windowIsKey: true, frontmostApplication: "xctest", waited: 0
        )

        _ = GUIFocusHarness.verdict(for: keyWindow, harness: "AnyHarness",
                                    secureInput: probes.tick())
        XCTAssertEqual(probes.value, 0, "the happy path must not pay for a diagnostic it does not need")

        _ = GUIFocusHarness.verdict(for: Self.deniedObservation, harness: "AnyHarness",
                                    secureInput: probes.tick())
        XCTAssertEqual(probes.value, 1, "…and the denied path must pay for it exactly once")
    }

    private final class Counter {
        var value = 0
        func tick() -> String {
            value += 1
            return "\(SecureEventInputProbe.holderMarker) probed"
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

    // MARK: - Safety plumbing

    /// Take secure event input for the duration of `body` and give it back on
    /// EVERY exit path.
    ///
    /// `defer` covers the three ways out that matter: a normal return, an error
    /// thrown by `body`, and a failed `XCTAssert` inside it (which does not
    /// unwind, but still reaches the return). The fourth — the process dying —
    /// is covered by macOS itself: secure event input is reference-counted PER
    /// PROCESS and released when the process exits, which is why a crashed test
    /// cannot leave the machine held either.
    ///
    /// `DisableSecureEventInput` only decrements THIS process's count, so it can
    /// never take the state away from whoever else might hold it.
    private func holdingSecureEventInput<T>(_ body: () throws -> T) rethrows -> T {
        XCTAssertEqual(EnableSecureEventInput(), noErr, "could not take secure event input")
        defer {
            XCTAssertEqual(DisableSecureEventInput(), noErr, "could not release secure event input")
            assertUnheld("after releasing it, the machine must be back to where it started")
        }
        return try body()
    }

    /// Re-read the real machine state and fail loudly if anything is held.
    private func assertUnheld(_ message: String) {
        XCTAssertFalse(IsSecureEventInputEnabled(), message)
    }

    /// The two cases that assert about an UNHELD machine can only mean anything
    /// on an unheld machine. If something else on this Mac is holding secure
    /// input while the suite runs, say so instead of failing — and note that the
    /// diagnostic under test has just proved its own worth by naming it.
    private func requireUnheldBaseline() throws {
        guard IsSecureEventInputEnabled() else { return }
        throw XCTSkip(
            "this case needs a machine where nothing holds secure event input; "
            + SecureEventInputProbe.diagnosticLine()
        )
    }

    /// The three cases that assert the registry names THIS process need this
    /// process to own a key window — `setUp` takes the front for exactly that
    /// reason, and this reports it if the machine would not grant it.
    ///
    /// Deliberately a check on the PRECONDITION, never on the ANSWER: it asks
    /// `focus`, which `establishFocus` measured before any secure input was
    /// taken, and it never asks the probe. A guard that skipped whenever the
    /// probe failed to name us would make those three assertions incapable of
    /// ever going red, which is the one way this fix could have weakened them.
    private func requireSelfAttribution() throws {
        guard let obstacle = SecureEventInputProbe.selfAttributionObstacle(focus) else { return }
        throw XCTSkip("this case cannot assert self-attribution here: " + obstacle)
    }
}
