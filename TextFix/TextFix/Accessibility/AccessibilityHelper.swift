import Cocoa
import ApplicationServices

enum AccessibilityHelper {
    static func ensurePermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NotificationManager.send(
                title: "Accessibility permission required",
                message: "Enable TextFix in System Settings > Privacy & Security > Accessibility, then relaunch."
            )
        }
    }

    /// Returns the AXUIElement for the focused text field in the frontmost application.
    static func getFocusedTextField() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement
        )
        guard result == .success else { return nil }
        return (focusedElement as! AXUIElement)
    }

    /// Reads the text value of an AXUIElement.
    static func getValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// Sets the text value of an AXUIElement. Returns true on success.
    @discardableResult
    static func setValue(of element: AXUIElement, to newValue: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, newValue as CFTypeRef
        )
        return result == .success
    }

    /// Gets the selected text range from an AXUIElement.
    static func getSelectedRange(of element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        )
        guard result == .success else { return nil }
        var range = CFRange(location: 0, length: 0)
        if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
            return range
        }
        return nil
    }
}
