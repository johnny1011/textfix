import Foundation

struct OpenAIProvider: TextFixProvider {
    let models = openaiModels
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func rewrite(text: String, apiKey: String, model: String, systemPrompt: String,
                 temperature: Double, maxTokens: Int, context: String?,
                 timeout: TimeInterval = 30) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let inputText = ContextFormatter.format(text: text, context: context)
        let effectivePrompt = ContextFormatter.effectivePrompt(systemPrompt, context: context)

        let body: [String: Any] = [
            "model": model,
            "instructions": effectivePrompt,
            "input": inputText,
            "temperature": temperature,
            "max_output_tokens": maxTokens,
        ]
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

        return Self.extractOutputText(from: json)
    }

    static func extractOutputText(from payload: [String: Any]) -> String {
        guard let output = payload["output"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for item in output {
            guard item["type"] as? String == "message",
                  let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if block["type"] as? String == "output_text",
                   let text = block["text"] as? String {
                    parts.append(text)
                }
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
        return (try? String(data: JSONSerialization.data(withJSONObject: json), encoding: .utf8)) ?? ""
    }
}
