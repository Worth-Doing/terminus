import Foundation
import SharedModels
import DataStore

// MARK: - Saved Commands Manager

@Observable
public final class SavedCommandsManager: @unchecked Sendable {
    private let dataAccess: DataAccess

    public init(dataAccess: DataAccess) {
        self.dataAccess = dataAccess
    }

    // MARK: - CRUD

    public func save(_ command: SavedCommand) throws {
        let tagsJSON = try JSONEncoder().encode(command.tags)
        let paramsJSON = try JSONEncoder().encode(command.parameters)

        try dataAccess.db.execute(
            """
            INSERT OR REPLACE INTO saved_commands
                (id, name, command_template, description, tags, parameters,
                 created_at, last_used_at, use_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                .text(command.id),
                .text(command.name),
                .text(command.commandTemplate),
                command.description.map { .text($0) } ?? .null,
                .text(String(data: tagsJSON, encoding: .utf8) ?? "[]"),
                .text(String(data: paramsJSON, encoding: .utf8) ?? "[]"),
                .real(command.createdAt.timeIntervalSince1970),
                command.lastUsedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                .integer(Int64(command.useCount)),
            ]
        )
    }

    public func delete(id: String) throws {
        try dataAccess.db.execute(
            "DELETE FROM saved_commands WHERE id = ?",
            parameters: [.text(id)]
        )
    }

    public func list(tags: [String]? = nil) throws -> [SavedCommand] {
        let rows: [[String: SQLiteValue]]

        if let tags, !tags.isEmpty {
            // Filter by any matching tag
            let placeholders = tags.map { _ in "tags LIKE ?" }.joined(separator: " OR ")
            let params = tags.map { SQLiteValue.text("%\"\($0)\"%") }
            rows = try dataAccess.db.query(
                "SELECT * FROM saved_commands WHERE \(placeholders) ORDER BY use_count DESC",
                parameters: params
            )
        } else {
            rows = try dataAccess.db.query(
                "SELECT * FROM saved_commands ORDER BY use_count DESC"
            )
        }

        return rows.compactMap { rowToSavedCommand($0) }
    }

    public func search(query: String) throws -> [SavedCommand] {
        let rows = try dataAccess.db.query(
            """
            SELECT * FROM saved_commands
            WHERE name LIKE ? OR command_template LIKE ? OR description LIKE ?
            ORDER BY use_count DESC
            """,
            parameters: [
                .text("%\(query)%"),
                .text("%\(query)%"),
                .text("%\(query)%"),
            ]
        )
        return rows.compactMap { rowToSavedCommand($0) }
    }

    // MARK: - Template Resolution

    public func resolve(_ command: SavedCommand, parameters: [String: String]) -> String {
        var result = command.commandTemplate
        for param in command.parameters {
            let value = parameters[param.name] ?? param.defaultValue ?? ""
            result = result.replacingOccurrences(of: "{{\(param.name)}}", with: value)
        }
        return result
    }

    // MARK: - Private

    private func rowToSavedCommand(_ row: [String: SQLiteValue]) -> SavedCommand? {
        guard let id = row["id"]?.stringValue,
              let name = row["name"]?.stringValue,
              let template = row["command_template"]?.stringValue,
              let createdAt = row["created_at"]?.doubleValue else {
            return nil
        }

        let tags: [String]
        if let tagsStr = row["tags"]?.stringValue,
           let data = tagsStr.data(using: .utf8) {
            tags = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else {
            tags = []
        }

        let parameters: [ParameterDefinition]
        if let paramsStr = row["parameters"]?.stringValue,
           let data = paramsStr.data(using: .utf8) {
            parameters = (try? JSONDecoder().decode([ParameterDefinition].self, from: data)) ?? []
        } else {
            parameters = []
        }

        return SavedCommand(
            id: id,
            name: name,
            commandTemplate: template,
            description: row["description"]?.stringValue,
            tags: tags,
            parameters: parameters,
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastUsedAt: row["last_used_at"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
            useCount: row["use_count"]?.intValue.map { Int($0) } ?? 0
        )
    }
}
