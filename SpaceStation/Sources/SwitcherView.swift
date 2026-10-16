import SwiftUI

/// One card's data.
struct SwitcherItem: Identifiable, Equatable {
    let space: SpaceInfo
    let name: String
    let icon: SpaceIcon?
    var id: String { space.id }
}

/// Observable state for the switcher panel.
@MainActor
final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    /// ID of the current desktop, nil while in a fullscreen Space.
    @Published var currentID: String?
    @Published var selectedIndex = 0
    @Published var cardWidth: CGFloat = SwitcherLayout.preferredCardWidth
    @Published var showsHints = true
    @Published var highContrast = false
}

/// The content of the switcher panel: a grid of cards and a hint footer. The window it sits in
/// (a non-activating panel with a blurred, rounded background) is set up by the controller.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onPick: (SpaceInfo) -> Void

    var body: some View {
        let count = model.items.count
        let columns = SwitcherLayout.columns(for: count)
        let rows = SwitcherLayout.rows(for: count)

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: SwitcherLayout.cardGap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: SwitcherLayout.cardGap) {
                        ForEach(row * columns..<min((row + 1) * columns, count), id: \.self) { index in
                            SwitcherCard(item: model.items[index],
                                         number: index + 1,
                                         isCurrent: model.items[index].id == model.currentID,
                                         isSelected: index == model.selectedIndex,
                                         width: model.cardWidth,
                                         showsNumberHint: model.showsHints,
                                         highContrast: model.highContrast,
                                         onPick: onPick)
                        }
                    }
                }
            }
            .padding(SwitcherLayout.panelPadding)

            if model.showsHints {
                SwitcherFooter(twoRows: rows > 1)
            }
        }
        .fixedSize()
    }
}

// MARK: - Card

struct SwitcherCard: View {
    let item: SwitcherItem
    let number: Int
    let isCurrent: Bool
    let isSelected: Bool
    let width: CGFloat
    let showsNumberHint: Bool
    let highContrast: Bool
    let onPick: (SpaceInfo) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { onPick(item.space) }) {
            VStack(spacing: 6) {
                SwitcherIconTile(icon: item.icon, number: item.space.index)

                // Two lines are always reserved so every card has the same height.
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .top)

                // A running-app style dot, like the Dock. Never an accent fill: that would
                // be confused with the keyboard selection.
                Circle()
                    .fill(Color(nsColor: .labelColor).opacity(0.6))
                    .frame(width: 4, height: 4)
                    .opacity(isCurrent ? 1 : 0)
            }
            .padding(.top, 12)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .frame(width: width, height: SwitcherLayout.cardHeight)
            .overlay(alignment: .topTrailing) {
                // Only 1-9 can be jumped to with a single key.
                if showsNumberHint, number <= 9 {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SwitcherCardButtonStyle(isSelected: isSelected, highContrast: highContrast, colorScheme: colorScheme))
        .help(item.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), Space \(item.space.index)\(isCurrent ? ", current Space" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Selected (keyboard or hover) cards get a quiet fill plus a focus ring; pressed cards a
/// slightly darker fill.
struct SwitcherCardButtonStyle: ButtonStyle {
    let isSelected: Bool
    let highContrast: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let dark = colorScheme == .dark
        let fill: Color = configuration.isPressed
            ? (dark ? .white.opacity(0.18) : .black.opacity(0.12))
            : (isSelected ? (dark ? .white.opacity(0.12) : .black.opacity(0.07)) : .clear)

        configuration.label
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .controlAccentColor).opacity(0.75), lineWidth: 2.5)
                } else if highContrast {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
    }
}

/// The 46 pt rounded tile behind a Space's icon: an SF Symbol, an emoji, or (with no icon) the
/// Space's number in SF Rounded.
struct SwitcherIconTile: View {
    let icon: SpaceIcon?
    let number: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(dark ? Color.white.opacity(0.10) : Color.white)
                .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 0.5)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)

            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(Color(nsColor: .labelColor))
            case .emoji(let text):
                Text(text).font(.system(size: 26))
            case nil:
                Text("\(number)")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

// MARK: - Footer

struct SwitcherFooter: View {
    let twoRows: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                hint(twoRows ? "← → ↑ ↓" : "← →", "Select")
                hint("1–9", "Jump")
                hint("Return", "Switch")
                hint("Esc", "Close")
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, SwitcherLayout.panelPadding)
        .frame(height: SwitcherLayout.footerHeight)
        .accessibilityHidden(true)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            KeyCap(text: keys)
            Text(label)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
}

struct KeyCap: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
            )
    }
}
