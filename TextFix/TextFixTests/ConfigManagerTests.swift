import XCTest
@testable import TextFix

final class ConfigManagerTests: XCTestCase {
    func testDefaultConfig() {
        let config = TextFixConfig.default
        XCTAssertEqual(config.hotkey, "<cmd>+<shift>+g")
        XCTAssertEqual(config.contextHotkey, "<cmd>+<shift>+h")
        XCTAssertEqual(config.model, "gpt-4.1-mini")
        XCTAssertEqual(config.temperature, 0.0)
        XCTAssertEqual(config.maxOutputTokens, 512)
        XCTAssertFalse(config.openAtLogin)
        XCTAssertFalse(config.showNotifications)
    }

    func testRoundtripEncodeDecode() throws {
        let config = TextFixConfig(
            openaiApiKey: "sk-test",
            anthropicApiKey: "ant-test",
            hotkey: "<cmd>+<shift>+g",
            contextHotkey: "<cmd>+<shift>+h",
            model: "gpt-4.1",
            temperature: 0.5,
            maxOutputTokens: 1024,
            openAtLogin: true,
            showNotifications: true,
            systemPrompt: "Fix it"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(TextFixConfig.self, from: data)

        XCTAssertEqual(config, decoded)
    }

    func testDecodesSnakeCaseKeys() throws {
        let json = """
        {
            "openai_api_key": "sk-123",
            "anthropic_api_key": "ant-456",
            "hotkey": "<cmd>+<shift>+g",
            "context_hotkey": "<cmd>+<shift>+h",
            "model": "gpt-4.1-mini",
            "temperature": 0.7,
            "max_output_tokens": 256,
            "open_at_login": true,
            "show_notifications": false,
            "system_prompt": "Hello"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(TextFixConfig.self, from: json)
        XCTAssertEqual(config.openaiApiKey, "sk-123")
        XCTAssertEqual(config.anthropicApiKey, "ant-456")
        XCTAssertEqual(config.temperature, 0.7)
        XCTAssertEqual(config.maxOutputTokens, 256)
        XCTAssertTrue(config.openAtLogin)
        XCTAssertEqual(config.systemPrompt, "Hello")
    }

    func testMissingKeysGetDefaults() throws {
        let json = """
        {
            "openai_api_key": "sk-test",
            "model": "gpt-4.1"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(TextFixConfig.self, from: json)
        XCTAssertEqual(config.openaiApiKey, "sk-test")
        XCTAssertEqual(config.model, "gpt-4.1")
        // Missing keys should get defaults
        XCTAssertEqual(config.hotkey, "<cmd>+<shift>+g")
        XCTAssertEqual(config.contextHotkey, "<cmd>+<shift>+h")
        XCTAssertEqual(config.temperature, 0.0)
        XCTAssertEqual(config.maxOutputTokens, 512)
        XCTAssertFalse(config.openAtLogin)
    }

    func testLegacyApiKeyMigration() throws {
        let json = """
        {
            "api_key": "sk-legacy"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(TextFixConfig.self, from: json)
        XCTAssertEqual(config.openaiApiKey, "sk-legacy")
    }

    func testCorruptJsonGetsDefaults() {
        let json = "not json at all".data(using: .utf8)!
        let config = try? JSONDecoder().decode(TextFixConfig.self, from: json)
        XCTAssertNil(config)
    }
}
