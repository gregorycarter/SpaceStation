import SwiftUI

/// A row in a settings form that flags a problem: a yellow warning triangle, a title, an
/// explanation and an action.
struct SettingsWarningRow<Actions: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: .systemYellow))
                .font(.system(size: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) { actions() }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

/// A label on the left and a control on the right, vertically centred. (LabeledContent aligns on
/// the first text baseline, which misplaces custom controls that have none.)
struct SettingsRow<Content: View>: View {
    let label: String
    var minHeight: CGFloat = 28
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: minHeight)
    }
}

extension View {
    /// Footers sit under their group, left-aligned (grouped forms right-align plain footer text).
    func settingsFooter() -> some View {
        multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}
