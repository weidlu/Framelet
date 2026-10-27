import Carbon

@MainActor final class HotKeys {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    var onTrigger: ((UInt32) -> Void)?
    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let keys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { keys.onTrigger?(id.id) }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return false }
        var success = true
        for (id, key) in [(UInt32(1),UInt32(kVK_ANSI_4)),(UInt32(2),UInt32(kVK_ANSI_3))] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x46524D4C, id: id), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references.append(reference) } else { success = false }
        }
        return success
    }
    deinit {
        for reference in references { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
