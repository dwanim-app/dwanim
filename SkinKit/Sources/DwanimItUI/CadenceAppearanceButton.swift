import SwiftUI

// MARK: - CadenceAppearanceButton

/// The title-bar Appearance pop-up button and its popover. The button shows the
/// current theme's swatch + name + a chevron chip; tapping it opens a popover to
/// switch between the built-in themes instantly.
///
/// Phase-1 scope: switching between built-ins is live. The **Open Skin…** row (which
/// will open a colour-file in a later phase) is a STUB — it invokes the optional
/// `onOpenColorTheme` closure, which is nil this phase, so the row is disabled and
/// no file panel / parser is wired.
struct CadenceAppearanceButton: View {

    @Bindable var store: AppearanceStore
    /// Phase-2 hook to open a colour-theme file. Nil this phase → the row is disabled.
    let onOpenColorTheme: (() -> Void)?

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 7) {
                swatch(store.current, side: 11, corner: 3)
                Text(store.current.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isOpen ? Color.white : AppearanceTheme.buttonLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 96, alignment: .leading)
                    .fixedSize()
                chevronChip
            }
            .padding(.leading, 7)
            .padding(.trailing, 5)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isOpen ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppearanceTheme.buttonEdge, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Appearance")
        .accessibilityLabel(Text("Appearance: \(store.current.name)"))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            popoverContent
                .frame(width: 236)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var chevronChip: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(store.current.text)
            .frame(width: 14, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(store.current.accent)
            )
    }

    // MARK: Popover

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Appearance")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppearanceTheme.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 5)
                .padding(.bottom, 4)

            ForEach(store.builtIns) { theme in
                themeRow(theme)
            }

            Divider()
                .padding(.horizontal, 6)
                .padding(.vertical, 5)

            openThemeRow

            Text(hintText)
                .font(.system(size: 10))
                .foregroundStyle(AppearanceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 5)
                .padding(.bottom, 4)
        }
        .padding(5)
    }

    private func themeRow(_ theme: AppearanceTheme) -> some View {
        let isActive = theme.name == store.current.name
        return Button {
            store.select(theme)
            isOpen = false
        } label: {
            HStack(spacing: 8) {
                swatch(theme, side: 12, corner: 3)
                Text(theme.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppearanceTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(store.current.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.11) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var openThemeRow: some View {
        Button {
            onOpenColorTheme?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(AppearanceTheme.secondary)
                    .frame(width: 12)
                Text("Open Skin…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppearanceTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("⌘O")
                    .font(.system(size: 11))
                    .foregroundStyle(AppearanceTheme.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpenColorTheme == nil)
    }

    private var hintText: String {
        "Current: \(store.current.name) — A theme is a .json or .dwskin file of colors."
    }

    // MARK: Swatch

    /// The theme swatch: a 135° hard diagonal split of `accent` (0–52%) over `bg1`
    /// (52–100%), matching the design.
    private func swatch(_ theme: AppearanceTheme, side: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: theme.accent, location: 0),
                        .init(color: theme.accent, location: 0.52),
                        .init(color: theme.bg1, location: 0.52),
                        .init(color: theme.bg1, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: side, height: side)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
    }
}
