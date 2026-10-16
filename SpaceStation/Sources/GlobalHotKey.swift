import Carbon.HIToolbox
import CoreGraphics
import os.log

extension KeyBinding {
    /// The modifier bits Carbon's RegisterEventHotKey expects.
    var carbonModifiers: Int {
        var result = 0
        if flags.contains(.maskControl) { result |= controlKey }
        if flags.contains(.maskAlternate) { result |= optionKey }
        if flags.contains(.maskShift) { result |= shiftKey }
        if flags.contains(.maskCommand) { result |= cmdKey }
        return result
    }
}

/// Registers a single system-wide hotkey using the public Carbon API.
/// This needs no Accessibility or Input Monitoring permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "GlobalHotKey")

    /// - Parameters:
    ///   - keyCode: a virtual key code (e.g. `kVK_ANSI_S`)
    ///   - modifiers: Carbon modifier flags (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`)
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard status == noErr else {
            logger.error("InstallEventHandler failed: \(status)")
            return nil
        }

        let id = EventHotKeyID(signature: OSType(0x53505354) /* 'SPST' */, id: 1)
        let registerStatus = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            // e.g. another app already owns this combination
            logger.error("RegisterEventHotKey failed: \(registerStatus)")
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
