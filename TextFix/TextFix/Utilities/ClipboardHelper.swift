import Cocoa

enum ClipboardHelper {
    private static let pollInterval: TimeInterval = 0.005
    private static let pollAttempts = 100

    static func read() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    static func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Simulates Cmd+C and waits for the pasteboard to change, then returns the new content.
    static func copySelection() -> String {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        KeyboardSimulator.pressKey(code: KeycodeMap.charToKeycode["c"]!, modifiers: .maskCommand)

        for _ in 0..<pollAttempts {
            Thread.sleep(forTimeInterval: pollInterval)
            if pasteboard.changeCount != changeCount {
                break
            }
        }
        return pasteboard.string(forType: .string) ?? ""
    }

    /// Writes text to clipboard and simulates Cmd+V.
    static func pasteText(_ text: String) {
        write(text)
        KeyboardSimulator.pressKey(code: KeycodeMap.charToKeycode["v"]!, modifiers: .maskCommand)
    }
}
