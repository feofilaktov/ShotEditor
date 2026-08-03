import AppKit
import Carbon.HIToolbox

/// Minimal global hotkey registration via the Carbon Hot Key API.
/// (Still the simplest reliable way to get system-wide shortcuts without
/// Accessibility permissions.)
final class HotkeyManager {

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        installHandler()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            manager.registrations[hkID.id]?.handler()
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    /// Register a hotkey. `keyCode` is a virtual key code (kVK_ANSI_*).
    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1

        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x53484f54), id: id) // 'SHOT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            registrations[id] = Registration(ref: ref, handler: handler)
        } else {
            NSLog("Failed to register hotkey \(keyCode) (status \(status))")
        }
    }

    deinit {
        for (_, reg) in registrations { UnregisterEventHotKey(reg.ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
