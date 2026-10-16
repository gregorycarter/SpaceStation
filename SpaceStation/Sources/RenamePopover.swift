import SwiftUI
import AppKit

/// A single-line text field that selects its contents when it appears, limits its length, and
/// reports Return and Esc. (SwiftUI's TextField can't select its text on macOS 13.)
struct SelectingTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxLength: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.stringValue = text
        field.setAccessibilityLabel("Space name")
        // Focus after the popover is on screen, then select everything.
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectingTextField
        init(_ parent: SelectingTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if field.stringValue.count > parent.maxLength {
                field.stringValue = String(field.stringValue.prefix(parent.maxLength))
            }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

struct RenameView: View {
    let space: SpaceInfo
    @State private var draft: RenameDraft
    let onRename: (RenameDraft) -> Void
    let onCancel: () -> Void
    let onOpenCharacterPalette: () -> Void

    init(space: SpaceInfo, name: String, icon: SpaceIcon?,
         onRename: @escaping (RenameDraft) -> Void, onCancel: @escaping () -> Void,
         onOpenCharacterPalette: @escaping () -> Void) {
        self.space = space
        _draft = State(initialValue: RenameDraft(name: name, icon: icon))
        self.onRename = onRename
        self.onCancel = onCancel
        self.onOpenCharacterPalette = onOpenCharacterPalette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Space \(space.index)")
                .font(.system(size: 13, weight: .semibold))

            HStack(alignment: .top, spacing: 10) {
                IconWell(icon: draft.icon, size: 44, cornerRadius: 10, symbolSize: 24, emojiSize: 22)

                VStack(alignment: .trailing, spacing: 4) {
                    SelectingTextField(text: Binding(get: { draft.name }, set: { draft.setName($0) }),
                                       placeholder: SpaceNameRules.defaultName(index: space.index),
                                       maxLength: SpaceNameRules.maxLength,
                                       onSubmit: submit, onCancel: onCancel)
                        .frame(height: 22)
                    Text("\(draft.name.count) / \(SpaceNameRules.maxLength)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .fixedSize()
                }
            }

            IconPickerView(icon: draft.icon, onChange: { draft.icon = $0 },
                           onOpenCharacterPalette: onOpenCharacterPalette)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isChanged)
            }
        }
        .padding(14)
        .frame(width: 316)
    }

    private func submit() {
        guard draft.isChanged else { return }
        onRename(draft)
    }
}

/// Shows the rename popover under the menu bar item.
@MainActor
final class RenamePopoverController: NSObject, NSPopoverDelegate {
    static let shared = RenamePopoverController()

    private var popover: NSPopover?

    func show(space: SpaceInfo, anchor: NSView?, nameManager: SpaceNameManager, fallback: () -> Void) {
        guard let anchor, anchor.window != nil else {
            fallback()
            return
        }
        popover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self

        let view = RenameView(
            space: space,
            name: nameManager.hasCustomName(for: space) ? nameManager.name(for: space) : "",
            icon: nameManager.icon(for: space),
            onRename: { [weak popover] draft in
                nameManager.setName(draft.normalizedName, for: space)
                nameManager.setIcon(draft.icon, for: space)
                popover?.close()
            },
            onCancel: { [weak popover] in popover?.close() },
            onOpenCharacterPalette: { [weak popover] in
                // The Character Viewer takes focus, which would dismiss a transient popover.
                popover?.behavior = .applicationDefined
                NSApp.orderFrontCharacterPalette(nil)
            })
        popover.contentViewController = NSHostingController(rootView: view)
        self.popover = popover

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}
