import Foundation
import SharedModels

// MARK: - Shell Integration Events

public enum ShellIntegrationEvent: Sendable {
    /// Prompt rendering started (OSC 133;A)
    case promptStart
    /// User pressed Enter, command input begins (OSC 133;B)
    case commandStart(command: String?)
    /// Command output is starting (OSC 133;C)
    case commandOutputStart
    /// Command finished with exit code (OSC 133;D;exitCode)
    case commandFinished(exitCode: Int32)
    /// Current working directory changed (OSC 7)
    case directoryChanged(path: String)
}

// MARK: - Shell Integration State

public final class ShellIntegrationState: @unchecked Sendable {
    /// The current command being typed
    public private(set) var currentCommand: String?
    /// The current working directory reported by shell
    public private(set) var currentDirectory: String?
    /// Last exit code
    public private(set) var lastExitCode: Int32?
    /// Whether we're currently inside a command output region
    public private(set) var isInCommandOutput: Bool = false
    /// Prompt location (row in buffer where prompt started)
    public private(set) var promptRow: Int?

    /// Callback for events
    public var onEvent: ((ShellIntegrationEvent) -> Void)?

    public init() {}

    func handleEvent(_ event: ShellIntegrationEvent) {
        switch event {
        case .promptStart:
            isInCommandOutput = false
            currentCommand = nil
        case .commandStart(let cmd):
            currentCommand = cmd
        case .commandOutputStart:
            isInCommandOutput = true
        case .commandFinished(let code):
            lastExitCode = code
            isInCommandOutput = false
        case .directoryChanged(let path):
            currentDirectory = path
        }
        onEvent?(event)
    }

    func setPromptRow(_ row: Int) {
        promptRow = row
    }
}

// MARK: - Shell Integration Setup

public enum ShellIntegrationSetup {
    /// Returns shell configuration snippets that enable OSC 133 integration
    public static func shellConfig(for shell: String) -> String? {
        let shellName = (shell as NSString).lastPathComponent

        switch shellName {
        case "zsh":
            return zshConfig
        case "bash":
            return bashConfig
        case "fish":
            return fishConfig
        default:
            return nil
        }
    }

    private static let zshConfig = """
    # Terminus shell integration
    __terminus_precmd() {
        local exit_code=$?
        # Report command finished with exit code
        printf '\\e]133;D;%d\\a' "$exit_code"
        # Report current directory
        printf '\\e]7;file://%s%s\\a' "$HOST" "$PWD"
        # Report prompt start
        printf '\\e]133;A\\a'
    }

    __terminus_preexec() {
        # Report command start
        printf '\\e]133;C\\a'
    }

    [[ -z "${precmd_functions[(r)__terminus_precmd]}" ]] && precmd_functions+=(__terminus_precmd)
    [[ -z "${preexec_functions[(r)__terminus_preexec]}" ]] && preexec_functions+=(__terminus_preexec)

    # Initial prompt start
    printf '\\e]133;A\\a'
    """

    private static let bashConfig = """
    # Terminus shell integration
    __terminus_prompt_command() {
        local exit_code=$?
        printf '\\e]133;D;%d\\a' "$exit_code"
        printf '\\e]7;file://%s%s\\a' "$HOSTNAME" "$PWD"
        printf '\\e]133;A\\a'
    }

    __terminus_preexec() {
        printf '\\e]133;C\\a'
    }

    trap '__terminus_preexec' DEBUG
    PROMPT_COMMAND="__terminus_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

    printf '\\e]133;A\\a'
    """

    private static let fishConfig = """
    # Terminus shell integration
    function __terminus_prompt --on-event fish_prompt
        printf '\\e]133;D;%d\\a' $status
        printf '\\e]7;file://%s%s\\a' (hostname) $PWD
        printf '\\e]133;A\\a'
    end

    function __terminus_preexec --on-event fish_preexec
        printf '\\e]133;C\\a'
    end

    printf '\\e]133;A\\a'
    """

    /// Environment variables to inject for shell integration
    public static func environmentVariables(for shell: String) -> [String: String] {
        guard let config = shellConfig(for: shell) else { return [:] }

        let shellName = (shell as NSString).lastPathComponent
        let envKey: String

        switch shellName {
        case "zsh":
            // Use ZDOTDIR trick or inject via ENV
            envKey = "TERMINUS_SHELL_INTEGRATION"
        case "bash":
            envKey = "TERMINUS_SHELL_INTEGRATION"
        case "fish":
            envKey = "TERMINUS_SHELL_INTEGRATION"
        default:
            return [:]
        }

        return [
            envKey: config,
            "TERMINUS_INTEGRATION": "1",
        ]
    }
}
