import Foundation

public struct RewriteResult: Equatable, Sendable {
    public let text: String
    public let error: String

    public init(text: String, error: String) {
        self.text = text
        self.error = error
    }
}

public final class APIClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func rewriteText(
        text: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double,
        maxOutputTokens: Int,
        provider: Provider,
        timeout: TimeInterval = 30
    ) async -> RewriteResult {
        switch provider {
        case .openAI:
            return await rewriteOpenAIText(
                text: text,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                temperature: temperature,
                maxOutputTokens: maxOutputTokens,
                timeout: timeout
            )
        case .anthropic:
            return await rewriteAnthropicText(
                text: text,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                temperature: temperature,
                maxOutputTokens: maxOutputTokens,
                timeout: timeout
            )
        }
    }

    public func extractOpenAIOutput(from payload: [String: Any]) -> String {
        guard let output = payload["output"] as? [[String: Any]] else {
            return ""
        }

        let text = output.compactMap { item -> String? in
            guard item["type"] as? String == "message" else {
                return nil
            }
            let content = item["content"] as? [[String: Any]] ?? []
            let parts = content.compactMap { entry -> String? in
                guard entry["type"] as? String == "output_text" else {
                    return nil
                }
                return entry["text"] as? String
            }
            return parts.joined()
        }

        return text.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func extractAnthropicOutput(from payload: [String: Any]) -> String {
        guard let content = payload["content"] as? [[String: Any]] else {
            return ""
        }

        let parts = content.compactMap { entry -> String? in
            guard entry["type"] as? String == "text" else {
                return nil
            }
            return entry["text"] as? String
        }
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rewriteOpenAIText(
        text: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double,
        maxOutputTokens: Int,
        timeout: TimeInterval
    ) async -> RewriteResult {
        let payload: [String: Any] = [
            "input": text,
            "instructions": systemPrompt,
            "max_output_tokens": maxOutputTokens,
            "model": model,
            "temperature": temperature,
        ]

        return await performRequest(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
            ],
            payload: payload,
            timeout: timeout,
            detailExtractor: { data in
                guard
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let dictionary = object as? [String: Any]
                else {
                    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                if
                    let error = dictionary["error"] as? [String: Any],
                    let message = error["message"] as? String,
                    !message.isEmpty
                {
                    return message
                }
                return self.compactJSONString(dictionary)
            },
            successExtractor: { data in
                guard
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let dictionary = object as? [String: Any]
                else {
                    return RewriteResult(text: "", error: "Invalid response from server.")
                }
                return RewriteResult(text: self.extractOpenAIOutput(from: dictionary), error: "")
            }
        )
    }

    private func rewriteAnthropicText(
        text: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double,
        maxOutputTokens: Int,
        timeout: TimeInterval
    ) async -> RewriteResult {
        var payload: [String: Any] = [
            "max_tokens": maxOutputTokens,
            "messages": [
                ["content": text, "role": "user"],
            ],
            "model": model,
            "temperature": temperature,
        ]
        if !systemPrompt.isEmpty {
            payload["system"] = systemPrompt
        }

        return await performRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
                "x-api-key": apiKey,
            ],
            payload: payload,
            timeout: timeout,
            detailExtractor: { data in
                guard
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let dictionary = object as? [String: Any]
                else {
                    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                if
                    let error = dictionary["error"] as? [String: Any],
                    let message = error["message"] as? String,
                    !message.isEmpty
                {
                    return message
                }
                if let message = dictionary["message"] as? String, !message.isEmpty {
                    return message
                }
                return self.compactJSONString(dictionary)
            },
            successExtractor: { data in
                guard
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let dictionary = object as? [String: Any]
                else {
                    return RewriteResult(text: "", error: "Invalid response from server.")
                }
                return RewriteResult(text: self.extractAnthropicOutput(from: dictionary), error: "")
            }
        )
    }

    private func performRequest(
        url: URL,
        headers: [String: String],
        payload: [String: Any],
        timeout: TimeInterval,
        detailExtractor: (Data) -> String,
        successExtractor: (Data) -> RewriteResult
    ) async -> RewriteResult {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return RewriteResult(text: "", error: "Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return RewriteResult(text: "", error: "Invalid response from server.")
        }

        if httpResponse.statusCode >= 400 {
            let detail = detailExtractor(data)
            let message = detail.isEmpty
                ? "API error \(httpResponse.statusCode)"
                : "API error \(httpResponse.statusCode): \(detail)"
            return RewriteResult(text: "", error: message)
        }

        return successExtractor(data)
    }

    private func compactJSONString(_ object: [String: Any]) -> String {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }
}
