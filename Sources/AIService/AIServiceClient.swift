import Foundation
import SharedModels
import SecureStorage

// MARK: - AI Service Error

public enum AIServiceError: Error, LocalizedError, Sendable {
    case noAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case modelNotAvailable(String)
    case serverError(Int, String)
    case networkError(String)
    case decodingError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .noAPIKey: "No OpenRouter API key configured"
        case .unauthorized: "Invalid API key (401 Unauthorized)"
        case .rateLimited(let t): "Rate limited. Retry after \(Int(t))s"
        case .modelNotAvailable(let m): "Model not available: \(m)"
        case .serverError(let code, let msg): "Server error \(code): \(msg)"
        case .networkError(let msg): "Network error: \(msg)"
        case .decodingError(let msg): "Decoding error: \(msg)"
        case .timeout: "Request timed out"
        }
    }
}

// MARK: - Chat Types

public struct ChatMessage: Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }

    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }

    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

public struct ChatResponse: Sendable {
    public let content: String
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let finishReason: String

    public init(
        content: String,
        model: String,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        finishReason: String = "stop"
    ) {
        self.content = content
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.finishReason = finishReason
    }
}

// MARK: - AI Service Client

public actor AIServiceClient {
    private let secureStorage: SecureStorage
    private let session: URLSession
    private let baseURL = "https://openrouter.ai/api/v1"

    public init(secureStorage: SecureStorage = SecureStorage()) {
        self.secureStorage = secureStorage
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - API Key

    public func hasAPIKey() -> Bool {
        (try? secureStorage.exists(key: SecureStorage.openRouterAPIKey)) ?? false
    }

    func getAPIKey() throws -> String {
        guard let key = try secureStorage.retrieve(key: SecureStorage.openRouterAPIKey) else {
            throw AIServiceError.noAPIKey
        }
        return key
    }

    // MARK: - Chat Completion

    public func chatCompletion(
        messages: [ChatMessage],
        model: ModelConfiguration,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> ChatResponse {
        let apiKey = try getAPIKey()

        var body: [String: Any] = [
            "model": model.modelID,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]

        if let maxTokens = maxTokens ?? model.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let temp = temperature ?? model.temperature {
            body["temperature"] = temp
        }

        let data = try await makeRequest(
            path: "/chat/completions",
            body: body,
            apiKey: apiKey
        )

        return try parseChatResponse(data)
    }

    // MARK: - Embeddings

    public func embeddings(
        input: [String],
        model: ModelConfiguration
    ) async throws -> [[Float]] {
        let apiKey = try getAPIKey()

        let body: [String: Any] = [
            "model": model.modelID,
            "input": input,
        ]

        let data = try await makeRequest(
            path: "/embeddings",
            body: body,
            apiKey: apiKey
        )

        return try parseEmbeddingsResponse(data)
    }

    // MARK: - Request Builder

    private func makeRequest(
        path: String,
        body: [String: Any],
        apiKey: String
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw AIServiceError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Terminus", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw AIServiceError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) } ?? 60
            throw AIServiceError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.serverError(httpResponse.statusCode, body)
        }
    }

    // MARK: - Response Parsing

    private func parseChatResponse(_ data: Data) throws -> ChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIServiceError.decodingError("Invalid chat response format")
        }

        // Handle content — may be null if model sent a refusal
        let content: String
        if let c = message["content"] as? String {
            content = c
        } else if let refusal = message["refusal"] as? String {
            content = "Request refused: \(refusal)"
        } else {
            throw AIServiceError.decodingError("No content in chat response")
        }

        let model = json["model"] as? String ?? "unknown"
        let usage = json["usage"] as? [String: Any]
        let promptTokens = usage?["prompt_tokens"] as? Int ?? 0
        let completionTokens = usage?["completion_tokens"] as? Int ?? 0
        let finishReason = first["finish_reason"] as? String ?? "stop"

        return ChatResponse(
            content: content,
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            finishReason: finishReason
        )
    }

    private func parseEmbeddingsResponse(_ data: Data) throws -> [[Float]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw AIServiceError.decodingError("Invalid embeddings response format")
        }

        return dataArray.compactMap { item in
            (item["embedding"] as? [NSNumber])?.map { Float(truncating: $0) }
        }
    }
}
