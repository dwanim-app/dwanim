import XCTest
@testable import PlayerCore

/// Pins `RepeatMode.nextInCycle`, the SINGLE definition of the repeat button's
/// press order.
///
/// Both faces cycle the same three states, so the order lives on the model rather
/// than in either view: the classic `.wsz` face reaches it through
/// `PlayerControl.nextRepeatMode` (its `.toggleRepeat` control), and the Cadence
/// face's Repeat pill calls it directly. Before this, Cadence hard-coded a
/// 2-state `off ↔ .one` flip, which made `.all` — the wrapping mode — unreachable
/// from the default UI.
final class RepeatModeCycleTests: XCTestCase {

    /// The order itself: OFF → ALL → ONE → OFF.
    func testCycleOrderIsOffThenAllThenOne() {
        XCTAssertEqual(RepeatMode.off.nextInCycle, .all, "off -> all")
        XCTAssertEqual(RepeatMode.all.nextInCycle, .one, "all -> one")
        XCTAssertEqual(RepeatMode.one.nextInCycle, .off, "one -> off")
    }

    /// Three presses return to the start from ANY state, so the button can never
    /// strand the listener in a mode they cannot press their way out of.
    func testThreePressesReturnToTheStartingModeFromEveryState() {
        for start in [RepeatMode.off, .all, .one] {
            let after = start.nextInCycle.nextInCycle.nextInCycle
            XCTAssertEqual(after, start, "three presses from \(start) must return to \(start)")
        }
    }

    /// One full cycle visits all three states — no mode is skipped (the bug this
    /// replaces: `.all` was unreachable from the Cadence UI).
    func testOneCycleVisitsEveryMode() {
        var seen: [RepeatMode] = []
        var mode = RepeatMode.off
        for _ in 0..<3 {
            seen.append(mode)
            mode = mode.nextInCycle
        }
        XCTAssertEqual(seen, [.off, .all, .one])
    }
}
