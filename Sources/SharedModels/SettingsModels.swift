import Foundation

// MARK: - User Settings

public struct UserSettings: Sendable, Codable {
    public var defaultShell: String
    public var startupDirectory: String
    public var theme: String
    public var fontSize: Double
    public var fontFamily: String?
    public var scrollbackLimit: Int
    public var cursorStyle: CursorStyle
    public var enableBell: Bool
    public var enableAI: Bool
    public var autoEmbed: Bool
    public var predictionEnabled: Bool

    public init(
        defaultShell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        startupDirectory: String = "~",
        theme: String = "defaultDark",
        fontSize: Double = 14,
        fontFamily: String? = nil,
        scrollbackLimit: Int = 10_000,
        cursorStyle: CursorStyle = .block,
        enableBell: Bool = true,
        enableAI: Bool = false,
        autoEmbed: Bool = true,
        predictionEnabled: Bool = true
    ) {
        self.defaultShell = defaultShell
        self.startupDirectory = startupDirectory
        self.theme = theme
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.scrollbackLimit = scrollbackLimit
        self.cursorStyle = cursorStyle
        self.enableBell = enableBell
        self.enableAI = enableAI
        self.autoEmbed = autoEmbed
        self.predictionEnabled = predictionEnabled
    }

    public static let defaults = UserSettings()
}

// MARK: - Model Configuration

public struct ModelConfiguration: Identifiable, Sendable, Codable {
    public let id: String
    public var provider: String
    public var modelID: String
    public var purpose: ModelPurpose
    public var displayName: String?
    public var maxTokens: Int?
    public var temperature: Double?
    public var isDefault: Bool

    public init(
        id: String = UUID().uuidString,
        provider: String = "openrouter",
        modelID: String,
        purpose: ModelPurpose,
        displayName: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.modelID = modelID
        self.purpose = purpose
        self.displayName = displayName
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.isDefault = isDefault
    }
}

public enum ModelPurpose: String, Sendable, Codable {
    case chat
    case embedding
}

// MARK: - Default Models

public enum DefaultModels {
    public static let chat = ModelConfiguration(
        id: "default-chat",
        provider: "openrouter",
        modelID: "anthropic/claude-sonnet-4",
        purpose: .chat,
        displayName: "Claude Sonnet",
        maxTokens: 4096,
        temperature: 0.7,
        isDefault: true
    )

    public static let embedding = ModelConfiguration(
        id: "default-embedding",
        provider: "openrouter",
        modelID: "openai/text-embedding-3-small",
        purpose: .embedding,
        displayName: "text-embedding-3-small",
        isDefault: true
    )
}

// MARK: - Prediction

public struct Prediction: Identifiable, Sendable {
    public let id: UUID
    public let command: String
    public let score: Double
    public let source: PredictionSource
    public let explanation: String?

    public init(
        id: UUID = UUID(),
        command: String,
        score: Double,
        source: PredictionSource,
        explanation: String? = nil
    ) {
        self.id = id
        self.command = command
        self.score = score
        self.source = source
        self.explanation = explanation
    }
}

public enum PredictionSource: String, Sendable, Codable {
    case frequencyHistory
    case ngramSequence
    case directoryContext
    case savedCommand
    case aiSuggestion
}

// MARK: - Prediction Context

public struct PredictionContext: Sendable {
    public var prefix: String
    public var currentDirectory: String
    public var previousCommand: String?
    public var projectType: ProjectType?

    public init(
        prefix: String,
        currentDirectory: String,
        previousCommand: String? = nil,
        projectType: ProjectType? = nil
    ) {
        self.prefix = prefix
        self.currentDirectory = currentDirectory
        self.previousCommand = previousCommand
        self.projectType = projectType
    }
}
