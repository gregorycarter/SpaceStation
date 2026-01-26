import SwiftUI

struct MenuBarView: View {
    @ObservedObject var spaceTracker: SpaceTracker
    @ObservedObject var nameManager: SpaceNameManager
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var renamingSpaceIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header showing current space
            currentSpaceHeader

            Divider()
                .padding(.vertical, 8)

            // List of all spaces
            spacesList

            Divider()
                .padding(.vertical, 8)

            // Actions
            actionButtons
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var currentSpaceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Space")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text(nameManager.name(for: spaceTracker.currentSpaceIndex))
                    .font(.headline)

                Spacer()

                Button(action: { startRenaming(spaceTracker.currentSpaceIndex) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rename this space")
            }
        }
    }

    private var spacesList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All Spaces")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(1...max(spaceTracker.totalSpaces, 1), id: \.self) { index in
                spaceRow(for: index)
            }
        }
    }

    private func spaceRow(for index: Int) -> some View {
        HStack {
            // Active indicator
            if index == spaceTracker.currentSpaceIndex {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 6))
                    .foregroundColor(.secondary)
            }

            // Name (editable if renaming)
            if isRenaming && renamingSpaceIndex == index {
                TextField("Space name", text: $renameText, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
            } else {
                Text(nameManager.name(for: index))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(index == spaceTracker.currentSpaceIndex ? .primary : .secondary)
            }

            Spacer()

            // Keyboard shortcut hint
            Text("⌃\(index)")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.5))

            // Rename button
            if !isRenaming {
                Button(action: { startRenaming(index) }) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .opacity(0.6)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(index == spaceTracker.currentSpaceIndex ? Color.blue.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                spaceTracker.switchToSpace(index)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(action: openSettings) {
                Label("Settings", systemImage: "gear")
            }

            Spacer()

            Button(action: quitApp) {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }

    // MARK: - Actions

    private func startRenaming(_ index: Int) {
        renamingSpaceIndex = index
        renameText = nameManager.hasCustomName(for: index) ? nameManager.name(for: index) : ""
        isRenaming = true
    }

    private func commitRename() {
        if let index = renamingSpaceIndex {
            nameManager.setName(renameText, for: index)
        }
        isRenaming = false
        renamingSpaceIndex = nil
        renameText = ""
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    MenuBarView(
        spaceTracker: SpaceTracker(),
        nameManager: SpaceNameManager()
    )
}
