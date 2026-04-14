import Foundation
import SharedModels

// MARK: - Project Type Detector

public enum ProjectDetector {
    private static let markers: [(String, ProjectType)] = [
        ("Package.swift", .swift),
        ("Cargo.toml", .rust),
        ("go.mod", .go),
        ("package.json", .node),
        ("pyproject.toml", .python),
        ("setup.py", .python),
        ("requirements.txt", .python),
        ("Gemfile", .ruby),
        ("pom.xml", .java),
        ("build.gradle", .java),
        ("build.gradle.kts", .java),
    ]

    public static func detect(directory: String) -> ProjectType {
        let expandedDir = (directory as NSString).expandingTildeInPath
        let fm = FileManager.default

        // Check current directory first
        for (marker, projectType) in markers {
            let path = (expandedDir as NSString).appendingPathComponent(marker)
            if fm.fileExists(atPath: path) {
                return projectType
            }
        }

        // Walk up parent directories (max 3 levels)
        var current = expandedDir
        for _ in 0..<3 {
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current else { break }
            current = parent

            for (marker, projectType) in markers {
                let path = (current as NSString).appendingPathComponent(marker)
                if fm.fileExists(atPath: path) {
                    return projectType
                }
            }
        }

        return .unknown
    }

    /// Detect git branch in a directory
    public static func detectGitBranch(directory: String) -> String? {
        let expandedDir = (directory as NSString).expandingTildeInPath
        let headPath = findGitDir(from: expandedDir)

        guard let headPath,
              let headContent = try? String(contentsOfFile: headPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        // Parse HEAD file: "ref: refs/heads/main"
        if headContent.hasPrefix("ref: refs/heads/") {
            return String(headContent.dropFirst("ref: refs/heads/".count))
        }

        // Detached HEAD — return short hash
        if headContent.count >= 7 {
            return String(headContent.prefix(7))
        }

        return nil
    }

    private static func findGitDir(from directory: String) -> String? {
        var current = directory
        for _ in 0..<10 {
            let gitHead = (current as NSString).appendingPathComponent(".git/HEAD")
            if FileManager.default.fileExists(atPath: gitHead) {
                return gitHead
            }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current else { break }
            current = parent
        }
        return nil
    }
}
