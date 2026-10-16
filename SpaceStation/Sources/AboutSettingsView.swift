import SwiftUI

struct AboutSettingsView: View {
    static let repositoryURL = URL(string: "https://github.com/gregorycarter/SpaceStation")!

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("SpaceStation")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 16)

            Text(versionText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize()
                .padding(.top, 2)

            Text("Name your Spaces and switch between them from the menu bar, a shortcut or a hot corner.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 12)

            HStack(spacing: 10) {
                Button("View on GitHub") { NSWorkspace.shared.open(Self.repositoryURL) }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(Self.repositoryURL.appendingPathComponent("issues/new"))
                }
                .fixedSize()
            }
            .padding(.top, 20)

            HStack(spacing: 4) {
                Text("Open-source software (MIT) ·")
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                Link("License", destination: Self.repositoryURL.appendingPathComponent("blob/main/LICENSE"))
            }
            .font(.system(size: 11))
            .fixedSize()
            .padding(.top, 28)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
