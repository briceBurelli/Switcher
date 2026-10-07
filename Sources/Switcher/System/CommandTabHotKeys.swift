import Carbon
import Foundation

/// ⌘Tab and ⌘⇧Tab as global hot keys. They start the switcher, and keep working where keyboard
/// event taps go deaf (password fields and other "secure input" moments).
@MainActor
final class CommandTabHotKeys {
    var onPress: ((_ backward: Bool) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func register() {
        guard hotKeyRefs.isEmpty else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                let backward = hotKeyID.id == 2
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        SwitcherController.shared.hotKeyPressed(backward: backward)
                    }
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        let signature = OSType(0x5357_5443) // 'SWTC'
        for (id, modifiers) in [(UInt32(1), cmdKey), (UInt32(2), cmdKey | shiftKey)] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(modifiers), EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
