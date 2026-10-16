import SwiftUI

/// The strip of Space cards shown by the switcher panel.
struct SwitcherView: View {
    let spaces: [SpaceInfo]
    let names: [String]
    let currentIndex: Int?     // nil while in a fullscreen Space
    let selectedIndex: Int
    let onPick: (SpaceInfo) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(spaces.enumerated()), id: \.element.id) { offset, space in
                    card(for: space, name: names[offset], isSelected: offset == selectedIndex)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func card(for space: SpaceInfo, name: String, isSelected: Bool) -> some View {
        let isCurrent = space.index == currentIndex
        let canSwitch = space.index <= SpaceTracker.maxSwitchableSpace

        return Button(action: { onPick(space) }) {
            VStack(spacing: 6) {
                Text("\(space.index)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(isCurrent ? Color.blue : Color.secondary))

                Text(name)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                Text(canSwitch ? "⌃\(space.index)" : "no shortcut")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 128, height: 92)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? Color.blue : (isSelected ? Color.accentColor : Color.clear), lineWidth: 2)
            )
            .contentShape(Rectangle())
            .opacity(canSwitch || isCurrent ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canSwitch && !isCurrent)
        .accessibilityLabel("\(name), Desktop \(space.index)\(isCurrent ? ", current" : "")")
    }
}
