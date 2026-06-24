import SwiftUI

// MARK: - TransportButton

/// A single glass transport button: an SF Symbol on a translucent rounded
/// panel. The primary (play/pause) variant is gold-filled to read as the main
/// action; secondary buttons (previous / next) are quiet glass with a gold
/// symbol.
///
/// The button is purely presentational plus an `action` closure — it holds no
/// playback state. The owning view decides which symbol to show (e.g. `play.fill`
/// vs `pause.fill`) from the live `PlayerCore` state and wires `action` to the
/// matching transport call.
struct TransportButton: View {

    /// The SF Symbol name, e.g. `play.fill` / `pause.fill` / `backward.fill`.
    let systemName: String
    /// Whether this is the gold-filled primary button.
    let isPrimary: Bool
    /// The button's diameter in points.
    let diameter: CGFloat
    /// An accessibility label (the symbol is decorative on its own).
    let label: String
    /// The transport action to run on tap.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                Image(systemName: systemName)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(isPrimary ? AnyShapeStyle(Color.black.opacity(0.75))
                                               : AnyShapeStyle(DwanimTheme.goldGradient))
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if isPrimary {
            Circle()
                .fill(DwanimTheme.goldGradient)
                .overlay { Circle().stroke(DwanimTheme.glassStrokeStrong, lineWidth: 1) }
                .shadow(color: DwanimTheme.goldDeep.opacity(0.6), radius: diameter * 0.12)
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay { Circle().stroke(DwanimTheme.glassStroke, lineWidth: 1) }
        }
    }
}
