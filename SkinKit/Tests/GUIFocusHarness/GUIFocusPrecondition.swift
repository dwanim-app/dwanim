import AppKit
import XCTest

// MARK: - GUIFocusHarness
//
// THE ONE SEAM every in-process click harness takes its environment from.
//
// ## What these harnesses need, and why it can be missing
// A harness that drives SYNTHESIZED `NSEvent`s through `window.sendEvent` only
// works while this process owns a KEY window: `NSTableView` selection and
// SwiftUI `Slider` drags are gated on key-window status, and macOS only lets a
// window become key while its APPLICATION is allowed to come to the front.
//
// A locked screen removes that permission process-wide. On 2026-09-21 the
// unattended 07:00 job started 38 seconds after the session shield went up, and
// WindowServer logged, 162 times:
//
//     CPS: Denying xctest the right to be in front because cursor securing is
//     active, this request was not caused by user activity
//
// No window became key, every synthesized click was inert, and the suites
// reported their EFFECT assertions — "engine.play called exactly once",
// "0 indexes is not equal to 1 indexes" — so the morning report read as a
// product regression in the playlist and the equalizer. It was not: the same
// tests pass interactively on the same commit.
//
// ## The contract this type imposes
//   1. The precondition is re-observed AT THE POINT OF USE — immediately before
//      each synthesized event and again immediately after it — never once in
//      `setUp`. Key-window status is not sticky: measured on this machine,
//      3 of 6 full-suite runs lost the front somewhere between `setUp` and a
//      click (another app activating, the previous suite's window closing), and
//      a one-shot gate reported those as EFFECT failures — the very signature
//      this seam exists to eliminate.
//   2. Establishing the front CANNOT skip anything. `establishFocus` does not
//      throw, so a suite's `setUp` cannot make its whole class conditional on
//      the environment. Only `synthesize` — the click itself — can skip, so the
//      22 tests in these suites that never synthesize an event (bitmap, layout,
//      accessibility-label and localization assertions) keep running behind a
//      locked screen and keep catching regressions there.
//   3. The skip is LOUD: the message leads with `skipMarker` (greppable and
//      countable by CI), names the harness, the precondition, the phase, the
//      observed state, the remedy, and states that nothing was verified.
//   4. The gate opens on ONE condition — no key window AND no front. If this
//      process IS the active application and the window still is not key,
//      something IN-PROCESS holds key, which is the product's business: the
//      test runs and is allowed to fail. Every real denial measured (the 07:00
//      job, the focus-hog repro) reads `isKeyWindow=false processIsActive=false
//      NSApp.isActive=false`, never a mixture, so this costs nothing and closes
//      the only way a product change could have reached the skip path.
//   5. Every denial is recorded in `DenialLedger.shared`, which
//      `ZzGUIFocusEnvironmentSentinelTests` turns into the single FAILING case
//      that makes a denied run red. `summary.txt` prints failures and not
//      skips, so without that one failure a fully-skipped run mails as
//      "1198 tests, 0 failed, 100.0% pass rate, ALL GREEN" and promotes a
//      coverage baseline measured with 187 production lines never executed.
//
// This mirrors `AudioOutputDeviceProbe` in PlaybackKitTests: an INDEPENDENT
// probe of the environment, deliberately unable to mask the bug class the tests
// exist to catch.
public enum GUIFocusHarness {

    /// Leads every per-test skip message. CI greps and counts this; it is a
    /// contract.
    public static let skipMarker = "[GUI-FOCUS-SKIP]"

    /// Leads the run-level sentinel FAILURE. Deliberately distinct from
    /// `skipMarker`: one marks a test that did not run, the other marks a run
    /// whose acceptance layer did not run at all.
    public static let environmentMarker = "[GUI-FOCUS-ENVIRONMENT]"

    /// How long `establishFocus` waits for a window to become key. Deliberately
    /// longer than the 3 s the old hand-rolled loops used: that deadline was
    /// undeclared and load-bearing, and on a slow morning it could expire for a
    /// reason other than the lock.
    public static let defaultTimeout: TimeInterval = 5

    /// Once this process has been denied the front, the denial is usually
    /// process-wide and persistent (it is the session that is locked, not this
    /// window), so later attempts wait only this long — otherwise every gated
    /// test would pay the full timeout. A success at any point clears the flag.
    public static let retryTimeoutAfterDenial: TimeInterval = 0.75

    /// How long the point-of-use gate spends trying to take the front BACK
    /// after a transient loss before it gives up and skips. Long enough to
    /// survive the window churn between two suites, short enough that a locked
    /// morning does not spend minutes discovering it is still locked.
    public static let reacquireTimeout: TimeInterval = 1.5

    // MARK: - Observation

    /// What the harness could see about its own activation at the moment it
    /// looked. Everything the skip message reports comes from here.
    public struct Observation: Sendable, Equatable {
        public var activationPolicy: String
        public var processIsActive: Bool
        public var applicationIsActive: Bool
        public var windowIsKey: Bool
        public var frontmostApplication: String
        public var waited: TimeInterval

        public init(
            activationPolicy: String,
            processIsActive: Bool,
            applicationIsActive: Bool,
            windowIsKey: Bool,
            frontmostApplication: String,
            waited: TimeInterval
        ) {
            self.activationPolicy = activationPolicy
            self.processIsActive = processIsActive
            self.applicationIsActive = applicationIsActive
            self.windowIsKey = windowIsKey
            self.frontmostApplication = frontmostApplication
            self.waited = waited
        }

        /// One line, every field, for the skip message.
        public var summary: String {
            String(
                format: "isKeyWindow=%@ processIsActive=%@ NSApp.isActive=%@ activationPolicy=%@ frontmost=%@ waited=%.1fs",
                windowIsKey ? "true" : "false",
                processIsActive ? "true" : "false",
                applicationIsActive ? "true" : "false",
                activationPolicy,
                frontmostApplication,
                waited
            )
        }
    }

    /// WHERE the front was missing. Different phases are different diagnoses:
    /// "never had it" is a locked session, "had it and lost it mid-click" is
    /// another app taking the front — and the second one is what survived the
    /// first version of this gate.
    public enum Phase: String, Sendable, CaseIterable {
        /// While setting the window up, before any event.
        case precondition
        /// Checked immediately before an event is synthesized.
        case beforeEvent
        /// Checked immediately after the event was delivered and drained, i.e.
        /// just before the test would assert on its effect.
        case afterEvent
    }

    /// The decision, kept separate from the act of skipping so it can be tested
    /// without an environment.
    public enum Verdict: Equatable {
        /// The precondition holds — or the environment is not what is denying
        /// it. Everything from here on is the product's responsibility, and any
        /// failure is a real failure.
        case proceed
        /// The precondition cannot be met here; skip with this message.
        case skip(String)
    }

    // MARK: - The ledger

    /// One recorded denial: which harness, where, and what was observed.
    public struct Denial: Sendable, Equatable {
        public var harness: String
        public var phase: Phase
        public var observation: String

        public init(harness: String, phase: Phase, observation: String) {
            self.harness = harness
            self.phase = phase
            self.observation = observation
        }

        public var summary: String { "\(harness) (\(phase.rawValue)): \(observation)" }
    }

    /// Append-only record of every denial in this process. `shared` is what the
    /// run-level sentinel reads; there is deliberately no way to clear it, so a
    /// denial cannot be erased before the sentinel looks. Tests of the gate
    /// itself pass their OWN ledger instead, which is why this is an object and
    /// not a global.
    @MainActor
    public final class DenialLedger {
        public static let shared = DenialLedger()

        public private(set) var entries: [Denial] = []

        public init() {}

        public func record(_ denial: Denial) {
            entries.append(denial)
        }
    }

    // MARK: - The decision (pure)

    /// A key window opens the gate — and so does the absence of an environment
    /// excuse.
    ///
    /// Note what this does NOT do: it does not treat a missing key window as
    /// skippable while this process IS the front application. In that state
    /// nothing outside the process is denying anything, so whatever took key is
    /// in here with us and the test must RUN and be allowed to fail.
    public static func verdict(
        for observation: Observation,
        harness: String,
        phase: Phase = .precondition
    ) -> Verdict {
        if observation.windowIsKey { return .proceed }
        if observation.applicationIsActive || observation.processIsActive { return .proceed }
        return .skip(skipMessage(for: observation, harness: harness, phase: phase))
    }

    public static func skipMessage(
        for observation: Observation,
        harness: String,
        phase: Phase = .precondition
    ) -> String {
        """
        \(skipMarker) \(harness): \(headline(for: phase))
          precondition : window.isKeyWindow == true, re-checked immediately before and after every synthesized event
          observed     : \(observation.summary)
          why          : macOS grants a key window only to an application it lets come to the front. \
        A locked screen or an active screen saver revokes that permission process-wide — WindowServer \
        logs "Denying xctest the right to be in front because cursor securing is active" — and without \
        a key window synthesized NSEvents reach no NSTableView selection and no SwiftUI Slider.
          what to do   : run these tests in an interactive GUI session — logged in, screen unlocked, \
        at the keyboard, with nothing else grabbing the front. An unattended/launchd run must keep the \
        session unlocked for its whole duration (e.g. re-exec under `caffeinate -d -i -m -s -u`); there \
        is no in-process workaround — orderFrontRegardless, .accessory policy, offscreen windows, direct \
        view.mouseDown and even real CGEvent posting were all measured and all fail the same way behind \
        the lock.
          NOTE         : this is an ENVIRONMENT skip. The product was NOT verified here — treat it as \
        a gap in the run, not as a pass. The run-level sentinel \
        (ZzGUIFocusEnvironmentSentinelTests) FAILS when this happens, so the report is red.
        """
    }

    private static func headline(for phase: Phase) -> String {
        switch phase {
        case .precondition:
            return "this in-process click harness needs a key window and never got one."
        case .beforeEvent:
            return "this in-process click harness lost the front before the click could be delivered, "
                + "so the click was NOT synthesized."
        case .afterEvent:
            return "this in-process click harness lost the front while the click was being delivered, "
                + "so the click reached nothing and its effect was NOT asserted."
        }
    }

    /// The run-level message: what the owner reads in the mailed report.
    ///
    /// `summary.txt` quotes only the FIRST LINE of a failure's message (it is
    /// the text after `] : ` on XCTest's diagnostic line), so that line has to
    /// stand alone: what happened, that it is not a product bug, and what to do
    /// about it. The rest is for whoever opens `swift_test.log`.
    public static func environmentFailureMessage(observation: Observation, denials: [Denial]) -> String {
        let harnesses = Array(Set(denials.map(\.harness))).sorted()
        var lines = [
            "\(environmentMarker) the GUI click environment was denied to this run: "
            + "\(denials.count) gated click(s) were skipped across \(harnesses.count) harness(es). "
            + "This is NOT a product failure — the acceptance layer never ran, so nothing was verified. "
            + "Run with the screen unlocked and the session at the keyboard; an unattended job must "
            + "re-exec under `caffeinate -d -i -m -s -u` (or the whole GUI tier stays unverified)."
        ]
        lines.append("  sentinel probe : \(observation.summary)")
        if harnesses.isEmpty {
            lines.append("  denied harnesses: (none recorded — this sentinel's own probe never became key)")
        } else {
            lines.append("  denied harnesses:")
            for harness in harnesses {
                let count = denials.filter { $0.harness == harness }.count
                lines.append("    - \(harness): \(count) skipped click(s)")
            }
        }
        lines.append("  detail         : grep \(skipMarker) in swift_test.log for each skipped case.")
        lines.append("  WHY THIS FAILS : a denied run that exits 0 mails as ALL GREEN with a 100% pass "
                     + "rate and promotes a coverage baseline that never executed the GUI tier. One "
                     + "named failure is the only signal this side of automation/ can send.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Establishing the front (never skips)

    /// Take the front, best effort, and report what was achieved.
    ///
    /// Deliberately NON-THROWING. A suite's `setUp` calls this, and a `setUp`
    /// that could skip would skip every test in its class — including the many
    /// that never synthesize an event and do not need a key window at all. That
    /// was measured: with the front hard-denied, 22 of the 56 tests in the six
    /// gated suites still pass, and gating in `setUp` reported all 56 as
    /// environment skips, hiding those 22 behind the skip path.
    @discardableResult
    @MainActor
    public static func establishFocus(
        _ window: NSWindow,
        harness: String,
        timeout: TimeInterval? = nil
    ) -> Observation {
        let started = Date()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        // The deprecated "ignoring other apps" pair, deliberately: the modern
        // `NSApp.activate()` is a POLITE request, and a test runner launched
        // from a terminal that holds the front never wins it — measured, the
        // window stayed non-key and every harness skipped even with the screen
        // unlocked. These two are what the harnesses have always used and what
        // actually takes the front in an interactive session; behind a locked
        // screen WindowServer denies them too, which is the case this seam is
        // here to report.
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        let budget = timeout ?? (hasBeenDeniedInThisProcess ? retryTimeoutAfterDenial : defaultTimeout)
        let deadline = Date(timeIntervalSinceNow: budget)
        repeat {
            window.makeKeyAndOrderFront(nil)
            // Explicit and separate from `makeKeyAndOrderFront`: measured to be
            // the difference between a selection landing and not, whenever the
            // app is active but some other window of this process holds key.
            // It cannot manufacture a key window while the front is denied, so
            // it can never open the gate dishonestly.
            window.makeKey()
            pump(0.1)
        } while !window.isKeyWindow && Date() < deadline

        let observation = observe(window, waited: Date().timeIntervalSince(started))
        hasBeenDeniedInThisProcess = !observation.windowIsKey
        return observation
    }

    // MARK: - The point-of-use gate (the only thing that skips)

    /// Deliver one synthesized event with the front checked on BOTH sides of it.
    ///
    /// Before: if the window is not key, take the front back once (windows churn
    /// between suites, notifications steal it) and only skip if that fails.
    /// After: look again. A front lost while the event was in flight means the
    /// click reached nothing, and the caller's effect assertion would otherwise
    /// report it as a product failure — the exact 2026-09-21 signature.
    @MainActor
    @discardableResult
    public static func synthesize<T>(
        in window: NSWindow,
        harness: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ deliver: @MainActor () throws -> T
    ) throws -> T {
        var spentReacquiring: TimeInterval = 0
        return try guardedEvent(
            harness: harness,
            file: file,
            line: line,
            isKeyWindow: { window.isKeyWindow },
            reacquire: {
                // A genuine transient gets the full re-acquire budget; once the
                // front has been denied outright, every later attempt is almost
                // certainly denied too, so it pays the short budget instead of
                // adding seconds per click to a locked morning.
                let budget = hasBeenDeniedInThisProcess ? retryTimeoutAfterDenial : reacquireTimeout
                let attempt = establishFocus(window, harness: harness, timeout: budget)
                spentReacquiring += attempt.waited
            },
            // `waited` is how long THIS click spent trying to take the front
            // back, so the skip message says what was actually attempted rather
            // than a hard-coded zero.
            observe: { observe(window, waited: spentReacquiring) },
            deliver: deliver
        )
    }

    /// The gate itself, with the environment injected so both directions can be
    /// unit-tested without one (see `GUIFocusPreconditionTests`).
    @MainActor
    @discardableResult
    public static func guardedEvent<T>(
        harness: String,
        ledger: DenialLedger = .shared,
        file: StaticString = #filePath,
        line: UInt = #line,
        isKeyWindow: @MainActor () -> Bool,
        reacquire: @MainActor () -> Void,
        observe: @MainActor () -> Observation,
        deliver: @MainActor () throws -> T
    ) throws -> T {
        if !isKeyWindow() {
            reacquire()                       // a transient loss is recovered, not reported
        }
        if !isKeyWindow() {
            try refuse(.beforeEvent, harness: harness, ledger: ledger,
                       observe: observe, file: file, line: line)
        }

        let value = try deliver()

        if !isKeyWindow() {
            try refuse(.afterEvent, harness: harness, ledger: ledger,
                       observe: observe, file: file, line: line)
        }
        return value
    }

    /// Record the denial and skip — unless the observation says the front was
    /// ours all along, in which case there is no environment excuse and the
    /// caller's own assertions must decide.
    @MainActor
    private static func refuse(
        _ phase: Phase,
        harness: String,
        ledger: DenialLedger,
        observe: @MainActor () -> Observation,
        file: StaticString,
        line: UInt
    ) throws {
        let observation = observe()
        guard case .skip(let message) = verdict(for: observation, harness: harness, phase: phase) else {
            return   // this process holds the front: not the environment's fault, so let the test speak
        }
        ledger.record(Denial(harness: harness, phase: phase, observation: observation.summary))
        if ledger === DenialLedger.shared {
            // Only a REAL denial shortens the next wait and prints the banner;
            // the gate's own unit tests pass their own ledger, and a unit test
            // must not make the log look like a denied morning.
            hasBeenDeniedInThisProcess = true
            announceOnce(message)
        }
        throw XCTSkip(message, file: file, line: line)
    }

    // MARK: - Shared plumbing

    /// Read the activation state, for the record.
    @MainActor
    public static func observe(_ window: NSWindow, waited: TimeInterval) -> Observation {
        Observation(
            activationPolicy: describe(NSApp.activationPolicy()),
            processIsActive: NSRunningApplication.current.isActive,
            applicationIsActive: NSApp.isActive,
            windowIsKey: window.isKeyWindow,
            frontmostApplication: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                ?? NSWorkspace.shared.frontmostApplication?.localizedName
                ?? "(none)",
            waited: waited
        )
    }

    /// Drain `NSApp`'s queue through `sendEvent` and spin the run loop for
    /// `seconds` — the event plumbing every harness shares.
    @MainActor
    public static func pump(_ seconds: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        repeat {
            while let event = NSApp.nextEvent(
                matching: .any, until: Date(timeIntervalSinceNow: 0.01),
                inMode: .default, dequeue: true
            ) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
    }

    // MARK: - Private

    @MainActor private static var hasBeenDeniedInThisProcess = false
    @MainActor private static var hasAnnounced = false

    /// Print the diagnosis once per process. XCTest's own skip line is easy to
    /// lose in a long log, and the mailed report renders only failures, so this
    /// banner plus the sentinel's failure are what a reader gets.
    @MainActor
    private static func announceOnce(_ message: String) {
        guard !hasAnnounced else { return }
        hasAnnounced = true
        print("""

        ================================================================================
        \(message)

        Every further denial in this run is skipped the same way and recorded;
        ZzGUIFocusEnvironmentSentinelTests fails at the end of the run with the total.
        ================================================================================

        """)
    }

    private static func describe(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular: return "regular"
        case .accessory: return "accessory"
        case .prohibited: return "prohibited"
        @unknown default: return "unknown(\(policy.rawValue))"
        }
    }
}
