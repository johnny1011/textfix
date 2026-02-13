import Foundation

struct AnthropicProvider: TextFixProvider {
    let models = anthropicModels
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func rewrite(text: String, apiKey: String, model: String, systemPrompt: String,
                 temperature: Double, maxTokens: Int, context: String?,
                 timeout: TimeInterval = 30) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let inputText = ContextFormatter.format(text: text, context: context)
        let effectivePrompt = ContextFormatter.effectivePrompt(systemPrompt, context: context)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": inputText]],
        ]
        if !effectivePrompt.isEmpty {
            body["system"] = effectivePrompt
        }
        body["temperature"] = temperature
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode >= 400 {
            let detail = Self.extractErrorDetail(from: data)
            throw TextFixError.apiError(statusCode: httpResponse.statusCode, detail: detail)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TextFixError.invalidResponse
        }

        return Self.extractText(from: json)
    }

    static func extractText(from payload: [String: Any]) -> String {
        guard let content = payload["content"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for block in content {
            if block["type"] as? String == "text",
               let text = block["text"] as? String {
                parts.append(text)
            }
        }
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractErrorDetail(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return (try? String(data: JSONSerialization.data(withJSONObject: json), encoding: .utf8)) ?? ""
    }
}
