import Foundation
import SharedModels
import DataStore

// MARK: - History Engine

@Observable
public final class HistoryEngine: @unchecked Sendable {
    private let dataAccess: DataAccess

    public init(dataAccess: DataAccess) {
        self.dataAccess = dataAccess
    }

    // MARK: - Record

    public func record(_ entry: CommandEntry) throws {
        try dataAccess.db.execute(
            """
            INSERT INTO command_history
                (id, command, working_directory, shell, exit_code, started_at,
                 finished_at, duration_ms, session_id, hostname, project_type, git_branch)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                .text(entry.id),
                .text(entry.command),
                .text(entry.workingDirectory),
                .text(entry.shell),
                entry.exitCode.map { .integer(Int64($0)) } ?? .null,
                .real(entry.startedAt.timeIntervalSince1970),
                entry.finishedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                entry.durationMs.map { .integer(Int64($0)) } ?? .null,
                .text(entry.sessionID),
                entry.hostname.map { .text($0) } ?? .null,
                entry.projectType.map { .text($0.rawValue) } ?? .null,
                entry.gitBranch.map { .text($0) } ?? .null,
            ]
        )
    }

    // MARK: - Search

    public func search(query: String, limit: Int = 50) throws -> [CommandEntry] {
        let rows = try dataAccess.db.query(
            """
            SELECT * FROM command_history
            WHERE command LIKE ?
            ORDER BY started_at DESC
            LIMIT ?
            """,
            parameters: [.text("%\(query)%"), .integer(Int64(limit))]
        )
        return rows.compactMap { rowToCommandEntry($0) }
    }

    // MARK: - Recent

    public func recentCommands(limit: Int = 100) throws -> [CommandEntry] {
        let rows = try dataAccess.db.query(
            """
            SELECT * FROM command_history
            ORDER BY started_at DESC
            LIMIT ?
            """,
            parameters: [.integer(Int64(limit))]
        )
        return rows.compactMap { rowToCommandEntry($0) }
    }

    // MARK: - Directory

    public func commandsInDirectory(_ directory: String, limit: Int = 50) throws -> [CommandEntry] {
        let rows = try dataAccess.db.query(
            """
            SELECT * FROM command_history
            WHERE working_directory = ?
            ORDER BY started_at DESC
            LIMIT ?
            """,
            parameters: [.text(directory), .integer(Int64(limit))]
        )
        return rows.compactMap { rowToCommandEntry($0) }
    }

    // MARK: - Frequency Map

    public func frequencyMap(limit: Int = 500) throws -> [String: Int] {
        let rows = try dataAccess.db.query(
            """
            SELECT command, COUNT(*) as freq FROM command_history
            GROUP BY command
            ORDER BY freq DESC
            LIMIT ?
            """,
            parameters: [.integer(Int64(limit))]
        )

        var map: [String: Int] = [:]
        for row in rows {
            if let cmd = row["command"]?.stringValue,
               let freq = row["freq"]?.intValue {
                map[cmd] = Int(freq)
            }
        }
        return map
    }

    // MARK: - N-gram Recording

    public func recordNgram(
        context: String,
        prediction: String,
        gramSize: Int,
        directory: String?
    ) throws {
        try dataAccess.db.execute(
            """
            INSERT INTO command_ngrams (gram_size, context, prediction, count, last_seen, directory_pattern)
            VALUES (?, ?, ?, 1, ?, ?)
            ON CONFLICT(gram_size, context, prediction, directory_pattern)
            DO UPDATE SET count = count + 1, last_seen = ?
            """,
            parameters: [
                .integer(Int64(gramSize)),
                .text(context),
                .text(prediction),
                .real(Date().timeIntervalSince1970),
                directory.map { .text($0) } ?? .null,
                .real(Date().timeIntervalSince1970),
            ]
        )
    }

    // MARK: - Private

    private func rowToCommandEntry(_ row: [String: SQLiteValue]) -> CommandEntry? {
        guard let id = row["id"]?.stringValue,
              let command = row["command"]?.stringValue,
              let directory = row["working_directory"]?.stringValue,
              let shell = row["shell"]?.stringValue,
              let startedAt = row["started_at"]?.doubleValue,
              let sessionID = row["session_id"]?.stringValue else {
            return nil
        }

        return CommandEntry(
            id: id,
            command: command,
            workingDirectory: directory,
            shell: shell,
            exitCode: row["exit_code"]?.intValue.map { Int32($0) },
            startedAt: Date(timeIntervalSince1970: startedAt),
            finishedAt: row["finished_at"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
            durationMs: row["duration_ms"]?.intValue.map { Int($0) },
            sessionID: sessionID,
            hostname: row["hostname"]?.stringValue,
            projectType: row["project_type"]?.stringValue.flatMap { ProjectType(rawValue: $0) },
            gitBranch: row["git_branch"]?.stringValue
        )
    }
}
