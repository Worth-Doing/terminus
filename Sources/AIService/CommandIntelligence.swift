import Foundation
import SharedModels

// MARK: - Command Intelligence

public actor CommandIntelligence {
    private let aiService: AIServiceClient

    public init(aiService: AIServiceClient) {
        self.aiService = aiService
    }

    // MARK: - Explain Command Inline

    public func explainCommand(
        _ command: String,
        model: ModelConfiguration
    ) async throws -> CommandExplanation {
        let messages: [ChatMessage] = [
            .system("""
            You are a shell command expert. Analyze the given command and respond with valid JSON only:
            {
              "summary": "one-line summary of what this command does",
              "parts": [
                {"token": "the part", "explanation": "what it does"}
              ],
              "risk_level": "safe|moderate|dangerous",
              "tips": ["optional improvement suggestion"]
            }
            Keep explanations concise (under 15 words each). Output ONLY valid JSON.
            """),
            .user(command),
        ]

        let response = try await aiService.chatCompletion(
            messages: messages,
            model: model,
            maxTokens: 512,
            temperature: 0.2
        )

        return parseExplanation(response.content, command: command)
    }

    // MARK: - Suggest Improvements

    public func suggestImprovement(
        _ command: String,
        model: ModelConfiguration
    ) async throws -> [CommandSuggestion] {
        let messages: [ChatMessage] = [
            .system("""
            You are a shell command optimizer for macOS. Analyze the command and suggest improvements.
            Respond with JSON only:
            {
              "suggestions": [
                {"improved": "better command", "reason": "why it's better", "category": "performance|safety|readability|portability"}
              ]
            }
            Only suggest genuinely better alternatives. If the command is already optimal, return empty suggestions array.
            Output ONLY valid JSON.
            """),
            .user(command),
        ]

        let response = try await aiService.chatCompletion(
            messages: messages,
            model: model,
            maxTokens: 512,
            temperature: 0.3
        )

        return parseSuggestions(response.content)
    }

    // MARK: - Parsing

    private func parseExplanation(_ content: String, command: String) -> CommandExplanation {
        let json = extractJSON(from: content)
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CommandExplanation(
                command: command,
                summary: content,
                parts: [],
                riskLevel: "safe",
                tips: []
            )
        }

        let summary = parsed["summary"] as? String ?? "Command analyzed"
        let riskLevel = parsed["risk_level"] as? String ?? "safe"
        let tips = parsed["tips"] as? [String] ?? []

        var parts: [CommandPart] = []
        if let partsArray = parsed["parts"] as? [[String: Any]] {
            for p in partsArray {
                if let token = p["token"] as? String,
                   let explanation = p["explanation"] as? String {
                    parts.append(CommandPart(token: token, explanation: explanation))
                }
            }
        }

        return CommandExplanation(
            command: command,
            summary: summary,
            parts: parts,
            riskLevel: riskLevel,
            tips: tips
        )
    }

    private func parseSuggestions(_ content: String) -> [CommandSuggestion] {
        let json = extractJSON(from: content)
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let suggestions = parsed["suggestions"] as? [[String: Any]] else {
            return []
        }

        return suggestions.compactMap { s in
            guard let improved = s["improved"] as? String,
                  let reason = s["reason"] as? String else { return nil }
            let category = s["category"] as? String ?? "general"
            return CommandSuggestion(improved: improved, reason: reason, category: category)
        }
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}

// MARK: - Data Types

public struct CommandExplanation: Sendable {
    public let command: String
    public let summary: String
    public let parts: [CommandPart]
    public let riskLevel: String
    public let tips: [String]

    public init(command: String, summary: String, parts: [CommandPart], riskLevel: String, tips: [String]) {
        self.command = command
        self.summary = summary
        self.parts = parts
        self.riskLevel = riskLevel
        self.tips = tips
    }
}

public struct CommandPart: Sendable, Identifiable {
    public let id = UUID()
    public let token: String
    public let explanation: String

    public init(token: String, explanation: String) {
        self.token = token
        self.explanation = explanation
    }
}

public struct CommandSuggestion: Sendable, Identifiable {
    public let id = UUID()
    public let improved: String
    public let reason: String
    public let category: String

    public init(improved: String, reason: String, category: String) {
        self.improved = improved
        self.reason = reason
        self.category = category
    }
}
