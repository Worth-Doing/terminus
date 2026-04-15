import Foundation
import SharedModels
import SecureStorage

// MARK: - NL Command Pipeline

public actor NLCommandPipeline {
    private let aiService: AIServiceClient
    private var sessionContext: AISessionContext

    public init(aiService: AIServiceClient) {
        self.aiService = aiService
        self.sessionContext = AISessionContext()
    }

    // MARK: - Intent Detection

    public func detectIntent(_ input: String) -> InputIntent {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it starts with common shell prefixes, treat as raw command
        let shellPrefixes = [
            "/", "./", "~", "$", "!", "#",
            "cd ", "ls", "cat ", "echo ", "pwd", "mkdir ",
            "rm ", "cp ", "mv ", "touch ", "chmod ", "chown ",
            "git ", "docker ", "npm ", "yarn ", "pip ", "brew ",
            "python", "node ", "swift ", "cargo ", "go ",
            "curl ", "wget ", "ssh ", "scp ", "rsync ",
            "grep ", "find ", "sed ", "awk ", "sort ",
            "export ", "source ", "alias ", "unalias ",
            "sudo ", "man ", "which ", "where ",
            "make", "cmake", "gcc ", "g++ ",
            "tar ", "zip ", "unzip ", "gzip ",
            "kill ", "ps ", "top", "htop",
            "vim ", "nano ", "emacs ",
            "open ", "pbcopy", "pbpaste",
        ]

        // Check for command-like patterns
        for prefix in shellPrefixes {
            if trimmed.lowercased().hasPrefix(prefix) {
                return .rawCommand
            }
        }

        // If it contains pipe, redirect, or other shell operators at the start, it's a command
        if trimmed.first == "|" || trimmed.hasPrefix(">>") || trimmed.hasPrefix("2>") {
            return .rawCommand
        }

        // If it looks like an executable (word with no spaces followed by flags)
        let words = trimmed.split(separator: " ")
        if let first = words.first {
            let firstWord = String(first)
            // If first word contains no spaces and subsequent words start with -
            if words.count > 1 && words.dropFirst().first?.hasPrefix("-") == true {
                // Looks like: somecommand -flag
                return .rawCommand
            }
            // Single word that looks like a command
            if words.count == 1 && !firstWord.contains(" ") && firstWord.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" }) && firstWord.count < 20 {
                return .rawCommand
            }
        }

        // Otherwise, if it contains question-like or natural language patterns
        let nlIndicators = [
            "find ", "show ", "list ", "create ", "delete ",
            "how ", "what ", "where ", "which ",
            "can you", "please ", "help ",
            "i want", "i need",
            "set up", "setup",
            "install ", "update ", "upgrade ",
            "all ", "every ", "each ",
            "files ", "folders ", "directories ",
            "larger than", "smaller than", "bigger than",
            "sort by", "sorted by", "order by",
            "compress", "extract",
            "running on port",
            "using port",
            "disk usage", "disk space",
            "memory usage",
        ]

        let lowered = trimmed.lowercased()
        for indicator in nlIndicators {
            if lowered.contains(indicator) && trimmed.contains(" ") {
                // Additional check: natural language tends to have multiple regular words
                let regularWords = words.filter { !$0.hasPrefix("-") && !$0.hasPrefix("/") }
                if regularWords.count >= 2 {
                    return .naturalLanguage
                }
            }
        }

        // If it's a longer phrase with spaces and no obvious shell syntax, treat as NL
        if words.count >= 3 && !trimmed.contains("|") && !trimmed.contains(">") && !trimmed.contains("&&") {
            return .naturalLanguage
        }

        return .rawCommand
    }

    // MARK: - Generate Command from Natural Language

    public func generateCommand(
        from request: NLCommandRequest,
        model: ModelConfiguration
    ) async throws -> NLCommandResponse {
        let messages = buildPromptMessages(for: request)

        let response = try await aiService.chatCompletion(
            messages: messages,
            model: model,
            maxTokens: 1024,
            temperature: 0.3
        )

        let parsed = parseCommandResponse(response.content, requestID: request.id)

        // Update session context
        var ctx = sessionContext
        ctx.currentDirectory = request.currentDirectory
        ctx.addExchange(
            query: request.query,
            commands: parsed.commands.map(\.command),
            output: nil
        )
        sessionContext = ctx

        return NLCommandResponse(
            id: UUID(),
            requestID: request.id,
            commands: parsed.commands,
            explanation: parsed.explanation,
            alternatives: parsed.alternatives,
            isMultiStep: parsed.commands.count > 1,
            model: response.model,
            timestamp: Date()
        )
    }

    // MARK: - Explain Command

    public func explainCommand(
        _ command: String,
        model: ModelConfiguration
    ) async throws -> String {
        let messages: [ChatMessage] = [
            .system("""
            You are a shell command expert. Explain the given command clearly and concisely.
            Break down each part: the command name, flags, arguments.
            Mention any risks or side effects.
            Keep the explanation under 150 words.
            """),
            .user("Explain this command:\n\(command)"),
        ]

        let response = try await aiService.chatCompletion(
            messages: messages,
            model: model,
            maxTokens: 300,
            temperature: 0.2
        )

        return response.content
    }

    // MARK: - Suggest Fix for Failed Command

    public func suggestFix(
        command: String,
        exitCode: Int32,
        output: String,
        model: ModelConfiguration
    ) async throws -> NLCommandResponse {
        let messages: [ChatMessage] = [
            .system("""
            You are a shell command expert running on macOS.
            A command failed. Analyze the error and suggest a fix.
            Respond in this exact JSON format:
            {
              "commands": [{"command": "fixed command", "explanation": "what was wrong and how this fixes it"}],
              "explanation": "Brief summary of the issue",
              "alternatives": []
            }
            Only output valid JSON, nothing else.
            """),
            .user("""
            Failed command: \(command)
            Exit code: \(exitCode)
            Output:
            \(String(output.suffix(1000)))
            """),
        ]

        let response = try await aiService.chatCompletion(
            messages: messages,
            model: model,
            maxTokens: 512,
            temperature: 0.3
        )

        return parseCommandResponse(response.content, requestID: UUID())
    }

    // MARK: - Update Context

    public func updateContext(directory: String, recentCommand: String, output: String?) {
        sessionContext.currentDirectory = directory
        sessionContext.recentCommands.append(recentCommand)
        if sessionContext.recentCommands.count > 20 {
            sessionContext.recentCommands.removeFirst()
        }
        if let output {
            sessionContext.recentOutputs.append(String(output.prefix(500)))
            if sessionContext.recentOutputs.count > 10 {
                sessionContext.recentOutputs.removeFirst()
            }
        }
    }

    public func updateProjectType(_ type: ProjectType?) {
        sessionContext.projectType = type
    }

    public func resetContext() {
        sessionContext = AISessionContext()
    }

    // MARK: - Prompt Building

    private func buildPromptMessages(for request: NLCommandRequest) -> [ChatMessage] {
        var messages: [ChatMessage] = []

        // System prompt
        messages.append(.system("""
        You are Terminus AI, an intelligent shell command generator for macOS.
        Your job is to convert natural language requests into safe, correct shell commands.

        Rules:
        1. Generate commands for macOS (zsh/bash compatible)
        2. Prefer safe, non-destructive operations when possible
        3. Use standard macOS tools (no assuming third-party tools unless the user mentions them)
        4. If a task requires multiple steps, list them in order
        5. Always explain what each command does
        6. Flag any destructive operations clearly
        7. Never generate commands that could harm the system without explicit warnings

        Respond ONLY with valid JSON in this exact format:
        {
          "commands": [
            {"command": "the shell command", "explanation": "what it does"}
          ],
          "explanation": "Brief overall explanation",
          "alternatives": [
            {"command": "alternative approach", "explanation": "why this alternative"}
          ]
        }

        Context:
        - OS: macOS (Darwin)
        - Shell: \(request.shell)
        - Current directory: \(request.currentDirectory)
        \(request.projectType.map { "- Project type: \($0.rawValue)" } ?? "")
        \(request.directoryContents.map { "- Directory contents: \($0.prefix(20).joined(separator: ", "))" } ?? "")
        """))

        // Add session conversation history for context
        for msg in sessionContext.conversationHistory.suffix(6) {
            switch msg.role {
            case .user:
                messages.append(.user(msg.content))
            case .assistant:
                messages.append(.assistant(msg.content))
            case .system:
                break
            }
        }

        // Add recent commands context
        if !request.previousCommands.isEmpty {
            let recentContext = request.previousCommands.suffix(5).joined(separator: "\n")
            messages.append(.system("Recent commands in this session:\n\(recentContext)"))
        }

        // The actual user request
        messages.append(.user(request.query))

        return messages
    }

    // MARK: - Response Parsing

    private func parseCommandResponse(_ content: String, requestID: UUID) -> NLCommandResponse {
        // Try to extract JSON from the response
        let jsonString = extractJSON(from: content)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback: treat entire content as a single command explanation
            return NLCommandResponse(
                requestID: requestID,
                commands: [],
                explanation: content
            )
        }

        var commands: [GeneratedCommand] = []
        var alternatives: [GeneratedCommand] = []

        if let cmdArray = json["commands"] as? [[String: Any]] {
            for (index, cmd) in cmdArray.enumerated() {
                if let command = cmd["command"] as? String {
                    let explanation = cmd["explanation"] as? String
                    let safetyResult = SafetyAnalyzer.analyze(command)
                    commands.append(GeneratedCommand(
                        command: command,
                        explanation: explanation,
                        safetyLevel: safetyResult.level,
                        warnings: safetyResult.warnings,
                        stepNumber: cmdArray.count > 1 ? index + 1 : nil
                    ))
                }
            }
        }

        if let altArray = json["alternatives"] as? [[String: Any]] {
            for alt in altArray {
                if let command = alt["command"] as? String {
                    let explanation = alt["explanation"] as? String
                    let safetyResult = SafetyAnalyzer.analyze(command)
                    alternatives.append(GeneratedCommand(
                        command: command,
                        explanation: explanation,
                        safetyLevel: safetyResult.level,
                        warnings: safetyResult.warnings
                    ))
                }
            }
        }

        let explanation = json["explanation"] as? String ?? "Command generated successfully."

        return NLCommandResponse(
            requestID: requestID,
            commands: commands,
            explanation: explanation,
            alternatives: alternatives,
            isMultiStep: commands.count > 1
        )
    }

    private func extractJSON(from text: String) -> String {
        // Try to find JSON block in the response
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}

// MARK: - Model Listing

extension AIServiceClient {
    /// Fetch available models from OpenRouter
    public func listModels() async throws -> [OpenRouterModel] {
        let apiKey = try getAPIKey()

        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            throw AIServiceError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Terminus", forHTTPHeaderField: "X-Title")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        let tempSession = URLSession(configuration: config)

        let (data, response) = try await tempSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.networkError("Failed to fetch models")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw AIServiceError.decodingError("Invalid models response")
        }

        return dataArray.compactMap { item in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else { return nil }
            let ctxLen = item["context_length"] as? Int
            var pricing: ModelPricing?
            if let p = item["pricing"] as? [String: Any] {
                pricing = ModelPricing(
                    prompt: p["prompt"] as? String,
                    completion: p["completion"] as? String
                )
            }
            return OpenRouterModel(id: id, name: name, contextLength: ctxLen, pricing: pricing)
        }
    }

    /// Validate the stored API key by making a test request
    public func validateAPIKey() async throws -> Bool {
        _ = try await listModels()
        return true
    }
}
