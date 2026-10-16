import SwiftUI
import AppKit

/// A field that records a keyboard shortcut: click it, then press the combination.
/// Esc cancels. Combinations without Control, Option or Command are refused (except function
/// keys), because a bare letter or Shift+letter would swallow ordinary typing system-wide.
struct KeyRecorderField: NSViewRepresentable {
    let binding: KeyBinding?
    let onChange: (KeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = onChange
        view.binding = binding
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onChange = onChange
        view.binding = binding
    }

    final class RecorderView: NSView {
        var onChange: ((KeyBinding) -> Void)?
        var binding: KeyBinding? { didSet { needsDisplay = true } }
        private var isRecording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        override var intrinsicContentSize: NSSize { NSSize(width: 128, height: 22) }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            focusRingType = .exterior
            setAccessibilityRole(.button)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func becomeFirstResponder() -> Bool {
            isRecording = true
            return true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isRecording ? 1.5 : 0.5
            path.stroke()

            let text: String
            let color: NSColor
            if isRecording {
                text = "Type shortcut"
                color = .secondaryLabelColor
            } else if let binding {
                text = binding.display
                color = .labelColor
            } else {
                text = "Click to record"
                color = .secondaryLabelColor
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: color,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: 8, y: (bounds.height - size.height) / 2), withAttributes: attributes)
            setAccessibilityLabel("Keyboard shortcut")
            setAccessibilityValue(binding?.display ?? "None")
        }

        // Command combinations arrive as key equivalents before keyDown.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            isRecording ? capture(event) : false
        }

        override func keyDown(with event: NSEvent) {
            if !(isRecording && capture(event)) { super.keyDown(with: event) }
        }

        private func capture(_ event: NSEvent) -> Bool {
            let code = CGKeyCode(event.keyCode)
            if code == 53 {   // Esc cancels
                window?.makeFirstResponder(nil)
                return true
            }
            let relevant: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
                | CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue) & relevant)
            guard ShortcutValidation.isAcceptable(keyCode: code, flags: flags) else {
                NSSound.beep()
                return true
            }
            onChange?(KeyBinding(keyCode: code, flags: flags))
            window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// The recorder with a clear button, as used in Settings.
struct ShortcutRecorderControl: View {
    @Binding var shortcut: KeyBinding?

    var body: some View {
        ZStack(alignment: .trailing) {
            KeyRecorderField(binding: shortcut) { shortcut = $0 }
                .frame(width: 128, height: 22)
            if shortcut != nil {
                Button(action: { shortcut = nil }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)
                .help("Turn the shortcut off")
                .accessibilityLabel("Clear keyboard shortcut")
            }
        }
    }
}
