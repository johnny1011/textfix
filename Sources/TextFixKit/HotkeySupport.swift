import AppKit
import CoreGraphics

public struct HotkeySpec: Equatable {
    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags

    public init(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum HotkeySupport {
    public static let inlineSpinnerPrefix = "⏳"
    public static let copyPollInterval: UInt32 = 20_000
    public static let copyPollAttempts = 25
    public static let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    public static let keyCodeMap: [String: CGKeyCode] = [
        "a": 0,
        "s": 1,
        "d": 2,
        "f": 3,
        "h": 4,
        "g": 5,
        "z": 6,
        "x": 7,
        "c": 8,
        "v": 9,
        "b": 11,
        "q": 12,
        "w": 13,
        "e": 14,
        "r": 15,
        "y": 16,
        "t": 17,
        "1": 18,
        "2": 19,
        "3": 20,
        "4": 21,
        "6": 22,
        "5": 23,
        "=": 24,
        "9": 25,
        "7": 26,
        "-": 27,
        "8": 28,
        "0": 29,
        "]": 30,
        "o": 31,
        "u": 32,
        "[": 33,
        "i": 34,
        "p": 35,
        "l": 37,
        "j": 38,
        "'": 39,
        "k": 40,
        ";": 41,
        "\\": 42,
        ",": 43,
        "/": 44,
        "n": 45,
        "m": 46,
        ".": 47,
        "`": 50,
        "space": 49,
        "tab": 48,
        "enter": 36,
        "esc": 53,
        "backspace": 51,
        "delete": 117,
        "left": 123,
        "right": 124,
        "down": 125,
        "up": 126,
        "home": 115,
        "end": 119,
        "pageup": 116,
        "pagedown": 121,
    ]

    public static let specialKeycodes: [CGKeyCode: String] = [
        36: "enter",
        48: "tab",
        49: "space",
        51: "backspace",
        53: "esc",
        117: "delete",
        123: "left",
        124: "right",
        125: "down",
        126: "up",
        115: "home",
        119: "end",
        116: "pageup",
        121: "pagedown",
        122: "f1",
        120: "f2",
        99: "f3",
        118: "f4",
        96: "f5",
        97: "f6",
        98: "f7",
        100: "f8",
        101: "f9",
        109: "f10",
        103: "f11",
        111: "f12",
        105: "f13",
        107: "f14",
        113: "f15",
        106: "f16",
        64: "f17",
        79: "f18",
        80: "f19",
        90: "f20",
    ]

    public static func parse(_ hotkey: String) -> HotkeySpec? {
        let parts = hotkey
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var modifiers = CGEventFlags()
        var keyCode: CGKeyCode?

        for part in parts {
            var token = part.lowercased()
            if token.hasPrefix("<"), token.hasSuffix(">") {
                token.removeFirst()
                token.removeLast()
            }

            switch token {
            case "cmd", "command":
                modifiers.insert(.maskCommand)
            case "shift":
                modifiers.insert(.maskShift)
            case "alt", "option":
                modifiers.insert(.maskAlternate)
            case "ctrl", "control":
                modifiers.insert(.maskControl)
            default:
                keyCode = keyCodeMap[token]
            }
        }

        guard let keyCode else {
            return nil
        }
        return HotkeySpec(keyCode: keyCode, modifiers: modifiers)
    }

    public static func matches(_ spec: HotkeySpec?, keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let spec else {
            return false
        }
        guard keyCode == spec.keyCode else {
            return false
        }
        return flags.intersection(modifierMask) == spec.modifiers
    }

    public static func format(event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []

        if flags.contains(.command) {
            parts.append("<cmd>")
        }
        if flags.contains(.control) {
            parts.append("<ctrl>")
        }
        if flags.contains(.option) {
            parts.append("<alt>")
        }
        if flags.contains(.shift) {
            parts.append("<shift>")
        }

        let keyCode = CGKeyCode(event.keyCode)
        let keyToken: String
        if let special = specialKeycodes[keyCode] {
            if special == "backspace" {
                return ""
            }
            keyToken = "<\(special)>"
        } else {
            guard let characters = event.charactersIgnoringModifiers, let first = characters.first else {
                return nil
            }
            switch first {
            case "\r":
                keyToken = "<enter>"
            case "\t":
                keyToken = "<tab>"
            case " ":
                keyToken = "<space>"
            default:
                keyToken = String(first).lowercased()
            }
        }

        if parts.isEmpty {
            return keyToken
        }
        return (parts + [keyToken]).joined(separator: "+")
    }
}
