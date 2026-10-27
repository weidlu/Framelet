import AppKit
import Carbon.HIToolbox
import FrameletCore

/// Registers global hot keys through Carbon and translates recorded key events
/// into `HotKeyCombo` values. Registration is transactional: a failed rebind
/// keeps the previous binding working and reports the specific reason.
@MainActor final class HotKeyRegistry {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum RebindError: LocalizedError {
        case occupiedBy(CaptureAction)
        case carbonFailure(String)
        case invalidCombo
        var errorDescription: String? {
            switch self {
            case .occupiedBy(let other): return "该组合已被「\(other.title)」使用。"
            case .carbonFailure(let reason): return "系统未能注册该组合（\(reason)）。请换一个组合。"
            case .invalidCombo: return "全局快捷键需要包含 Command、Control 或 Option。"
            }
        }
    }

    private var handler: EventHandlerRef?
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var current: [CaptureAction: HotKeyCombo?] = [:]
    var onTrigger: ((CaptureAction) -> Void)?
    private let signature: OSType = 0x46524D4C // "FRML"

    /// Installs or refreshes the event handler and (re)registers every action.
    /// Returns failures keyed by action; actions that failed keep working via
    /// other means (menu bar / status item).
    @discardableResult
    func registerAll(_ shortcuts: [CaptureAction: HotKeyCombo?]) -> [CaptureAction: String] {
        current = shortcuts
        var failures: [CaptureAction: String] = [:]
        installHandlerIfNeeded()
        // Unregister everything we own, then register fresh (no duplicates).
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll()
        let ordered = CaptureAction.allCases
        for action in ordered {
            guard let combo = shortcuts[action] ?? nil, combo.isValidGlobal else { continue }
            var reference: EventHotKeyRef?
            let id = UInt32(ordered.firstIndex(of: action)! + 1)
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                             EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                references[id] = reference
            } else {
                failures[action] = Self.carbonDescription(status)
            }
        }
        return failures
    }

    /// Rebinds a single action transactionally. `combo == nil` clears it.
    func rebind(action: CaptureAction, to combo: HotKeyCombo?) throws {
        guard let combo, combo.isValidGlobal else { throw RebindError.invalidCombo }
        if let conflict = current.first(where: { $0.key != action && $0.value == combo })?.key {
            throw RebindError.occupiedBy(conflict)
        }
        let old = current[action] ?? nil
        // Transaction: unregister old, register new, restore old on failure.
        if let oldRef = references[Self.id(for: action)] {
            UnregisterEventHotKey(oldRef); references.removeValue(forKey: Self.id(for: action))
        }
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                         EventHotKeyID(signature: signature, id: Self.id(for: action)),
                                         GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference {
            references[Self.id(for: action)] = reference
            current[action] = combo
        } else {
            // Restore the previous binding so it remains usable.
            if let old, old.isValidGlobal {
                var restored: EventHotKeyRef?
                let restoreStatus = RegisterEventHotKey(old.keyCode, old.modifiers,
                                                        EventHotKeyID(signature: signature, id: Self.id(for: action)),
                                                        GetApplicationEventTarget(), 0, &restored)
                if restoreStatus == noErr, let restored { references[Self.id(for: action)] = restored }
            }
            throw RebindError.carbonFailure(Self.carbonDescription(status))
        }
    }

    func clear(action: CaptureAction) {
        if let ref = references[Self.id(for: action)] { UnregisterEventHotKey(ref); references.removeValue(forKey: Self.id(for: action)) }
        current[action] = nil
    }

    private static func id(for action: CaptureAction) -> UInt32 { actionID(for: action) }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if result != noErr { handler = nil }
    }

    func unregisterAll() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll()
        if let existing = handler { RemoveEventHandler(existing); handler = nil }
    }

    deinit {
        for reference in references.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static func carbonDescription(_ status: OSStatus) -> String {
        switch status {
        case -9877: return "组合已被其他应用占用"
        case noErr: return ""
        default: return "错误码 \(status)"
        }
    }
}

/// C callback for Carbon hot keys; must not capture context, so it is a
/// top-level function.
private func hotKeyHandler(_ callRef: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let registry = Unmanaged<HotKeyRegistry>.fromOpaque(context).takeUnretainedValue()
    let action = CaptureAction.allCases.first { actionID(for: $0) == id.id }
    if let action { DispatchQueue.main.async { registry.onTrigger?(action) } }
    return noErr
}

private func actionID(for action: CaptureAction) -> UInt32 {
    UInt32((CaptureAction.allCases.firstIndex(of: action) ?? 0) + 1)
}

/// Converts `NSEvent` modifiers to Carbon modifier bits and formats a combo for
/// display using the current keyboard layout.
enum HotKeyFormat {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= HotKeyModifier.command.rawValue }
        if flags.contains(.option) { value |= HotKeyModifier.option.rawValue }
        if flags.contains(.control) { value |= HotKeyModifier.control.rawValue }
        if flags.contains(.shift) { value |= HotKeyModifier.shift.rawValue }
        return value
    }

    static func display(_ combo: HotKeyCombo) -> String {
        var parts: [String] = []
        if combo.modifiers & HotKeyModifier.control.rawValue != 0 { parts.append("⌃") }
        if combo.modifiers & HotKeyModifier.option.rawValue != 0 { parts.append("⌥") }
        if combo.modifiers & HotKeyModifier.shift.rawValue != 0 { parts.append("⇧") }
        if combo.modifiers & HotKeyModifier.command.rawValue != 0 { parts.append("⌘") }
        parts.append(keyName(combo.keyCode))
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "键\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        let keyboardLayout = UnsafeRawPointer(CFDataGetBytePtr(data))
            .assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(keyboardLayout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return "键\(keyCode)" }
        let string = String(utf16CodeUnits: chars, count: length)
        if string.isEmpty { return "键\(keyCode)" }
        return string.uppercased()
    }

    /// Standard symbols for keys that `UCKeyTranslate` reports empty for.
    private static let specialKeys: [Int: String] = [
        36: "↩", 76: "⌅", 48: "⇥", 51: "⌫", 53: "⎋", 49: "Space",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        117: "⌦", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
