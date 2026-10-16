import SwiftUI

/// A small screen illustration with a dot in each corner for choosing the hot corner. Corners that
/// macOS already uses are drawn dashed and can't be picked.
struct CornerMapView: View {
    let selected: HotCorner
    /// Corners macOS Hot Corners already use, with what they do.
    let inUse: [HotCorner: String]
    let onSelect: (HotCorner) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let corners: [HotCorner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            // The menu bar strip
            VStack(spacing: 0) {
                Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 5)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))

            ForEach(corners, id: \.self) { corner in
                dot(for: corner)
                    .position(position(of: corner))
            }
        }
        .frame(width: 84, height: 54)
        .accessibilityElement(children: .contain)
    }

    private func position(of corner: HotCorner) -> CGPoint {
        let x: CGFloat = (corner == .topLeft || corner == .bottomLeft) ? 11 : 73
        let y: CGFloat = (corner == .topLeft || corner == .topRight) ? 16 : 43
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func dot(for corner: HotCorner) -> some View {
        let isSelected = corner == selected
        let unavailable = inUse[corner] != nil
        Button(action: { onSelect(isSelected ? .off : corner) }) {
            ZStack {
                if isSelected {
                    Circle().fill(Color(nsColor: .controlAccentColor))
                    Circle().strokeBorder(Color.white, lineWidth: 1.5)
                } else if unavailable {
                    Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    Circle().fill(colorScheme == .dark ? Color.white.opacity(0.30) : Color.white.opacity(0.85))
                    Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
            .frame(width: 10, height: 10)
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable && !isSelected)
        .help(unavailable ? "\(corner.label) is used by macOS: \(inUse[corner] ?? "")" : corner.label)
        .accessibilityLabel(corner.label)
        .accessibilityValue(isSelected ? "selected" : (unavailable ? "unavailable" : ""))
    }
}
