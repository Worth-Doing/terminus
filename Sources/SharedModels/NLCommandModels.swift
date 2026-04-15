import Foundation

// MARK: - Intent Detection

public enum InputIntent: String, Sendable, Codable {
    case rawCommand       // Regular shell command
    case naturalLanguage  // Natural language request
}

// MARK: - Command Safety

public enum CommandSafetyLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case safe         // Non-destructive, read-only
    case moderate     // May modify files but reversible
    case dangerous    // Destructive or system-level
    case critical     // Could cause data loss or system instability

    public static func < (lhs: CommandSafetyLevel, rhs: CommandSafetyLevel) -> Bool {
        let order: [CommandSafetyLevel] = [.safe, .moderate, .dangerous, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct SafetyWarning: Identifiable, Sendable {
    public let id: UUID
    public let level: CommandSafetyLevel
    public let message: String
    public let detail: String?

    public init(
        id: UUID = UUID(),
        level: CommandSafetyLevel,
        message: String,
        detail: String? = nil
    ) {
        self.id = id
        self.level = level
        self.message = message
        self.detail = detail
    }
}

// MARK: - NL Command Request

public struct NLCommandRequest: Identifiable, Sendable {
    public let id: UUID
    public let query: String
    public let currentDirectory: String
    public let shell: String
    public let previousCommands: [String]
    public let directoryContents: [String]?
    public let projectType: ProjectType?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        query: String,
        currentDirectory: String,
        shell: String = "/bin/zsh",
        previousCommands: [String] = [],
        directoryContents: [String]? = nil,
        projectType: ProjectType? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.currentDirectory = currentDirectory
        self.shell = shell
        self.previousCommands = previousCommands
        self.directoryContents = directoryContents
        self.projectType = projectType
        self.timestamp = timestamp
    }
}

// MARK: - NL Command Response

public struct NLCommandResponse: Identifiable, Sendable {
    public let id: UUID
    public let requestID: UUID
    public let commands: [GeneratedCommand]
    public let explanation: String
    public let alternatives: [GeneratedCommand]
    public let isMultiStep: Bool
    public let model: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        requestID: UUID,
        commands: [GeneratedCommand],
        explanation: String,
        alternatives: [GeneratedCommand] = [],
        isMultiStep: Bool = false,
        model: String = "",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.requestID = requestID
        self.commands = commands
        self.explanation = explanation
        self.alternatives = alternatives
        self.isMultiStep = isMultiStep
        self.model = model
        self.timestamp = timestamp
    }
}

// MARK: - Generated Command

public struct GeneratedCommand: Identifiable, Sendable {
    public let id: UUID
    public let command: String
    public let explanation: String?
    public let safetyLevel: CommandSafetyLevel
    public let warnings: [SafetyWarning]
    public let stepNumber: Int?

    public init(
        id: UUID = UUID(),
        command: String,
        explanation: String? = nil,
        safetyLevel: CommandSafetyLevel = .safe,
        warnings: [SafetyWarning] = [],
        stepNumber: Int? = nil
    ) {
        self.id = id
        self.command = command
        self.explanation = explanation
        self.safetyLevel = safetyLevel
        self.warnings = warnings
        self.stepNumber = stepNumber
    }
}

// MARK: - Command Block (Block-Based Output)

public struct CommandBlock: Identifiable, Sendable {
    public let id: UUID
    public var input: String
    public var output: String
    public var exitCode: Int32?
    public var startedAt: Date
    public var finishedAt: Date?
    public var workingDirectory: String
    public var isCollapsed: Bool
    public var blockType: BlockType

    public enum BlockType: String, Sendable, Codable {
        case standard     // Normal command execution
        case aiGenerated  // AI-generated command
        case aiExplanation // AI explanation block
        case error        // Error output
        case system       // System message
    }

    public init(
        id: UUID = UUID(),
        input: String,
        output: String = "",
        exitCode: Int32? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        workingDirectory: String = "",
        isCollapsed: Bool = false,
        blockType: BlockType = .standard
    ) {
        self.id = id
        self.input = input
        self.output = output
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.workingDirectory = workingDirectory
        self.isCollapsed = isCollapsed
        self.blockType = blockType
    }

    public var duration: TimeInterval? {
        guard let finished = finishedAt else { return nil }
        return finished.timeIntervalSince(startedAt)
    }

    public var isSuccess: Bool {
        exitCode == 0
    }

    public var isRunning: Bool {
        finishedAt == nil && exitCode == nil
    }
}

// MARK: - AI Session Context (Session Memory)

public struct AISessionContext: Sendable {
    public var conversationHistory: [AIContextMessage]
    public var currentDirectory: String
    public var recentCommands: [String]
    public var recentOutputs: [String]
    public var projectType: ProjectType?

    public init(
        conversationHistory: [AIContextMessage] = [],
        currentDirectory: String = "",
        recentCommands: [String] = [],
        recentOutputs: [String] = [],
        projectType: ProjectType? = nil
    ) {
        self.conversationHistory = conversationHistory
        self.currentDirectory = currentDirectory
        self.recentCommands = recentCommands
        self.recentOutputs = recentOutputs
        self.projectType = projectType
    }

    public mutating func addExchange(query: String, commands: [String], output: String?) {
        conversationHistory.append(AIContextMessage(role: .user, content: query))
        let cmdText = commands.joined(separator: "\n")
        var response = "Commands: \(cmdText)"
        if let output {
            response += "\nOutput: \(String(output.prefix(500)))"
        }
        conversationHistory.append(AIContextMessage(role: .assistant, content: response))

        // Keep only last 10 exchanges
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }
    }
}

public struct AIContextMessage: Sendable {
    public let role: AIContextRole
    public let content: String

    public init(role: AIContextRole, content: String) {
        self.role = role
        self.content = content
    }
}

public enum AIContextRole: String, Sendable {
    case user
    case assistant
    case system
}

// MARK: - OpenRouter Model Info

public struct OpenRouterModel: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let contextLength: Int?
    public let pricing: ModelPricing?

    public init(
        id: String,
        name: String,
        contextLength: Int? = nil,
        pricing: ModelPricing? = nil
    ) {
        self.id = id
        self.name = name
        self.contextLength = contextLength
        self.pricing = pricing
    }
}

public struct ModelPricing: Sendable, Codable {
    public let prompt: String?
    public let completion: String?

    public init(prompt: String? = nil, completion: String? = nil) {
        self.prompt = prompt
        self.completion = completion
    }
}

// MARK: - User Settings Extensions

public struct SafetySettings: Sendable, Codable {
    public var requireConfirmation: CommandSafetyLevel
    public var blockExecution: CommandSafetyLevel
    public var showWarnings: Bool

    public init(
        requireConfirmation: CommandSafetyLevel = .dangerous,
        blockExecution: CommandSafetyLevel = .critical,
        showWarnings: Bool = true
    ) {
        self.requireConfirmation = requireConfirmation
        self.blockExecution = blockExecution
        self.showWarnings = showWarnings
    }
}
