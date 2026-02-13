import CoreGraphics

struct HotkeySpec: Equatable {
    let keycode: UInt16
    let modifiers: CGEventFlags

    func matches(keycode: Int64, flags: CGEventFlags) -> Bool {
        guard self.keycode == UInt16(keycode) else { return false }
        if modifiers.isEmpty { return true }
        return flags.contains(modifiers)
    }

    static func parse(_ hotkey: String) -> HotkeySpec? {
        let parts = hotkey.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers = CGEventFlags()
        var keycode: UInt16?

        let modifierMap: [String: CGEventFlags] = [
            "cmd": .maskCommand, "command": .maskCommand,
            "shift": .maskShift,
            "alt": .maskAlternate, "option": .maskAlternate,
            "ctrl": .maskControl, "control": .maskControl,
        ]

        for part in parts {
            var token = part.lowercased()
            if token.hasPrefix("<") && token.hasSuffix(">") {
                token = String(token.dropFirst().dropLast())
            }
            if let mod = modifierMap[token] {
                modifiers.insert(mod)
            } else {
                keycode = KeycodeMap.keycode(for: token)
            }
        }

        guard let kc = keycode else { return nil }
        return HotkeySpec(keycode: kc, modifiers: modifiers)
    }
}
