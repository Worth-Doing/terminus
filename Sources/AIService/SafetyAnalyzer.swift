import Foundation
import SharedModels

// MARK: - Safety Analysis Result

public struct SafetyAnalysisResult: Sendable {
    public let level: CommandSafetyLevel
    public let warnings: [SafetyWarning]

    public init(level: CommandSafetyLevel, warnings: [SafetyWarning]) {
        self.level = level
        self.warnings = warnings
    }
}

// MARK: - Safety Analyzer

public enum SafetyAnalyzer {

    // MARK: - Analyze Command

    public static func analyze(_ command: String) -> SafetyAnalysisResult {
        var warnings: [SafetyWarning] = []
        var maxLevel: CommandSafetyLevel = .safe

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let tokens = tokenize(trimmed)

        // === CRITICAL: System-destroying commands ===
        for pattern in criticalPatterns {
            if pattern.matches(lowered) {
                warnings.append(SafetyWarning(
                    level: .critical,
                    message: pattern.message,
                    detail: pattern.detail
                ))
                maxLevel = .critical
            }
        }

        // === DANGEROUS: Destructive operations ===
        for pattern in dangerousPatterns {
            if pattern.matches(lowered) {
                warnings.append(SafetyWarning(
                    level: .dangerous,
                    message: pattern.message,
                    detail: pattern.detail
                ))
                if maxLevel < .dangerous {
                    maxLevel = .dangerous
                }
            }
        }

        // === MODERATE: File modifications ===
        for pattern in moderatePatterns {
            if pattern.matches(lowered) {
                warnings.append(SafetyWarning(
                    level: .moderate,
                    message: pattern.message,
                    detail: pattern.detail
                ))
                if maxLevel < .moderate {
                    maxLevel = .moderate
                }
            }
        }

        // === Privilege escalation ===
        if tokens.first == "sudo" {
            let innerLevel: CommandSafetyLevel = maxLevel >= .dangerous ? .critical : .dangerous
            warnings.append(SafetyWarning(
                level: innerLevel,
                message: "Requires administrator privileges (sudo)",
                detail: "This command will run with elevated permissions. Ensure you trust the operation."
            ))
            if maxLevel < innerLevel {
                maxLevel = innerLevel
            }
        }

        // === Network operations ===
        if containsNetworkOperation(lowered, tokens: tokens) {
            warnings.append(SafetyWarning(
                level: .moderate,
                message: "Performs network operation",
                detail: "This command accesses the network. Verify the target is trusted."
            ))
            if maxLevel < .moderate {
                maxLevel = .moderate
            }
        }

        // === Piped to shell (curl | bash pattern) ===
        if lowered.contains("| bash") || lowered.contains("| sh") || lowered.contains("| zsh") {
            warnings.append(SafetyWarning(
                level: .critical,
                message: "Pipes remote content to shell",
                detail: "Downloading and executing scripts from the internet is extremely risky. The content could be malicious."
            ))
            maxLevel = .critical
        }

        // === Environment modification ===
        if lowered.hasPrefix("export ") || lowered.contains("source ") || lowered.contains(". /") {
            warnings.append(SafetyWarning(
                level: .moderate,
                message: "Modifies shell environment",
                detail: "Changes environment variables or sources a script into the current shell."
            ))
            if maxLevel < .moderate {
                maxLevel = .moderate
            }
        }

        return SafetyAnalysisResult(level: maxLevel, warnings: warnings)
    }

    // MARK: - Tokenize

    private static func tokenize(_ command: String) -> [String] {
        // Simple tokenization splitting on whitespace, respecting quotes loosely
        command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - Network Check

    private static func containsNetworkOperation(_ lowered: String, tokens: [String]) -> Bool {
        let networkCmds = ["curl", "wget", "ssh", "scp", "rsync", "nc", "ncat", "telnet", "ftp", "sftp"]
        return tokens.contains { networkCmds.contains($0.lowercased()) }
    }

    // MARK: - Pattern Definitions

    private struct DangerPattern: Sendable {
        let check: @Sendable (String) -> Bool
        let message: String
        let detail: String?

        func matches(_ input: String) -> Bool {
            check(input)
        }

        init(_ message: String, detail: String? = nil, check: @escaping @Sendable (String) -> Bool) {
            self.message = message
            self.detail = detail
            self.check = check
        }
    }

    private static let criticalPatterns: [DangerPattern] = [
        DangerPattern(
            "Recursive force delete from root or home",
            detail: "rm -rf / or rm -rf ~ will permanently delete everything. This is almost always a mistake."
        ) { $0.contains("rm -rf /") && !$0.contains("rm -rf /tmp") && !$0.contains("rm -rf /var") },

        DangerPattern(
            "Writes directly to disk device",
            detail: "Writing raw data to a disk device can destroy all data on that disk."
        ) { $0.contains("/dev/disk") || $0.contains("/dev/sda") || $0.contains("/dev/nvme") },

        DangerPattern(
            "Formats a disk or volume",
            detail: "Formatting will erase all data on the target volume."
        ) { $0.contains("diskutil erase") || $0.contains("mkfs") || $0.contains("newfs") },

        DangerPattern(
            "Modifies system boot or firmware",
            detail: "Changes to system firmware or boot configuration can make the system unbootable."
        ) { $0.contains("nvram") || $0.contains("csrutil") || $0.contains("bless ") },
    ]

    private static let dangerousPatterns: [DangerPattern] = [
        DangerPattern(
            "Recursive delete operation",
            detail: "rm -r recursively deletes directories and their contents. Deleted files cannot be recovered."
        ) { $0.contains("rm -r") || $0.contains("rm -f") || ($0.contains("rm ") && $0.contains("*")) },

        DangerPattern(
            "Kills processes",
            detail: "Terminating processes may cause data loss in running applications."
        ) { $0.contains("kill ") || $0.contains("killall ") || $0.contains("pkill ") },

        DangerPattern(
            "Changes file permissions recursively",
            detail: "Recursive permission changes can break system functionality or expose files."
        ) { ($0.contains("chmod -r") || $0.contains("chown -r")) },

        DangerPattern(
            "Modifies system files",
            detail: "Changes to /etc, /usr, or /System can affect system stability."
        ) { $0.contains("/etc/") || $0.contains("/usr/") || $0.contains("/system/") },

        DangerPattern(
            "Overwrites files without backup",
            detail: "Output redirection with > will overwrite existing files."
        ) { $0.contains(" > ") && !$0.contains(" >> ") },

        DangerPattern(
            "Force push to git remote",
            detail: "Force push overwrites remote history. Other collaborators may lose work."
        ) { $0.contains("git push") && ($0.contains("-f") || $0.contains("--force")) },

        DangerPattern(
            "Git hard reset",
            detail: "Hard reset discards all uncommitted changes permanently."
        ) { $0.contains("git reset --hard") || $0.contains("git checkout -- .") },

        DangerPattern(
            "Drops or destroys database",
            detail: "Database drop/delete operations are irreversible."
        ) { $0.contains("drop database") || $0.contains("drop table") || $0.contains("truncate ") },

        DangerPattern(
            "Disables security features",
            detail: "Disabling security features like SIP or Gatekeeper exposes your system to risks."
        ) { $0.contains("--no-quarantine") || $0.contains("spctl --master-disable") },

        DangerPattern(
            "Modifies launchd or cron",
            detail: "Changes to scheduled tasks can have persistent effects on your system."
        ) { $0.contains("launchctl") || $0.contains("crontab") },
    ]

    private static let moderatePatterns: [DangerPattern] = [
        DangerPattern(
            "Creates or modifies files",
            detail: "This command will create or modify files on disk."
        ) { $0.contains("touch ") || $0.contains("mkdir ") || $0.contains("tee ") },

        DangerPattern(
            "Moves or renames files",
            detail: "Moving files changes their location. The original path will no longer work."
        ) { $0.contains("mv ") },

        DangerPattern(
            "Copies files",
            detail: "Copying files will use additional disk space."
        ) { $0.contains("cp ") },

        DangerPattern(
            "Installs packages",
            detail: "Installing packages modifies your system and may require disk space."
        ) { $0.contains("brew install") || $0.contains("pip install") || $0.contains("npm install") || $0.contains("gem install") || $0.contains("cargo install") },

        DangerPattern(
            "Modifies git history",
            detail: "This operation modifies the git repository state."
        ) { $0.contains("git commit") || $0.contains("git merge") || $0.contains("git rebase") || $0.contains("git stash") },

        DangerPattern(
            "Writes to file",
            detail: "Output will be appended to or written to a file."
        ) { $0.contains(" >> ") },
    ]
}
