import Foundation
import SharedModels

// MARK: - Migration

public struct Migration: Sendable {
    public let version: Int
    public let sql: String

    public init(version: Int, sql: String) {
        self.version = version
        self.sql = sql
    }
}

// MARK: - Schema Manager

public final class SchemaManager: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func initialize() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER NOT NULL
            )
        """)

        let rows = try db.query("SELECT version FROM schema_version")
        if rows.isEmpty {
            try db.execute("INSERT INTO schema_version (version) VALUES (0)")
        }

        try runMigrations()
    }

    private func currentVersion() throws -> Int {
        let result = try db.scalar("SELECT version FROM schema_version")
        return Int(result.intValue ?? 0)
    }

    private func runMigrations() throws {
        let current = try currentVersion()

        for migration in Self.migrations where migration.version > current {
            try db.transaction {
                // Split by semicolons and execute each statement
                let statements = migration.sql
                    .components(separatedBy: ";")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                for statement in statements {
                    try db.execute(statement)
                }

                try db.execute(
                    "UPDATE schema_version SET version = ?",
                    parameters: [.integer(Int64(migration.version))]
                )
            }
        }
    }

    // MARK: - Migrations

    static let migrations: [Migration] = [
        Migration(version: 1, sql: """
            CREATE TABLE terminal_sessions (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL,
                initial_directory TEXT NOT NULL,
                shell TEXT NOT NULL
            );

            CREATE TABLE command_history (
                id TEXT PRIMARY KEY,
                command TEXT NOT NULL,
                working_directory TEXT NOT NULL,
                shell TEXT NOT NULL,
                exit_code INTEGER,
                started_at REAL NOT NULL,
                finished_at REAL,
                duration_ms INTEGER,
                session_id TEXT NOT NULL,
                hostname TEXT,
                project_type TEXT,
                git_branch TEXT,
                FOREIGN KEY (session_id) REFERENCES terminal_sessions(id)
            );

            CREATE INDEX idx_history_command ON command_history(command);
            CREATE INDEX idx_history_directory ON command_history(working_directory);
            CREATE INDEX idx_history_started ON command_history(started_at DESC);

            CREATE TABLE saved_commands (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                command_template TEXT NOT NULL,
                description TEXT,
                tags TEXT,
                parameters TEXT,
                created_at REAL NOT NULL,
                last_used_at REAL,
                use_count INTEGER DEFAULT 0
            );

            CREATE TABLE workflow_sequences (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                steps TEXT NOT NULL,
                tags TEXT,
                created_at REAL NOT NULL,
                last_used_at REAL
            );

            CREATE TABLE command_embeddings (
                id TEXT PRIMARY KEY,
                command_history_id TEXT,
                saved_command_id TEXT,
                content_text TEXT NOT NULL,
                embedding BLOB NOT NULL,
                model TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY (command_history_id) REFERENCES command_history(id),
                FOREIGN KEY (saved_command_id) REFERENCES saved_commands(id)
            );

            CREATE TABLE command_ngrams (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                gram_size INTEGER NOT NULL,
                context TEXT NOT NULL,
                prediction TEXT NOT NULL,
                count INTEGER DEFAULT 1,
                last_seen REAL NOT NULL,
                directory_pattern TEXT,
                UNIQUE(gram_size, context, prediction, directory_pattern)
            );

            CREATE INDEX idx_ngrams_context ON command_ngrams(context);

            CREATE TABLE prediction_feedback (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                predicted_command TEXT NOT NULL,
                was_accepted INTEGER NOT NULL,
                context_directory TEXT,
                context_previous_command TEXT,
                timestamp REAL NOT NULL
            );

            CREATE TABLE user_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE model_configurations (
                id TEXT PRIMARY KEY,
                provider TEXT NOT NULL DEFAULT 'openrouter',
                model_id TEXT NOT NULL,
                purpose TEXT NOT NULL,
                display_name TEXT,
                max_tokens INTEGER,
                temperature REAL,
                is_default INTEGER DEFAULT 0
            )
        """),

        Migration(version: 2, sql: """
            CREATE INDEX IF NOT EXISTS idx_embeddings_history_id
                ON command_embeddings(command_history_id);

            CREATE INDEX IF NOT EXISTS idx_ngrams_gram_context
                ON command_ngrams(gram_size, context);

            CREATE INDEX IF NOT EXISTS idx_history_command_dir
                ON command_history(command, working_directory);

            CREATE INDEX IF NOT EXISTS idx_feedback_predicted
                ON prediction_feedback(predicted_command)
        """),
    ]
}

// MARK: - Data Access

public final class DataAccess: Sendable {
    public let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    /// Default database path
    public static var defaultDatabasePath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.path
        return "\(appSupport)/Terminus/terminus.db"
    }

    /// Create with default path and initialize schema
    public static func createDefault() throws -> DataAccess {
        let db = try SQLiteDatabase(path: defaultDatabasePath)
        let schema = SchemaManager(database: db)
        try schema.initialize()
        return DataAccess(database: db)
    }
}
