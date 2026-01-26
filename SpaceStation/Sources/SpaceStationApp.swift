import SwiftUI

@main
struct SpaceStationApp: App {
    @StateObject private var spaceTracker = SpaceTracker()
    @StateObject private var nameManager = SpaceNameManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(spaceTracker: spaceTracker, nameManager: nameManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                Text(nameManager.name(for: spaceTracker.currentSpaceIndex))
                    .font(.system(.body, design: .rounded))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(nameManager: nameManager)
        }
    }
}
