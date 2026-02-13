import Cocoa
import SwiftUI

class HotkeyCaptureNSView: NSView {
    var onHotkeyChange: ((String) -> Void)?
    private let textField: NSTextField

    override init(frame: NSRect) {
        textField = NSTextField(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        textField.isBezeled = true
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = true
        textField.placeholderString = "Click and press keys"
        super.init(frame: frame)
        addSubview(textField)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let hotkey = formatHotkeyEvent(event)
        guard let hotkey, !hotkey.isEmpty else { return }
        textField.stringValue = hotkey
        onHotkeyChange?(hotkey)
    }

    func setStringValue(_ value: String) {
        textField.stringValue = value
    }

    private func formatHotkeyEvent(_ event: NSEvent) -> String? {
        var parts: [String] = []

        if event.modifierFlags.contains(.command) { parts.append("<cmd>") }
        if event.modifierFlags.contains(.control) { parts.append("<ctrl>") }
        if event.modifierFlags.contains(.option) { parts.append("<alt>") }
        if event.modifierFlags.contains(.shift) { parts.append("<shift>") }

        let keyCode = event.keyCode
        if let special = KeycodeMap.keycodeToSpecial[keyCode] {
            if special == "backspace" { return "" }
            parts.append("<\(special)>")
        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let char = String(chars.first!).lowercased()
            if char == "\r" { parts.append("<enter>") }
            else if char == "\t" { parts.append("<tab>") }
            else if char == " " { parts.append("<space>") }
            else { parts.append(char) }
        } else {
            return nil
        }

        return parts.joined(separator: "+")
    }
}

struct HotkeyCaptureField: NSViewRepresentable {
    @Binding var value: String

    func makeNSView(context: Context) -> HotkeyCaptureNSView {
        let view = HotkeyCaptureNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.setStringValue(value)
        view.onHotkeyChange = { newValue in
            value = newValue
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureNSView, context: Context) {
        nsView.setStringValue(value)
    }
}
