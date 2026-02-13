import Foundation

struct TextFixConfig: Codable, Equatable {
    var openaiApiKey: String
    var anthropicApiKey: String
    var hotkey: String
    var contextHotkey: String
    var promptHotkey: String
    var model: String
    var temperature: Double
    var maxOutputTokens: Int
    var openAtLogin: Bool
    var showNotifications: Bool
    var systemPrompt: String
    var promptSystemPrompt: String

    static let `default` = TextFixConfig(
        openaiApiKey: "",
        anthropicApiKey: "",
        hotkey: "<cmd>+<shift>+g",
        contextHotkey: "<cmd>+<shift>+h",
        promptHotkey: "<cmd>+<alt>+j",
        model: "gpt-4.1-mini",
        temperature: 0.0,
        maxOutputTokens: 512,
        openAtLogin: false,
        showNotifications: false,
        systemPrompt: "You are a copyeditor. Fix spelling, grammar, and punctuation while preserving the original meaning and tone. Return only the corrected text.",
        promptSystemPrompt: "You are an expert prompt engineer. Rewrite the provided text into a clear, well-structured prompt for a language model. Improve clarity, add specificity, and organize the request logically. Return only the rewritten prompt."
    )

    enum CodingKeys: String, CodingKey {
        case openaiApiKey = "openai_api_key"
        case anthropicApiKey = "anthropic_api_key"
        case hotkey
        case contextHotkey = "context_hotkey"
        case promptHotkey = "prompt_hotkey"
        case model
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case openAtLogin = "open_at_login"
        case showNotifications = "show_notifications"
        case systemPrompt = "system_prompt"
        case promptSystemPrompt = "prompt_system_prompt"
    }

    init(openaiApiKey: String = "",
         anthropicApiKey: String = "",
         hotkey: String = "<cmd>+<shift>+g",
         contextHotkey: String = "<cmd>+<shift>+h",
         promptHotkey: String = "<cmd>+<alt>+j",
         model: String = "gpt-4.1-mini",
         temperature: Double = 0.0,
         maxOutputTokens: Int = 512,
         openAtLogin: Bool = false,
         showNotifications: Bool = false,
         systemPrompt: String = "You are a copyeditor. Fix spelling, grammar, and punctuation while preserving the original meaning and tone. Return only the corrected text.",
         promptSystemPrompt: String = "You are an expert prompt engineer. Rewrite the provided text into a clear, well-structured prompt for a language model. Improve clarity, add specificity, and organize the request logically. Return only the rewritten prompt.") {
        self.openaiApiKey = openaiApiKey
        self.anthropicApiKey = anthropicApiKey
        self.hotkey = hotkey
        self.contextHotkey = contextHotkey
        self.promptHotkey = promptHotkey
        self.model = model
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.openAtLogin = openAtLogin
        self.showNotifications = showNotifications
        self.systemPrompt = systemPrompt
        self.promptSystemPrompt = promptSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let d = TextFixConfig.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        openaiApiKey = (try? container.decode(String.self, forKey: .openaiApiKey)) ?? d.openaiApiKey
        anthropicApiKey = (try? container.decode(String.self, forKey: .anthropicApiKey)) ?? d.anthropicApiKey
        hotkey = (try? container.decode(String.self, forKey: .hotkey)) ?? d.hotkey
        contextHotkey = (try? container.decode(String.self, forKey: .contextHotkey)) ?? d.contextHotkey
        model = (try? container.decode(String.self, forKey: .model)) ?? d.model
        temperature = (try? container.decode(Double.self, forKey: .temperature)) ?? d.temperature
        maxOutputTokens = (try? container.decode(Int.self, forKey: .maxOutputTokens)) ?? d.maxOutputTokens
        openAtLogin = (try? container.decode(Bool.self, forKey: .openAtLogin)) ?? d.openAtLogin
        showNotifications = (try? container.decode(Bool.self, forKey: .showNotifications)) ?? d.showNotifications
        systemPrompt = (try? container.decode(String.self, forKey: .systemPrompt)) ?? d.systemPrompt
        promptHotkey = (try? container.decode(String.self, forKey: .promptHotkey)) ?? d.promptHotkey
        promptSystemPrompt = (try? container.decode(String.self, forKey: .promptSystemPrompt)) ?? d.promptSystemPrompt

        // Migration: old Python config used "api_key" for OpenAI
        if openaiApiKey.isEmpty,
           let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           let legacy = try? legacyContainer.decode(String.self, forKey: .apiKey) {
            openaiApiKey = legacy
        }
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }
}
