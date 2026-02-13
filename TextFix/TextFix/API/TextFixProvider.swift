import Foundation

enum TextFixError: LocalizedError {
    case apiError(statusCode: Int, detail: String)
    case networkError(Error)
    case invalidResponse
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let detail):
            return detail.isEmpty ? "API error \(code)" : "API error \(code): \(detail)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server."
        case .noAPIKey:
            return "No API key configured."
        }
    }
}

protocol TextFixProvider {
    var models: [String] { get }
    func rewrite(text: String, apiKey: String, model: String, systemPrompt: String,
                 temperature: Double, maxTokens: Int, context: String?,
                 timeout: TimeInterval) async throws -> String
}

enum ProviderType {
    case openai, anthropic

    static func from(model: String) -> ProviderType {
        model.hasPrefix("claude-") ? .anthropic : .openai
    }
}

let openaiModels = ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
let anthropicModels = [
    "claude-opus-4-6",
    "claude-opus-4-5-20251101",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
]
let allModels = openaiModels + anthropicModels
