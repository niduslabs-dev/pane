import Carbon.HIToolbox

/// Maps Mac keyboard input to what the emulator's `KeyboardEvent` takes.
///
/// Keys that don't type text go by W3C key name with key down and key up, as Android Studio
/// sends them (`DomKeyNames`). Everything else is sent as typed text, so the Mac's keyboard
/// layout and dead keys decide the character.
public enum KeyMapping {
    /// The W3C name for a Mac virtual key code that doesn't type text, or nil.
    public static func keyName(macKeyCode: UInt16) -> String? {
        switch Int(macKeyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: "Enter"
        case kVK_Tab: "Tab"
        case kVK_Delete: "Backspace"
        case kVK_Escape: "Escape"
        case kVK_ForwardDelete: "Delete"
        case kVK_Home: "Home"
        case kVK_End: "End"
        case kVK_PageUp: "PageUp"
        case kVK_PageDown: "PageDown"
        case kVK_LeftArrow: "ArrowLeft"
        case kVK_RightArrow: "ArrowRight"
        case kVK_DownArrow: "ArrowDown"
        case kVK_UpArrow: "ArrowUp"
        default: nil
        }
    }

    /// Text worth typing: printable characters only, no control or function-key characters
    /// (AppKit puts arrows and the like in the private-use area).
    public static func typedText(_ characters: String) -> String? {
        let privateUse: ClosedRange<UInt32> = 0xF700...0xF8FF
        let printable = characters.unicodeScalars.filter {
            !$0.properties.generalCategory.isControl && !privateUse.contains($0.value)
        }
        guard !printable.isEmpty else { return nil }
        return String(String.UnicodeScalarView(printable))
    }
}

extension Unicode.GeneralCategory {
    fileprivate var isControl: Bool {
        switch self {
        case .control, .format, .surrogate, .privateUse, .unassigned: true
        default: false
        }
    }
}
