import Foundation

/// Carbon `modifiers` bit values. Kept in FrameletCore so the settings model
/// and its validation stay GUI-free and testable.
public enum HotKeyModifier: UInt32 {
    case command = 0x0100 // cmdKey
    case shift   = 0x0200 // shiftKey
    case option  = 0x0800 // optionKey
    case control = 0x1000 // controlKey
}

/// A user-recordable key combination. Global shortcuts require at least one of
/// Command/Control/Option; session tool keys may be bare characters.
public struct HotKeyCombo: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32 = 0) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    public var hasCommand: Bool { modifiers & HotKeyModifier.command.rawValue != 0 }
    public var hasControl: Bool { modifiers & HotKeyModifier.control.rawValue != 0 }
    public var hasOption: Bool { modifiers & HotKeyModifier.option.rawValue != 0 }
    public var hasShift: Bool { modifiers & HotKeyModifier.shift.rawValue != 0 }
    public var hasRequiredModifier: Bool { hasCommand || hasControl || hasOption }
    /// macOS virtual key code zero is the A key, not an empty shortcut.
    /// Absence is represented by Optional.none throughout the settings model.
    public var isRecordable: Bool { keyCode < 128 && !(54...63).contains(keyCode) }
    /// Global shortcut rule: at least one of Command/Control/Option, never a
    /// bare character or Shift-only combination.
    public var isValidGlobal: Bool { isRecordable && hasRequiredModifier }
    public var isBareKey: Bool { isRecordable && !hasCommand && !hasControl && !hasOption }
}

/// Global capture actions, keyed by a stable identifier.
public enum CaptureAction: String, Codable, CaseIterable, Identifiable {
    case region, fullscreen, window, lastRegion
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .region: return "区域截图"
        case .fullscreen: return "全屏截图"
        case .window: return "窗口截图"
        case .lastRegion: return "上次区域截图"
        }
    }
}

/// What the "完成" action does.
public enum CompletionAction: String, Codable, CaseIterable, Identifiable {
    case copy, save, saveAndCopy, pin
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .copy: return "复制"
        case .save: return "保存文件"
        case .saveAndCopy: return "保存并复制"
        case .pin: return "贴图"
        }
    }
}

/// What a double-click on the selection does while in move/selection state.
public enum DoubleClickAction: String, Codable, CaseIterable, Identifiable {
    case followCompletion, none
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .followCompletion: return "跟随完成动作"
        case .none: return "无动作"
        }
    }
}

public enum SaveFormat: String, Codable, CaseIterable, Identifiable {
    case png, jpeg
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
    public var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
}

/// Session-internal tool keys (no modifier). Bare characters only.
public enum ToolKeyAction: String, Codable, CaseIterable, Identifiable {
    case move, rectangle, ellipse, arrow, pen, mosaic, text, redact, pin, ocr
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .move: return "移动选区"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        case .redact: return "遮挡"
        case .pin: return "贴图"
        case .ocr: return "提取文字"
        }
    }
}

/// RGB color for annotation defaults, kept UI-framework-free.
public struct RGBValue: Codable, Equatable, Hashable {
    public var red: Double, green: Double, blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    public static let defaultInk = RGBValue(red: 0.90, green: 0.24, blue: 0.25)
}

/// Remembered region for the "last region" global shortcut. `selection` and
/// `screenFrame` are in AppKit global display coordinates (bottom-left origin).
public struct LastRegion: Codable, Equatable {
    public var displayID: UInt32
    public var screenFrame: CGRect
    public var selection: CGRect
    public init(displayID: UInt32, screenFrame: CGRect, selection: CGRect) {
        self.displayID = displayID; self.screenFrame = screenFrame; self.selection = selection
    }
}

/// Typed, validated settings model. Persisted through `AppSettingsStore` in the
/// app target; this type stays pure so the checks executable can validate it.
public struct AppSettings: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var completionAction: CompletionAction
    public var doubleClickAction: DoubleClickAction
    public var copyOnSave: Bool
    public var copyOnPin: Bool
    public var saveFormat: SaveFormat
    public var jpegQuality: Double
    public var saveDirectoryPath: String
    public var globalShortcuts: [CaptureAction: HotKeyCombo?]
    public var toolShortcuts: [ToolKeyAction: HotKeyCombo?]
    public var strokeWidth: Double
    public var fontSize: Double
    public var annotationColor: RGBValue
    public var lastRegion: LastRegion?
    // Optional so preferences saved before this setting existed still decode.
    public var selectionCornerRadius: Double?
    /// AppKit points; zero preserves square corners. Old preferences default to 16.
    public var effectiveSelectionCornerRadius: Double { min(32, max(0, selectionCornerRadius ?? 16)) }

    public init(schemaVersion: Int = AppSettings.currentSchemaVersion,
                completionAction: CompletionAction = .copy,
                doubleClickAction: DoubleClickAction = .followCompletion,
                copyOnSave: Bool = true,
                copyOnPin: Bool = true,
                saveFormat: SaveFormat = .png,
                jpegQuality: Double = 0.92,
                saveDirectoryPath: String = AppSettings.defaultSaveDirectory,
                globalShortcuts: [CaptureAction: HotKeyCombo?] = AppSettings.defaultGlobalShortcuts,
                toolShortcuts: [ToolKeyAction: HotKeyCombo?] = AppSettings.defaultToolShortcuts,
                strokeWidth: Double = 5,
                fontSize: Double = 16,
                annotationColor: RGBValue = .defaultInk,
                lastRegion: LastRegion? = nil,
                selectionCornerRadius: Double? = 16) {
        self.schemaVersion = schemaVersion
        self.completionAction = completionAction
        self.doubleClickAction = doubleClickAction
        self.copyOnSave = copyOnSave
        self.copyOnPin = copyOnPin
        self.saveFormat = saveFormat
        self.jpegQuality = jpegQuality
        self.saveDirectoryPath = saveDirectoryPath
        self.globalShortcuts = globalShortcuts
        self.toolShortcuts = toolShortcuts
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.annotationColor = annotationColor
        self.lastRegion = lastRegion
        self.selectionCornerRadius = selectionCornerRadius
    }

    public static let defaults = AppSettings()

    public static var defaultSaveDirectory: String {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let base = pictures?.path ?? NSHomeDirectory()
        return (base as NSString).appendingPathComponent("Framelet")
    }

    public static let defaultGlobalShortcuts: [CaptureAction: HotKeyCombo?] = [
        .region: HotKeyCombo(keyCode: 0x15, modifiers: HotKeyModifier.control.rawValue | HotKeyModifier.option.rawValue), // ⌃⌥4
        .fullscreen: HotKeyCombo(keyCode: 0x14, modifiers: HotKeyModifier.control.rawValue | HotKeyModifier.option.rawValue), // ⌃⌥3
        .window: nil,
        .lastRegion: nil,
    ]

    public static let defaultToolShortcuts: [ToolKeyAction: HotKeyCombo?] = [
        .rectangle: HotKeyCombo(keyCode: 0x12), // 1
        .ellipse: HotKeyCombo(keyCode: 0x13),   // 2
        .arrow: HotKeyCombo(keyCode: 0x14),     // 3
        .pen: HotKeyCombo(keyCode: 0x15),       // 4
        .mosaic: HotKeyCombo(keyCode: 0x17),    // 5
        .text: HotKeyCombo(keyCode: 0x16),      // 6
        .redact: HotKeyCombo(keyCode: 0x1A),    // 7
        .move: HotKeyCombo(keyCode: 0x09),      // V
        .pin: HotKeyCombo(keyCode: 0x11),       // T
        .ocr: HotKeyCombo(keyCode: 0x1F),       // O
    ]

    public static func from(data: Data) -> AppSettings? {
        guard let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return nil }
        return decoded.repaired
    }

    public func encode() -> Data? { try? JSONEncoder().encode(self) }

    /// Returns `self` with invalid or duplicate global/tool shortcuts removed,
    /// out-of-range numeric values clamped, and schema-version reset to current.
    /// Never throws, so corrupt or unknown values fall back to safe defaults
    /// instead of crashing at launch.
    public var repaired: AppSettings {
        var copy = self
        copy.schemaVersion = AppSettings.currentSchemaVersion
        copy.jpegQuality = min(max(copy.jpegQuality, 0.05), 1.0)
        copy.strokeWidth = min(max(copy.strokeWidth, 2), 24)
        copy.fontSize = min(max(copy.fontSize, 8), 64)
        if let radius = copy.selectionCornerRadius { copy.selectionCornerRadius = min(max(radius, 0), 32) }
        copy.annotationColor.red = min(max(copy.annotationColor.red, 0), 1)
        copy.annotationColor.green = min(max(copy.annotationColor.green, 0), 1)
        copy.annotationColor.blue = min(max(copy.annotationColor.blue, 0), 1)
        var globalSeen = Set<HotKeyCombo>()
        for action in CaptureAction.allCases {
            guard let combo = copy.globalShortcuts[action] ?? nil else { continue }
            if !combo.isValidGlobal || globalSeen.contains(combo) {
                copy.globalShortcuts[action] = nil
            } else {
                globalSeen.insert(combo)
            }
        }
        var toolSeen = Set<HotKeyCombo>()
        for action in ToolKeyAction.allCases {
            guard let combo = copy.toolShortcuts[action] ?? nil else { continue }
            if !combo.isBareKey || toolSeen.contains(combo) {
                copy.toolShortcuts[action] = nil
            } else {
                toolSeen.insert(combo)
            }
        }
        return copy
    }
}
