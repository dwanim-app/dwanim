import AppKit
import Carbon
import Darwin
import Foundation
import IOKit

// MARK: - SecureEventInputProbe
//
// Answers the ONE question the 2026-09-21 archaeology session could not:
// "cursor securing is active" — held by WHOM?
//
// ## What went wrong, and why a name was unobtainable
// The unattended 07:00 run was refused the front 162 times:
//
//     CPS: Denying xctest the right to be in front because cursor securing is
//     active, this request was not caused by user activity
//
// "cursor securing" is SECURE EVENT INPUT: an application-level state that some
// process on the machine has taken, so that keyboard events stop being visible
// to anyone else. A terminal with Secure Keyboard Entry switched on holds it. A
// focused password field holds it. A pending Keychain or authorization prompt
// holds it.
//
// It is NOT any of the things a CI diagnostic usually reaches for first, and
// each was measured and excluded on this Mac: `displaysleep=0`, `sleep=0`,
// screen saver `idleTime=0`, `screenLock off`. No `caffeinate` flag clears it —
// checked, and deliberately not changed.
//
// So the run was denied by a process, and the process could not be identified:
// `EnableSecureEventInput` is not logged by default, and by the time anyone
// looked, the unified log had rolled past the previous night. The cost of that
// is the reason this file exists — the NEXT denial has to arrive with the name
// already attached.
//
// ## Two facts, read separately
//   1. IS it held at all — `IsSecureEventInputEnabled()` (HIToolbox) is the
//      direct, documented answer, and it is a machine-wide read.
//   2. WHO holds it — WindowServer publishes `kCGSSessionSecureInputPID` inside
//      the `IOConsoleUsers` property of the `IOService:/IOResources` registry
//      entry. That is the same number `ioreg -l -w 0 | grep
//      kCGSSessionSecureInputPID` prints, read here through IOKit directly: a
//      test that parsed another tool's stdout would be one `ioreg` format change
//      away from silently reporting "nobody".
//
// They are reported separately and never collapsed, because the gap between
// them is itself information: the two reads are not atomic, and "the flag says
// no but a pid is still recorded" is a real, reportable state.
//
// ## One honest limit on the pid — AND WHY IT IS IN THE SENTENCE, NOT HERE
// `kCGSSessionSecureInputPID` is WINDOWSERVER'S ATTRIBUTION, not a bare record
// of who called `EnableSecureEventInput`. Measured, four ways: a caller that
// owned the front when it took the hold is named exactly (an activated GUI app
// with a key window — still named afterwards even once another app is
// frontmost); a caller with no such standing is NOT, and the pid recorded is
// the FRONTMOST APPLICATION instead. `NSApplication.shared` alone, an
// activation policy alone, `activate` without a window, and a window put on
// screen with `orderFrontRegardless` but never made key were all measured on
// the wrong side of that line. A foreign command-line holder at pid 60419 was
// reported as "pid 1881 (Finder)" for the whole duration of its hold.
//
// The holders this diagnostic exists to catch — a terminal with Secure Keyboard
// Entry, a SecurityAgent prompt, an app with a focused password field — are all
// activated GUI applications, so the attribution is usually the answer wanted.
// The gap is holders with no window-server standing: launchd agents, helpers,
// CLI tools over ssh.
//
// That caveat therefore lives in the EMITTED SENTENCE and not only in this
// comment. The entire deliverable is one line in an unattended 07:00 mail; a
// line that asserts an identity which can be false and then orders the reader
// to quit that process costs more than the silence it replaced. The sentence
// says "confirm with `ps -p <pid>`" on the same line as the name, where the
// person who acts on it will actually read it.
//
// ## Everything degrades to a sentence
// No holder; a pid that no longer resolves; the registry key absent; IOKit
// returning nothing; a permissions refusal — each produces one short, non-empty,
// single-line sentence carrying whatever IS known. Never a crash, never a hang,
// never an empty string, and never a multi-line blob (the mailed summary quotes
// one line).
//
// ## Cost
// Only the DENIED path asks. `GUIFocusHarness.verdict` short-circuits to
// `.proceed` before the diagnostic is evaluated (it is an `@autoclosure`), so a
// green run pays nothing at all. When it does run it is two synchronous kernel
// property reads plus a `NSRunningApplication` / `proc_pidpath` lookup — no
// retries, no waits, no subprocess, nothing that can block. Measured on this
// Mac: ~1 ms for the whole probe, and `testProbe_isCheapEnoughToRunOnEveryDenial`
// holds 20 consecutive probes under a second.
public enum SecureEventInputProbe {

    /// Leads the holder line wherever it is printed. Deliberately distinct from
    /// `GUIFocusHarness.skipMarker` and `environmentMarker`: CI greps for those
    /// to count denied clicks and denied runs, and for this one to answer "who
    /// was it, then?" — so the three must never be confused for one another.
    public static let holderMarker = "[SECURE-INPUT-HOLDER]"

    /// The registry entry WindowServer publishes the console-session state on.
    private static let resourcesPath = "IOService:/IOResources"
    private static let consoleUsersKey = "IOConsoleUsers"
    /// The key inside a console-session dictionary that names the holder. Same
    /// spelling `ioreg` prints.
    private static let secureInputPIDKey = "kCGSSessionSecureInputPID"

    // MARK: - What the registry could tell us

    /// The answer to "who", with every way of not knowing kept distinct — a
    /// key that is absent means "nobody is holding it", and a registry that
    /// cannot be read means "somebody might be"; conflating them would turn the
    /// diagnostic into the silence it was written to end.
    public enum Holder: Sendable, Equatable {
        /// The registry was read and records no holder.
        case none
        /// The registry names this process.
        case pid(Int32)
        /// The registry could not be read, for this reason.
        case unavailable(String)
    }

    // MARK: - The report (composition is pure, so every branch is testable)

    /// Both facts plus the resolved identity, and the one line a human reads.
    ///
    /// Constructible directly, which is how the degradation branches that cannot
    /// be provoked on a healthy Mac (a dead pid, a refused registry) are still
    /// pinned by tests.
    public struct Report: Sendable, Equatable {
        /// `IsSecureEventInputEnabled()` — is it held at all, by anyone.
        public var isEnabled: Bool
        /// `kCGSSessionSecureInputPID` — by whom.
        public var holder: Holder
        /// `holder`'s pid resolved to something a human can act on; `nil`
        /// whenever there is no pid to resolve.
        public var holderName: String?

        public init(isEnabled: Bool, holder: Holder, holderName: String? = nil) {
            self.isEnabled = isEnabled
            self.holder = holder
            self.holderName = holderName
        }

        /// ONE line: greppable, non-empty in every branch, and safe to append to
        /// the single line `summary.txt` quotes out of a failure message.
        public var line: String {
            "\(SecureEventInputProbe.holderMarker) \(sentence)"
        }

        private var sentence: String {
            switch (isEnabled, holder) {
            case (true, .pid(let pid)):
                return "secure event input IS active, and WindowServer attributes it to pid \(pid) "
                    + "(\(holderName ?? SecureEventInputProbe.describe(pid: pid))) — that is the "
                    + "\"cursor securing\" it names when it denies the front. "
                    + SecureEventInputProbe.attributionCaveat(pid: pid)
            case (true, .none):
                return "secure event input IS active, but no holder is recorded "
                    + "(\(SecureEventInputProbe.secureInputPIDKey) is absent from \(SecureEventInputProbe.consoleUsersKey)) — the owner is not visible "
                    + "from this session. Look for a terminal with Secure Keyboard Entry on, a focused "
                    + "password field, or a pending Keychain or authorization prompt."
            case (true, .unavailable(let reason)):
                return "secure event input IS active, but the holder could not be read (\(reason)) — look for "
                    + "a terminal with Secure Keyboard Entry on, a focused password field, or a pending "
                    + "Keychain or authorization prompt."
            case (false, .pid(let pid)):
                return "secure event input reports NOT active, yet pid \(pid) (\(holderName ?? SecureEventInputProbe.describe(pid: pid))) "
                    + "is still recorded as the holder — the two reads are not atomic, so this is a holder "
                    + "releasing (or taking) it right now; re-run to settle it. "
                    + SecureEventInputProbe.attributionCaveat(pid: pid)
            case (false, .none):
                return "secure event input is NOT active and no process holds it — cursor securing is not what "
                    + "denied the front here. Look instead at the screen lock, the screen saver, or another "
                    + "application refusing to give up the front."
            case (false, .unavailable(let reason)):
                return "secure event input is NOT active; the holder registry could not be read (\(reason)), "
                    + "which costs nothing while nothing is held."
            }
        }
    }

    // MARK: - The caveat that travels with a pid

    /// What the reader must know BEFORE acting on a pid this probe printed,
    /// and how to settle it in one command.
    ///
    /// Appended to every sentence that names a pid, and to no sentence that
    /// does not. It is deliberately imperative about VERIFYING and never about
    /// quitting: the previous wording ended "Quit that process", and the pid it
    /// said that about was measured naming an innocent Finder while a
    /// command-line tool held the input. An owner who follows a wrong order at
    /// 07:00 has been charged more than the silence this line replaced.
    ///
    /// The pid is repeated inside the `ps` invocation on purpose — the reader
    /// should be able to paste it without reconstructing the number.
    public static func attributionCaveat(pid: Int32) -> String {
        "TREAT THAT PID AS A LEAD, NOT A CONFESSION: it is WindowServer's attribution for the "
            + "console session, and it names the real taker only when that taker owned the front when "
            + "it took the hold — the usual causes do (Secure Keyboard Entry in a terminal, a focused "
            + "password field, a pending Keychain or authorization prompt), but a holder with no "
            + "window-server standing (a launchd agent, a helper, a CLI tool over ssh) is recorded as "
            + "the FRONTMOST application instead. Confirm with `ps -p \(pid)` and check that process's "
            + "own state before quitting anything."
    }

    // MARK: - When "it should name US" is a meaningful thing to assert

    /// Why this process cannot expect the registry to name IT right now — or
    /// `nil` when it can.
    ///
    /// The attribution rule cuts both ways. A test that holds secure input
    /// itself and then asserts the probe names it is only meaningful while this
    /// process owns a key window; without one, the very same call is attributed
    /// to whatever is frontmost, and the assertion fails on a perfectly healthy
    /// Mac. `SecureEventInputProbeTests` consults this so that it reports the
    /// mechanism instead of a bare inequality.
    ///
    /// It reads ONLY the observation — the activation state measured before any
    /// secure input was taken — and never the probe's own answer, so it cannot
    /// turn the assertions it guards into ones that can never fail.
    public static func selfAttributionObstacle(_ observation: GUIFocusHarness.Observation) -> String? {
        guard !observation.windowIsKey else { return nil }
        return "this process does not own a key window (\(observation.summary)), and "
            + "\(secureInputPIDKey) names the caller only while the caller owns the front — without one "
            + "the registry records the FRONTMOST application instead, so \"the probe must name us\" "
            + "cannot be asserted here. Run this suite in an interactive GUI session: logged in, screen "
            + "unlocked, at the keyboard, with nothing else holding the front."
    }

    // MARK: - Reading the machine

    /// Both facts and the resolved name, in one call. Never throws, never
    /// blocks, never returns an empty line.
    public static func probe() -> Report {
        let holder = currentHolder()
        var name: String?
        if case .pid(let pid) = holder { name = describe(pid: pid) }
        return Report(isEnabled: isEnabled(), holder: holder, holderName: name)
    }

    /// `probe().line` — the form the two call sites want.
    public static func diagnosticLine() -> String { probe().line }

    /// Fact one, straight from HIToolbox: is secure event input held by anyone.
    public static func isEnabled() -> Bool { IsSecureEventInputEnabled() }

    /// Fact two, straight from the IORegistry.
    ///
    /// Deliberately NOT `ioreg | grep`: the value is a property, and reading it
    /// as one means no subprocess, no stdout parsing, no dependency on another
    /// tool's output format, and nothing that can hang. Every failure mode is
    /// returned as `.unavailable(reason)` rather than thrown or logged, because
    /// the caller is already in the middle of reporting a different failure.
    public static func currentHolder() -> Holder {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, resourcesPath)
        guard entry != MACH_PORT_NULL else {
            return .unavailable("\(resourcesPath) is not present in the IORegistry")
        }
        defer { IOObjectRelease(entry) }

        guard let property = IORegistryEntryCreateCFProperty(
            entry, consoleUsersKey as CFString, kCFAllocatorDefault, 0
        ) else {
            return .unavailable("the \(consoleUsersKey) property could not be read "
                                + "(sandbox or permissions)")
        }
        guard let sessions = property.takeRetainedValue() as? [[String: Any]] else {
            return .unavailable("\(consoleUsersKey) is not the array of session dictionaries "
                                + "this reader expects")
        }

        for session in sessions {
            guard let number = session[secureInputPIDKey] as? NSNumber else { continue }
            return .pid(number.int32Value)
        }
        return .none
    }

    // MARK: - Turning a number into something actionable

    /// A pid as a human can use it: the app's localized name and bundle id when
    /// it is a GUI application (the usual case — terminals, browsers, Keychain
    /// Access), the executable name and path when it is not, and an explicit
    /// "it is gone" when it resolves to neither.
    ///
    /// The returned string never contains the pid: the caller already prints
    /// `pid N`, and the number must survive even the last fallback.
    public static func describe(pid: Int32) -> String {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent
            switch (name, app.bundleIdentifier) {
            case let (name?, bundleID?): return "\(name), bundle id \(bundleID)"
            case let (name?, nil):       return name
            case let (nil, bundleID?):   return "bundle id \(bundleID)"
            case (nil, nil):             break
            }
        }
        if let path = executablePath(of: pid) {
            return "\((path as NSString).lastPathComponent) at \(path)"
        }
        return "no longer a running process — it exited since it took secure event input, "
            + "or it belongs to another user"
    }

    /// The executable behind a pid, for processes `NSRunningApplication` does
    /// not know (daemons, helpers, anything without an app bundle).
    /// `proc_pidpath` is a single non-blocking syscall and returns 0 for a pid
    /// that is gone or not ours to look at.
    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard written > 0 else { return nil }
        return String(cString: buffer)
    }
}
