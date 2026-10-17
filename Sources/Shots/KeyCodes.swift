import Carbon
import Cocoa

public enum KeyCodes {
    // MARK: - Modifier Conversions

    public static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if cocoaFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if cocoaFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if cocoaFlags.contains(.option) { mods |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    public static func cocoaModifiers(from carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonMods & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        if (carbonMods & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbonMods & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbonMods & UInt32(controlKey)) != 0 { flags.insert(.control) }
        return flags
    }

    public static func modifierSymbols(carbonMods: UInt32) -> String {
        var result = ""
        if (carbonMods & UInt32(controlKey)) != 0 { result += "⌃" }
        if (carbonMods & UInt32(optionKey)) != 0 { result += "⌥" }
        if (carbonMods & UInt32(shiftKey)) != 0 { result += "⇧" }
        if (carbonMods & UInt32(cmdKey)) != 0 { result += "⌘" }
        return result
    }

    public static func modifierSymbols(cocoaFlags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if cocoaFlags.contains(.control) { result += "⌃" }
        if cocoaFlags.contains(.option) { result += "⌥" }
        if cocoaFlags.contains(.shift) { result += "⇧" }
        if cocoaFlags.contains(.command) { result += "⌘" }
        return result
    }

    public static let noKey: UInt16 = 0xFFFF

    public static func isShortcutAssigned(keyCode: UInt16, carbonMods: UInt32) -> Bool {
        return keyCode != noKey && carbonMods != 0
    }

    public static func shortcutString(keyCode: UInt16, carbonMods: UInt32) -> String {
        guard isShortcutAssigned(keyCode: keyCode, carbonMods: carbonMods) else {
            return "None"
        }
        let mods = modifierSymbols(carbonMods: carbonMods)
        let key = keyName(for: keyCode)
        return mods + key
    }

    // MARK: - Key Names

    public static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        // ANSI Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        // ANSI Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Symbols
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"

        // Keypad
        case kVK_ANSI_KeypadDecimal: return "Num ."
        case kVK_ANSI_KeypadMultiply: return "Num *"
        case kVK_ANSI_KeypadPlus: return "Num +"
        case kVK_ANSI_KeypadClear: return "Num Clear"
        case kVK_ANSI_KeypadDivide: return "Num /"
        case kVK_ANSI_KeypadEnter: return "Num Enter"
        case kVK_ANSI_KeypadMinus: return "Num -"
        case kVK_ANSI_KeypadEquals: return "Num ="
        case kVK_ANSI_Keypad0: return "Num 0"
        case kVK_ANSI_Keypad1: return "Num 1"
        case kVK_ANSI_Keypad2: return "Num 2"
        case kVK_ANSI_Keypad3: return "Num 3"
        case kVK_ANSI_Keypad4: return "Num 4"
        case kVK_ANSI_Keypad5: return "Num 5"
        case kVK_ANSI_Keypad6: return "Num 6"
        case kVK_ANSI_Keypad7: return "Num 7"
        case kVK_ANSI_Keypad8: return "Num 8"
        case kVK_ANSI_Keypad9: return "Num 9"

        // Control / Navigation
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"

        // Function keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"

        default:
            return "Key(\(keyCode))"
        }
    }

    // MARK: - Menu Key Equivalents

    public static func keyEquivalent(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        // ANSI Letters (lowercase for NSMenuItem keyEquivalent)
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"

        // ANSI Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Symbols
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"

        // Control / Navigation
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case kVK_Delete: return deleteEquivalent
        case kVK_ForwardDelete: return forwardDeleteEquivalent
        case kVK_Escape: return escapeEquivalent

        // Function keys F1...F12
        case kVK_F1: return f1Equivalent
        case kVK_F2: return f2Equivalent
        case kVK_F3: return f3Equivalent
        case kVK_F4: return f4Equivalent
        case kVK_F5: return f5Equivalent
        case kVK_F6: return f6Equivalent
        case kVK_F7: return f7Equivalent
        case kVK_F8: return f8Equivalent
        case kVK_F9: return f9Equivalent
        case kVK_F10: return f10Equivalent
        case kVK_F11: return f11Equivalent
        case kVK_F12: return f12Equivalent

        default:
            return ""
        }
    }

    private static let deleteEquivalent = String(utf16CodeUnits: [UInt16(NSBackspaceCharacter)], count: 1)
    private static let forwardDeleteEquivalent = String(utf16CodeUnits: [UInt16(NSDeleteCharacter)], count: 1)
    private static let escapeEquivalent = "\u{1b}"
    private static let f1Equivalent = String(utf16CodeUnits: [UInt16(NSF1FunctionKey)], count: 1)
    private static let f2Equivalent = String(utf16CodeUnits: [UInt16(NSF2FunctionKey)], count: 1)
    private static let f3Equivalent = String(utf16CodeUnits: [UInt16(NSF3FunctionKey)], count: 1)
    private static let f4Equivalent = String(utf16CodeUnits: [UInt16(NSF4FunctionKey)], count: 1)
    private static let f5Equivalent = String(utf16CodeUnits: [UInt16(NSF5FunctionKey)], count: 1)
    private static let f6Equivalent = String(utf16CodeUnits: [UInt16(NSF6FunctionKey)], count: 1)
    private static let f7Equivalent = String(utf16CodeUnits: [UInt16(NSF7FunctionKey)], count: 1)
    private static let f8Equivalent = String(utf16CodeUnits: [UInt16(NSF8FunctionKey)], count: 1)
    private static let f9Equivalent = String(utf16CodeUnits: [UInt16(NSF9FunctionKey)], count: 1)
    private static let f10Equivalent = String(utf16CodeUnits: [UInt16(NSF10FunctionKey)], count: 1)
    private static let f11Equivalent = String(utf16CodeUnits: [UInt16(NSF11FunctionKey)], count: 1)
    private static let f12Equivalent = String(utf16CodeUnits: [UInt16(NSF12FunctionKey)], count: 1)
}
