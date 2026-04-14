import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// MARK: - SQLite Value

public enum SQLiteValue: Sendable, CustomStringConvertible {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var description: String {
        switch self {
        case .null: "NULL"
        case .integer(let v): "\(v)"
        case .real(let v): "\(v)"
        case .text(let v): "'\(v)'"
        case .blob(let v): "<\(v.count) bytes>"
        }
    }

    public var intValue: Int64? {
        if case .integer(let v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        if case .real(let v) = self { return v }
        return nil
    }

    public var stringValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    public var blobValue: Data? {
        if case .blob(let v) = self { return v }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - SQLite Error

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String, Int32)
    case prepareFailed(String, String)
    case executionFailed(String, String)
    case bindFailed(Int, String)
    case transactionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let path, let code):
            "Failed to open database at \(path): error code \(code)"
        case .prepareFailed(let sql, let msg):
            "Failed to prepare SQL: \(sql) — \(msg)"
        case .executionFailed(let sql, let msg):
            "SQL execution failed: \(sql) — \(msg)"
        case .bindFailed(let index, let msg):
            "Failed to bind parameter at index \(index): \(msg)"
        case .transactionFailed(let msg):
            "Transaction failed: \(msg)"
        }
    }
}

// MARK: - SQLite Database

public final class SQLiteDatabase: @unchecked Sendable {
    private let db: OpaquePointer
    private let queue = DispatchQueue(label: "com.terminus.sqlite", qos: .userInitiated)

    public init(path: String) throws {
        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &dbPointer, flags, nil)

        guard result == SQLITE_OK, let db = dbPointer else {
            if let dbPointer {
                sqlite3_close(dbPointer)
            }
            throw SQLiteError.openFailed(path, result)
        }

        self.db = db

        // Enable WAL mode for better concurrent performance
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Execute (no results)

    public func execute(_ sql: String, parameters: [SQLiteValue] = []) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(sql, errorMessage())
            }

            try bindParameters(stmt!, parameters: parameters, sql: sql)

            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE || result == SQLITE_ROW else {
                throw SQLiteError.executionFailed(sql, errorMessage())
            }
        }
    }

    // MARK: - Query (returns rows)

    public func query(
        _ sql: String,
        parameters: [SQLiteValue] = []
    ) throws -> [[String: SQLiteValue]] {
        try queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(sql, errorMessage())
            }

            try bindParameters(stmt!, parameters: parameters, sql: sql)

            var rows: [[String: SQLiteValue]] = []
            let columnCount = sqlite3_column_count(stmt)

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: SQLiteValue] = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    row[name] = columnValue(stmt!, index: i)
                }
                rows.append(row)
            }

            return rows
        }
    }

    // MARK: - Transaction

    public func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN TRANSACTION")
        do {
            try block()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw SQLiteError.transactionFailed(error.localizedDescription)
        }
    }

    // MARK: - Scalar query

    public func scalar(_ sql: String, parameters: [SQLiteValue] = []) throws -> SQLiteValue {
        let rows = try query(sql, parameters: parameters)
        guard let firstRow = rows.first, let firstValue = firstRow.values.first else {
            return .null
        }
        return firstValue
    }

    // MARK: - Private Helpers

    private func errorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func bindParameters(
        _ stmt: OpaquePointer,
        parameters: [SQLiteValue],
        sql: String
    ) throws {
        for (index, param) in parameters.enumerated() {
            let sqlIndex = Int32(index + 1)
            let result: Int32

            switch param {
            case .null:
                result = sqlite3_bind_null(stmt, sqlIndex)
            case .integer(let value):
                result = sqlite3_bind_int64(stmt, sqlIndex, value)
            case .real(let value):
                result = sqlite3_bind_double(stmt, sqlIndex, value)
            case .text(let value):
                result = sqlite3_bind_text(
                    stmt, sqlIndex, value, -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
            case .blob(let value):
                result = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(
                        stmt, sqlIndex,
                        buffer.baseAddress, Int32(buffer.count),
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    )
                }
            }

            guard result == SQLITE_OK else {
                throw SQLiteError.bindFailed(index, errorMessage())
            }
        }
    }

    private func columnValue(_ stmt: OpaquePointer, index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            let text = String(cString: sqlite3_column_text(stmt, index))
            return .text(text)
        case SQLITE_BLOB:
            let bytes = sqlite3_column_bytes(stmt, index)
            if let blob = sqlite3_column_blob(stmt, index) {
                return .blob(Data(bytes: blob, count: Int(bytes)))
            }
            return .blob(Data())
        default:
            return .null
        }
    }
}
