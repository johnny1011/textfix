import XCTest
@testable import TextFixKit

final class TextFixKitTests: XCTestCase {
    func testExtractOpenAIOutputConcatenatesOutputText() {
        let payload: [String: Any] = [
            "output": [
                [
                    "type": "message",
                    "content": [
                        ["type": "output_text", "text": "Hello"],
                        ["type": "output_text", "text": " world"],
                    ],
                ],
            ],
        ]

        let client = APIClient()
        XCTAssertEqual(client.extractOpenAIOutput(from: payload), "Hello world")
    }

    func testExtractOpenAIOutputIgnoresNonMessageItems() {
        let payload: [String: Any] = [
            "output": [
                [
                    "type": "other",
                    "content": [
                        ["type": "output_text", "text": "Nope"],
                    ],
                ],
                [
                    "type": "message",
                    "content": [
                        ["type": "output_text", "text": "Yep"],
                    ],
                ],
            ],
        ]

        let client = APIClient()
        XCTAssertEqual(client.extractOpenAIOutput(from: payload), "Yep")
    }

    func testExtractAnthropicOutputConcatenatesTextParts() {
        let payload: [String: Any] = [
            "content": [
                ["type": "text", "text": "Fixed"],
                ["type": "text", "text": " text"],
            ],
        ]

        let client = APIClient()
        XCTAssertEqual(client.extractAnthropicOutput(from: payload), "Fixed text")
    }

    func testParseHotkeySupportsModifiersAndKey() {
        let hotkey = HotkeySupport.parse("<cmd>+<shift>+g")

        XCTAssertEqual(hotkey?.keyCode, HotkeySupport.keyCodeMap["g"])
        XCTAssertEqual(hotkey?.modifiers, [.maskCommand, .maskShift])
    }

    func testConfigFromDictionarySupportsLegacyTypes() {
        let config = AppConfig.from(dictionary: [
            "max_output_tokens": "1024",
            "open_at_login": NSNumber(value: true),
            "show_notifications": NSNumber(value: false),
            "temperature": "0.7",
        ])

        XCTAssertEqual(config.maxOutputTokens, 1024)
        XCTAssertEqual(config.temperature, 0.7)
        XCTAssertTrue(config.openAtLogin)
        XCTAssertFalse(config.showNotifications)
    }
}
