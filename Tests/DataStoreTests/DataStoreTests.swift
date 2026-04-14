import XCTest
@testable import DataStore

final class DataStoreTests: XCTestCase {

    func testCreateAndQueryDatabase() throws {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = try SQLiteDatabase(path: path)

        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute(
            "INSERT INTO test (name) VALUES (?)",
            parameters: [.text("hello")]
        )

        let rows = try db.query("SELECT * FROM test")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"]?.stringValue, "hello")
    }

    func testSchemaInitialization() throws {
        let path = NSTemporaryDirectory() + "test_schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = try SQLiteDatabase(path: path)
        let schema = SchemaManager(database: db)
        try schema.initialize()

        let tables = try db.query(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
        let tableNames = tables.compactMap { $0["name"]?.stringValue }

        XCTAssertTrue(tableNames.contains("command_history"))
        XCTAssertTrue(tableNames.contains("saved_commands"))
        XCTAssertTrue(tableNames.contains("terminal_sessions"))
        XCTAssertTrue(tableNames.contains("command_embeddings"))
        XCTAssertTrue(tableNames.contains("command_ngrams"))
        XCTAssertTrue(tableNames.contains("prediction_feedback"))
        XCTAssertTrue(tableNames.contains("user_settings"))
        XCTAssertTrue(tableNames.contains("model_configurations"))
    }

    func testTransactionRollback() throws {
        let path = NSTemporaryDirectory() + "test_tx_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
        try db.execute("INSERT INTO test (name) VALUES (?)", parameters: [.text("keep")])

        // Transaction that should fail
        XCTAssertThrowsError(try db.transaction {
            try db.execute("INSERT INTO test (name) VALUES (?)", parameters: [.text("new")])
            // This should fail (NOT NULL constraint)
            try db.execute("INSERT INTO test (name) VALUES (?)", parameters: [.null])
        })

        // Original data should still be there
        let rows = try db.query("SELECT * FROM test")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"]?.stringValue, "keep")
    }

    func testBlobStorage() throws {
        let path = NSTemporaryDirectory() + "test_blob_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE blobs (id INTEGER PRIMARY KEY, data BLOB)")

        let testData = Data([0x01, 0x02, 0x03, 0xFF])
        try db.execute(
            "INSERT INTO blobs (data) VALUES (?)",
            parameters: [.blob(testData)]
        )

        let rows = try db.query("SELECT * FROM blobs")
        XCTAssertEqual(rows[0]["data"]?.blobValue, testData)
    }
}
