import AppKit
import Carbon

final class Shortcut {
    var onStep: ((Int) -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private(set) var active = false

    func start() throws {
        guard !active else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<Shortcut>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4342544B else { return OSStatus(eventNotHandledErr) }
            shortcut.onStep?(id.id == 1 ? 1 : -1)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw EngineError.failed("Could not install the shortcut handler (\(status)).") }
        for (id, mods) in [(UInt32(1), UInt32(cmdKey)), (UInt32(2), UInt32(cmdKey | shiftKey))] {
            var ref: EventHotKeyRef?
            // Shared registration also lets Stage Manager switch focus before our selection is committed.
            let result = RegisterEventHotKey(UInt32(kVK_ANSI_Grave), mods,
                EventHotKeyID(signature: 0x4342544B, id: id), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
            guard result == noErr, let ref else {
                stop()
                throw EngineError.failed("Command–` is already registered or unavailable (\(result)). Disable other apps using this shortcut, then enable CommandBacktick again.")
            }
            keys.append(ref)
        }
        active = true
    }
    func stop() {
        keys.forEach { UnregisterEventHotKey($0) }; keys = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
        active = false
    }
    static var commandHeld: Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Command)) ||
            CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_RightCommand))
    }
    static var escapeHeld: Bool { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Escape)) }
    deinit { stop() }
}
