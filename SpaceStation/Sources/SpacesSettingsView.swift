import SwiftUI

struct SpacesSettingsView: View {
    @ObservedObject var nameManager: SpaceNameManager
    @ObservedObject var spaceTracker: SpaceTracker

    @State private var showResetConfirmation = false

    static let rowHeight: CGFloat = 38

    /// Window height for `count` Spaces: grows with the list up to a scrolling limit.
    static func height(spaceCount: Int) -> CGFloat {
        min(max(CGFloat(spaceCount) * rowHeight + 150, 300), 640)
    }

    var body: some View {
        Form {
            Section {
                ForEach(spaceTracker.spaces) { space in
                    SpaceRow(space: space,
                             isCurrent: !spaceTracker.isInFullscreenSpace && space.index == spaceTracker.currentSpaceIndex,
                             nameManager: nameManager)
                        .frame(height: Self.rowHeight - 12)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            } footer: {
                HStack(alignment: .top) {
                    Text("Click an icon to choose a symbol or emoji. Clear a name to go back to the macOS default.")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Reset All…") { showResetConfirmation = true }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset all Space names and icons?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) { nameManager.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Space goes back to its macOS default name and the number icon. This can't be undone.")
        }
    }
}

private struct SpaceRow: View {
    let space: SpaceInfo
    let isCurrent: Bool
    @ObservedObject var nameManager: SpaceNameManager

    @State private var showIconPicker = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(space.index)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 14, alignment: .trailing)

            Button(action: { showIconPicker = true }) {
                IconWell(icon: nameManager.icon(for: space))
            }
            .buttonStyle(.plain)
            .help("Choose an icon")
            .accessibilityLabel("Icon for Space \(space.index)")
            .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                IconPickerView(icon: nameManager.icon(for: space)) { nameManager.setIcon($0, for: space) }
                    .padding(14)
                    .frame(width: 316)
            }

            SpaceNameField(space: space, nameManager: nameManager)

            if isCurrent {
                Text("Current")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .fixedSize()
            }
        }
    }
}

/// A name that reads as plain text until focused, then shows a field bezel and a character
/// counter. Return or leaving the field commits; Esc reverts.
private struct SpaceNameField: View {
    let space: SpaceInfo
    @ObservedObject var nameManager: SpaceNameManager

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        // `prompt` is the placeholder; a plain title would be shown as a row label in a Form.
        TextField("Name", text: Binding(
            get: { draft },
            set: { draft = String($0.prefix(SpaceNameManager.maxNameLength)) }
        ), prompt: Text("Desktop \(space.index)"))
        .labelsHidden()
        .textFieldStyle(.plain)
        .focused($isFocused)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .padding(.trailing, isFocused ? 44 : 0)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isFocused ? Color(nsColor: .textBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isFocused ? Color(nsColor: .controlAccentColor) : Color.clear, lineWidth: isFocused ? 1.5 : 0)
        )
        .overlay(alignment: .trailing) {
            if isFocused {
                Text("\(draft.count) / \(SpaceNameManager.maxNameLength)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .fixedSize()
                    .padding(.trailing, 8)
            }
        }
        .onSubmit(commit)
        .onExitCommand {
            draft = storedName
            isFocused = false
        }
        .onAppear { draft = storedName }
        .onChange(of: isFocused) { focused in
            if !focused { commit() }
        }
        .onChange(of: storedName) { newValue in
            // Renamed elsewhere (the menu's rename popover, Reset All): follow it unless editing.
            if !isFocused { draft = newValue }
        }
        .accessibilityLabel("Name of Space \(space.index)")
    }

    private var storedName: String {
        nameManager.hasCustomName(for: space) ? nameManager.name(for: space) : ""
    }

    private func commit() {
        nameManager.setName(draft, for: space)
        draft = storedName
    }
}
