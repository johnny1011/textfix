import Foundation

enum ContextFormatter {
    static let contextSuffix = """


    The user has provided surrounding context in <context> tags. \
    Use it to understand tone, topic, and intent. Fix only the text \
    inside <text_to_fix> tags. Return only the corrected text, without any tags.
    """

    static func format(text: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return text }
        return """
        <context>
        \(context)
        </context>

        <text_to_fix>
        \(text)
        </text_to_fix>
        """
    }

    static func effectivePrompt(_ systemPrompt: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return systemPrompt }
        return systemPrompt + contextSuffix
    }
}
