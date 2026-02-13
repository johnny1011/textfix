import ApplicationServices
import os.log

/// Stores a reference to a text field that was marked for context-based fixing.
struct TextFieldReference {
    let element: AXUIElement
    let originalText: String
    var markerPrefix: String

    /// The full marked text that was written to the field (marker + original).
    var markedText: String { markerPrefix + originalText }

    /// Swaps the current marker prefix for a new one in the stored text field.
    /// Returns true if the swap succeeded.
    @discardableResult
    mutating func swapMarker(to newPrefix: String) -> Bool {
        guard let currentValue = AccessibilityHelper.getValue(of: element) else { return false }
        guard let range = currentValue.range(of: markedText) else { return false }
        let newMarked = newPrefix + originalText
        let newValue = currentValue.replacingCharacters(in: range, with: newMarked)
        guard AccessibilityHelper.setValue(of: element, to: newValue) else { return false }
        markerPrefix = newPrefix
        return true
    }

    /// Attempts to replace the marked text in the stored element with the fixed text.
    /// Returns true if the replacement succeeded via Accessibility API.
    func replaceWithFixed(_ fixedText: String) -> Bool {
        guard let currentValue = AccessibilityHelper.getValue(of: element) else {
            logger.info("replaceWithFixed: getValue returned nil")
            return false
        }

        // Try current marker first, then all known markers as fallback
        // (swapMarker can silently fail when the text field is unfocused)
        let candidates = [
            markedText,
            contextWaitingPrefix + originalText,
            fixingPrefix + originalText,
        ]

        for candidate in candidates {
            if let range = currentValue.range(of: candidate) {
                let newValue = currentValue.replacingCharacters(in: range, with: fixedText)
                if AccessibilityHelper.setValue(of: element, to: newValue) {
                    logger.info("replaceWithFixed: replaced OK")
                    return true
                }
            }
        }

        logger.info("replaceWithFixed: no marker found in value")
        return false
    }
}
