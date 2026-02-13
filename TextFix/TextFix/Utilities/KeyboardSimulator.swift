import CoreGraphics

enum KeyboardSimulator {
    static func pressKey(code: UInt16, modifiers: CGEventFlags = []) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        if !modifiers.isEmpty {
            keyDown.flags = modifiers
            keyUp.flags = modifiers
        }
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
