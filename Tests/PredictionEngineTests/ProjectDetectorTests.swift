import XCTest
@testable import PredictionEngine
import SharedModels

final class ProjectDetectorTests: XCTestCase {

    func testDetectSwiftProject() throws {
        let dir = NSTemporaryDirectory() + "test_swift_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        FileManager.default.createFile(
            atPath: (dir as NSString).appendingPathComponent("Package.swift"),
            contents: nil
        )

        XCTAssertEqual(ProjectDetector.detect(directory: dir), .swift)
    }

    func testDetectNodeProject() throws {
        let dir = NSTemporaryDirectory() + "test_node_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        FileManager.default.createFile(
            atPath: (dir as NSString).appendingPathComponent("package.json"),
            contents: nil
        )

        XCTAssertEqual(ProjectDetector.detect(directory: dir), .node)
    }

    func testDetectRustProject() throws {
        let dir = NSTemporaryDirectory() + "test_rust_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        FileManager.default.createFile(
            atPath: (dir as NSString).appendingPathComponent("Cargo.toml"),
            contents: nil
        )

        XCTAssertEqual(ProjectDetector.detect(directory: dir), .rust)
    }

    func testDetectPythonProject() throws {
        let dir = NSTemporaryDirectory() + "test_python_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        FileManager.default.createFile(
            atPath: (dir as NSString).appendingPathComponent("pyproject.toml"),
            contents: nil
        )

        XCTAssertEqual(ProjectDetector.detect(directory: dir), .python)
    }

    func testDetectUnknownProject() throws {
        let dir = NSTemporaryDirectory() + "test_empty_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        XCTAssertEqual(ProjectDetector.detect(directory: dir), .unknown)
    }

    func testDetectInSubdirectory() throws {
        let parentDir = NSTemporaryDirectory() + "test_parent_\(UUID().uuidString)"
        let childDir = (parentDir as NSString).appendingPathComponent("src/components")
        try FileManager.default.createDirectory(atPath: childDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: parentDir) }

        FileManager.default.createFile(
            atPath: (parentDir as NSString).appendingPathComponent("package.json"),
            contents: nil
        )

        // Should find package.json in parent
        XCTAssertEqual(ProjectDetector.detect(directory: childDir), .node)
    }
}
