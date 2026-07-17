import Foundation

// MARK: - ClickModifiers

/// The modifier keys held during a mouse-down, extracted from the `NSEvent` at
/// the view boundary (`ScaledImageView.mouseDown`) into a plain value so the
/// controllers stay `NSEvent`-free and unit-testable. Only the modifiers the
/// skin windows act on are carried: `command` toggles a playlist row in/out of
/// the multi-selection; `shift` is reserved for range-select (not wired yet).
/// Windows that ignore modifiers simply discard the parameter.
public struct ClickModifiers: Sendable, Equatable {
    public let command: Bool
    public let shift: Bool

    public init(command: Bool = false, shift: Bool = false) {
        self.command = command
        self.shift = shift
    }

    /// No modifiers held — the plain click.
    public static let none = ClickModifiers()
}
