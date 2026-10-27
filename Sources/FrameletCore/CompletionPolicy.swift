import Foundation

/// Pure description of what a completion action does. Keeping this out of the
/// overlay makes the "copy / save / pin / exit" matrix testable and guarantees
/// the settings UI, tooltips and actual behaviour share one source of truth.
public enum CompletionStep: Equatable {
    /// Write the encoded image to the pasteboard.
    case copyToPasteboard
    /// Write a file into the configured save directory.
    case saveToDefaultDirectory
    /// Ask the user for a path with a save panel.
    case saveWithPanel
    /// Open a floating pinned window.
    case pin
    /// End the capture session.
    case exitSession
}

public enum CompletionPlanner {
    /// Steps for the "完成" action (button, Enter, double-click follow).
    public static func steps(for action: CompletionAction, copyOnSave: Bool, copyOnPin: Bool) -> [CompletionStep] {
        switch action {
        case .copy:
            return [.copyToPasteboard, .exitSession]
        case .save:
            return (copyOnSave ? [CompletionStep.saveToDefaultDirectory, .copyToPasteboard] : [.saveToDefaultDirectory]) + [.exitSession]
        case .saveAndCopy:
            return [.saveToDefaultDirectory, .copyToPasteboard, .exitSession]
        case .pin:
            return (copyOnPin ? [CompletionStep.copyToPasteboard] : []) + [.pin, .exitSession]
        }
    }

    /// Steps for the explicit "保存" toolbar action, which always opens a panel.
    public static func savePanelSteps(copyOnSave: Bool) -> [CompletionStep] {
        (copyOnSave ? [CompletionStep.saveWithPanel, .copyToPasteboard] : [.saveWithPanel]) + [.exitSession]
    }

    /// Steps for Cmd+C, which copies but deliberately keeps the session alive.
    public static func copyOnlySteps() -> [CompletionStep] { [.copyToPasteboard] }

    /// Whether a double-click should run the completion action.
    public static func doubleClickCompletes(_ action: DoubleClickAction) -> Bool {
        action == .followCompletion
    }
}
