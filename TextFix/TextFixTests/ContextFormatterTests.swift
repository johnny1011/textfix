import XCTest
@testable import TextFix

final class ContextFormatterTests: XCTestCase {
    func testNoContextReturnsTextUnchanged() {
        XCTAssertEqual(ContextFormatter.format(text: "hello", context: nil), "hello")
        XCTAssertEqual(ContextFormatter.format(text: "hello", context: ""), "hello")
    }

    func testWithContextWrapsInTags() {
        let result = ContextFormatter.format(text: "fix me", context: "some context")
        XCTAssert(result.contains("<context>"))
        XCTAssert(result.contains("some context"))
        XCTAssert(result.contains("<text_to_fix>"))
        XCTAssert(result.contains("fix me"))
    }

    func testEffectivePromptWithoutContext() {
        let prompt = ContextFormatter.effectivePrompt("base prompt", context: nil)
        XCTAssertEqual(prompt, "base prompt")
    }

    func testEffectivePromptWithContext() {
        let prompt = ContextFormatter.effectivePrompt("base prompt", context: "ctx")
        XCTAssert(prompt.hasPrefix("base prompt"))
        XCTAssert(prompt.contains("context"))
        XCTAssert(prompt.count > "base prompt".count)
    }
}
