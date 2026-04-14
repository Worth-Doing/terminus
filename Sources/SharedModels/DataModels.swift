import Foundation

// MARK: - Terminal Session

public struct TerminalSession: Identifiable, Sendable, Codable {
    public let id: SessionID
    public var startedAt: Date
    public var endedAt: Date?
    public var initialDirectory: String
    public var shell: String

    public init(
        id: SessionID = UUID().uuidString,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        initialDirectory: String,
        shell: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.initialDirectory = initialDirectory
        self.shell = shell
    }
}

// MARK: - Command Entry

public struct CommandEntry: Identifiable, Sendable, Codable {
    public let id: String
    public var command: String
    public var workingDirectory: String
    public var shell: String
    public var exitCode: Int32?
    public var startedAt: Date
    public var finishedAt: Date?
    public var durationMs: Int?
    public var sessionID: SessionID
    public var hostname: String?
    public var projectType: ProjectType?
    public var gitBranch: String?

    public init(
        id: String = UUID().uuidString,
        command: String,
        workingDirectory: String,
        shell: String,
        exitCode: Int32? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        durationMs: Int? = nil,
        sessionID: SessionID,
        hostname: String? = nil,
        projectType: ProjectType? = nil,
        gitBranch: String? = nil
    ) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.sessionID = sessionID
        self.hostname = hostname
        self.projectType = projectType
        self.gitBranch = gitBranch
    }
}

// MARK: - Saved Command

public struct SavedCommand: Identifiable, Sendable, Codable {
    public let id: String
    public var name: String
    public var commandTemplate: String
    public var description: String?
    public var tags: [String]
    public var parameters: [ParameterDefinition]
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        commandTemplate: String,
        description: String? = nil,
        tags: [String] = [],
        parameters: [ParameterDefinition] = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.commandTemplate = commandTemplate
        self.description = description
        self.tags = tags
        self.parameters = parameters
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

// MARK: - Parameter Definition

public struct ParameterDefinition: Sendable, Codable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var defaultValue: String?
    public var options: [String]?
    public var description: String?
    public var required: Bool

    public init(
        name: String,
        defaultValue: String? = nil,
        options: [String]? = nil,
        description: String? = nil,
        required: Bool = true
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.options = options
        self.description = description
        self.required = required
    }
}

// MARK: - Workflow

public struct WorkflowSequence: Identifiable, Sendable, Codable {
    public let id: String
    public var name: String
    public var description: String?
    public var steps: [WorkflowStep]
    public var tags: [String]
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        steps: [WorkflowStep] = [],
        tags: [String] = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.steps = steps
        self.tags = tags
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct WorkflowStep: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public var command: String
    public var description: String?
    public var continueOnError: Bool
    public var delayAfterMs: Int?

    public init(
        id: String = UUID().uuidString,
        command: String,
        description: String? = nil,
        continueOnError: Bool = false,
        delayAfterMs: Int? = nil
    ) {
        self.id = id
        self.command = command
        self.description = description
        self.continueOnError = continueOnError
        self.delayAfterMs = delayAfterMs
    }
}

// MARK: - Command Embedding

public struct CommandEmbedding: Identifiable, Sendable {
    public let id: String
    public var commandHistoryID: String?
    public var savedCommandID: String?
    public var contentText: String
    public var embedding: [Float]
    public var model: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        commandHistoryID: String? = nil,
        savedCommandID: String? = nil,
        contentText: String,
        embedding: [Float],
        model: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.commandHistoryID = commandHistoryID
        self.savedCommandID = savedCommandID
        self.contentText = contentText
        self.embedding = embedding
        self.model = model
        self.createdAt = createdAt
    }
}

// MARK: - Project Type

public enum ProjectType: String, Sendable, Codable, CaseIterable {
    case node
    case rust
    case python
    case swift
    case go
    case ruby
    case java
    case dotnet
    case unknown
}
