import Carbon
import ClipboardCore

/// Carbon 全局热键。不需要辅助功能权限。
final class HotkeyCenter {
    private static let signature: OSType = 0x4348_5354 // "CHST"

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    @discardableResult
    func register(_ config: HotkeyConfig) -> Bool {
        unregister()
        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue().fire()
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
            guard status == noErr else {
                Log.debug("hotkey handler install failed: \(status)")
                return false
            }
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(config.keyCode, config.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            Log.debug("hotkey \(config.displayString) register failed: \(status)")
            return false
        }
        Log.debug("hotkey \(config.displayString) registered")
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func fire() {
        DispatchQueue.main.async { [action] in action() }
    }
}
