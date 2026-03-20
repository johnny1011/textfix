import Foundation

public enum Provider: String, Equatable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        }
    }
}

public enum ActionMode: Equatable, Sendable {
    case fix
    case prompt
}

public let openAIModelChoices = ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
public let anthropicModelChoices = [
    "claude-opus-4-6",
    "claude-opus-4-5-20251101",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
]
public let modelChoices = openAIModelChoices + anthropicModelChoices

public struct AppConfig: Equatable, Sendable {
    public var openAIAPIKey: String
    public var anthropicAPIKey: String
    public var hotkey: String
    public var promptHotkey: String
    public var model: String
    public var temperature: Double
    public var maxOutputTokens: Int
    public var openAtLogin: Bool
    public var showNotifications: Bool
    public var systemPrompt: String
    public var promptSystemPrompt: String

    public init(
        openAIAPIKey: String,
        anthropicAPIKey: String,
        hotkey: String,
        promptHotkey: String,
        model: String,
        temperature: Double,
        maxOutputTokens: Int,
        openAtLogin: Bool,
        showNotifications: Bool,
        systemPrompt: String,
        promptSystemPrompt: String
    ) {
        self.openAIAPIKey = openAIAPIKey
        self.anthropicAPIKey = anthropicAPIKey
        self.hotkey = hotkey
        self.promptHotkey = promptHotkey
        self.model = model
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.openAtLogin = openAtLogin
        self.showNotifications = showNotifications
        self.systemPrompt = systemPrompt
        self.promptSystemPrompt = promptSystemPrompt
    }

    public static let defaultConfig = AppConfig(
        openAIAPIKey: "",
        anthropicAPIKey: "",
        hotkey: "<cmd>+<shift>+g",
        promptHotkey: "<cmd>+<alt>+g",
        model: "gpt-4.1-mini",
        temperature: 0.0,
        maxOutputTokens: 512,
        openAtLogin: false,
        showNotifications: false,
        systemPrompt: "You are a copyeditor. Fix spelling, grammar, and punctuation while preserving the original meaning and tone. Return only the corrected text.",
        promptSystemPrompt: "You are a prompt engineer and copyeditor. Rewrite the user's text into a single, clear, high-quality prompt. Fix spelling, grammar, and punctuation. Preserve the original intent and important constraints. Return only the rewritten prompt."
    )

    public static let jsonKeys = [
        "openai_api_key",
        "anthropic_api_key",
        "hotkey",
        "prompt_hotkey",
        "model",
        "temperature",
        "max_output_tokens",
        "open_at_login",
        "show_notifications",
        "system_prompt",
        "prompt_system_prompt",
    ]

    public var provider: Provider {
        if model.hasPrefix("claude-") {
            return .anthropic
        }
        return .openAI
    }

    public func apiKey(for provider: Provider) -> String {
        switch provider {
        case .openAI:
            return openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic:
            return anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func prompt(for mode: ActionMode) -> String {
        switch mode {
        case .fix:
            return systemPrompt
        case .prompt:
            return promptSystemPrompt
        }
    }

    public static func from(dictionary: [String: Any]) -> AppConfig {
        var config = AppConfig.defaultConfig

        if let value = dictionary["openai_api_key"] as? String {
            config.openAIAPIKey = value
        }
        if let value = dictionary["anthropic_api_key"] as? String {
            config.anthropicAPIKey = value
        }
        if let value = dictionary["hotkey"] as? String, !value.isEmpty {
            config.hotkey = value
        }
        if let value = dictionary["prompt_hotkey"] as? String, !value.isEmpty {
            config.promptHotkey = value
        }
        if let value = dictionary["model"] as? String, !value.isEmpty {
            config.model = value
        }
        if let value = dictionary["temperature"] as? Double {
            config.temperature = value
        } else if let value = dictionary["temperature"] as? NSNumber {
            config.temperature = value.doubleValue
        } else if let value = dictionary["temperature"] as? String, let parsed = Double(value) {
            config.temperature = parsed
        }
        if let value = dictionary["max_output_tokens"] as? Int {
            config.maxOutputTokens = value
        } else if let value = dictionary["max_output_tokens"] as? NSNumber {
            config.maxOutputTokens = value.intValue
        } else if let value = dictionary["max_output_tokens"] as? String, let parsed = Int(value) {
            config.maxOutputTokens = parsed
        }
        if let value = dictionary["open_at_login"] as? Bool {
            config.openAtLogin = value
        } else if let value = dictionary["open_at_login"] as? NSNumber {
            config.openAtLogin = value.boolValue
        }
        if let value = dictionary["show_notifications"] as? Bool {
            config.showNotifications = value
        } else if let value = dictionary["show_notifications"] as? NSNumber {
            config.showNotifications = value.boolValue
        }
        if let value = dictionary["system_prompt"] as? String, !value.isEmpty {
            config.systemPrompt = value
        }
        if let value = dictionary["prompt_system_prompt"] as? String, !value.isEmpty {
            config.promptSystemPrompt = value
        }

        return config
    }

    public func jsonObject() -> [String: Any] {
        [
            "anthropic_api_key": anthropicAPIKey,
            "hotkey": hotkey,
            "max_output_tokens": maxOutputTokens,
            "model": model,
            "open_at_login": openAtLogin,
            "openai_api_key": openAIAPIKey,
            "prompt_hotkey": promptHotkey,
            "prompt_system_prompt": promptSystemPrompt,
            "show_notifications": showNotifications,
            "system_prompt": systemPrompt,
            "temperature": temperature,
        ]
    }
}
