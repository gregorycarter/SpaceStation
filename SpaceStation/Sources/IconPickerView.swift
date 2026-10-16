import SwiftUI

/// The Space icon chooser: Symbols, Emoji or Number (no custom icon).
struct IconPickerView: View {
    let icon: SpaceIcon?
    let onChange: (SpaceIcon?) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case symbols = "Symbols", emoji = "Emoji", number = "Number"
        var id: String { rawValue }
    }

    @State private var mode: Mode
    @State private var emojiText = ""

    init(icon: SpaceIcon?, onChange: @escaping (SpaceIcon?) -> Void) {
        self.icon = icon
        self.onChange = onChange
        switch icon {
        case .symbol: _mode = State(initialValue: .symbols)
        case .emoji: _mode = State(initialValue: .emoji)
        case nil: _mode = State(initialValue: .number)
        }
    }

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8)

    var body: some View {
        VStack(spacing: 12) {
            Picker("Icon type", selection: Binding(get: { mode }, set: { newMode in
                mode = newMode
                if newMode == .number { onChange(nil) }
            })) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .symbols: symbolGrid
            case .emoji: emojiEntry
            case .number: numberNote
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(SpaceIcon.symbolChoices, id: \.self) { name in
                let isSelected = icon == .symbol(name)
                Button(action: { onChange(.symbol(name)) }) {
                    Image(systemName: name)
                        .font(.system(size: 19))
                        .foregroundColor(isSelected ? .white : Color(nsColor: .labelColor))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color(nsColor: .controlAccentColor) : Color.clear))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var emojiEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Type or paste an emoji", text: $emojiText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyEmoji)
                Button("Use") { applyEmoji() }
                    .disabled(SpaceIcon.emoji(from: emojiText) == nil)
            }
            Button("Open Emoji & Symbols…") { NSApp.orderFrontCharacterPalette(nil) }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: emojiText) { _ in
            // Choosing from the Character Viewer inserts into the field; take the first emoji.
            if SpaceIcon.emoji(from: emojiText) != nil { applyEmoji() }
        }
    }

    private func applyEmoji() {
        if let chosen = SpaceIcon.emoji(from: emojiText) {
            onChange(chosen)
            emojiText = ""
        }
    }

    private var numberNote: some View {
        Text("No custom icon: the Space shows its number.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

/// The rounded tile that shows a Space's icon in Settings and the rename popover.
struct IconWell: View {
    let icon: SpaceIcon?
    var size: CGFloat = 26
    var cornerRadius: CGFloat = 6
    var symbolSize: CGFloat = 16
    var emojiSize: CGFloat = 15

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white)
                .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 0.5)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
            switch icon {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: symbolSize)).foregroundColor(Color(nsColor: .labelColor))
            case .emoji(let text):
                Text(text).font(.system(size: emojiSize))
            case nil:
                Image(systemName: "plus").font(.system(size: symbolSize * 0.8)).foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .frame(width: size, height: size)
    }
}
