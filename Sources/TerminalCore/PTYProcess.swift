import Foundation
import SharedModels
#if canImport(Darwin)
import Darwin
#endif

// MARK: - PTY Process

public actor PTYProcess {
    public struct Configuration: Sendable {
        public var shell: String
        public var environment: [String: String]
        public var workingDirectory: String
        public var initialSize: TerminalSize

        public init(
            shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
            environment: [String: String] = [:],
            workingDirectory: String = NSHomeDirectory(),
            initialSize: TerminalSize = .default80x24
        ) {
            self.shell = shell
            self.environment = environment
            self.workingDirectory = workingDirectory
            self.initialSize = initialSize
        }
    }

    public enum State: Sendable {
        case idle
        case running(pid: pid_t)
        case exited(status: Int32)
    }

    public enum PTYError: Error, LocalizedError {
        case forkFailed(Int32)
        case alreadyRunning
        case notRunning

        public var errorDescription: String? {
            switch self {
            case .forkFailed(let errno): "forkpty failed: \(String(cString: strerror(errno)))"
            case .alreadyRunning: "PTY process is already running"
            case .notRunning: "PTY process is not running"
            }
        }
    }

    public private(set) var state: State = .idle
    public private(set) var masterFileDescriptor: Int32 = -1

    private let configuration: Configuration
    private var outputContinuation: AsyncStream<Data>.Continuation?
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Output Stream

    /// Lazily creates the async output stream. Must be called before start().
    public func makeOutputStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            self.outputContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                // Cleanup handled by terminate()
            }
        }
    }

    // MARK: - Start

    public func start() throws {
        guard case .idle = state else {
            throw PTYError.alreadyRunning
        }

        var masterFD: Int32 = -1
        var size = winsize()
        size.ws_col = UInt16(configuration.initialSize.columns)
        size.ws_row = UInt16(configuration.initialSize.rows)

        // Configure termios
        var term = termios()
        cfmakeraw(&term)
        term.c_cc.1 = 0x03  // VINTR = Ctrl-C
        term.c_cc.4 = 0x04  // VEOF = Ctrl-D
        term.c_cc.8 = 0x7F  // VERASE = DEL

        let pid = forkpty(&masterFD, nil, &term, &size)

        if pid < 0 {
            throw PTYError.forkFailed(errno)
        }

        if pid == 0 {
            // ── Child process ──────────────────────────────────────
            setupChildEnvironment()

            // Change to working directory
            let dir = (configuration.workingDirectory as NSString).expandingTildeInPath
            chdir(dir)

            // Execute the shell as a login shell
            let shellPath = configuration.shell
            let shellName = "-" + ((shellPath as NSString).lastPathComponent)

            // execvp expects [UnsafeMutablePointer<CChar>?]
            let args: [String] = [shellName]
            let cArgs = args.map { strdup($0) } + [nil]
            execvp(shellPath, cArgs)

            // If exec fails
            _exit(1)
        }

        // ── Parent process ─────────────────────────────────────
        self.masterFileDescriptor = masterFD
        self.state = .running(pid: pid)

        // Set non-blocking mode on master FD
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // Start reading from PTY
        startReading(fd: masterFD)

        // Monitor child process
        startProcessMonitor(pid: pid)
    }

    // MARK: - Write

    public func write(_ data: Data) throws {
        guard masterFileDescriptor >= 0 else {
            throw PTYError.notRunning
        }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < buffer.count {
                let written = Darwin.write(
                    masterFileDescriptor,
                    ptr.advanced(by: totalWritten),
                    buffer.count - totalWritten
                )
                if written < 0 {
                    if errno == EAGAIN || errno == EINTR { continue }
                    break
                }
                totalWritten += written
            }
        }
    }

    // MARK: - Resize

    public func resize(columns: Int, rows: Int) throws {
        guard masterFileDescriptor >= 0 else { return }
        var size = winsize()
        size.ws_col = UInt16(columns)
        size.ws_row = UInt16(rows)
        _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &size)

        // Also send SIGWINCH to the child process group
        if case .running(let pid) = state {
            kill(pid, SIGWINCH)
        }
    }

    // MARK: - Terminate

    public func terminate() {
        readSource?.cancel()
        readSource = nil

        processSource?.cancel()
        processSource = nil

        if case .running(let pid) = state {
            kill(pid, SIGHUP)
            kill(pid, SIGTERM)
        }

        if masterFileDescriptor >= 0 {
            Darwin.close(masterFileDescriptor)
            masterFileDescriptor = -1
        }

        outputContinuation?.finish()
        outputContinuation = nil
        state = .idle
    }

    // MARK: - Private: Reading

    private func startReading(fd: Int32) {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: DispatchQueue(label: "com.terminus.pty.read", qos: .userInteractive)
        )

        source.setEventHandler { [weak self] in
            let bufferSize = 8192
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            let bytesRead = read(fd, buffer, bufferSize)

            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                // We need to hop back to the actor to yield data
                // But continuation.yield is Sendable-safe
                Task { @MainActor [weak self] in
                    await self?.yieldOutput(data)
                }
            } else if bytesRead < 0 && errno != EAGAIN && errno != EINTR {
                // Read error — process likely exited
                Task { @MainActor [weak self] in
                    await self?.handleReadError()
                }
            }
        }

        source.setCancelHandler {
            // Source cleaned up
        }

        source.resume()
        self.readSource = source
    }

    private func yieldOutput(_ data: Data) {
        outputContinuation?.yield(data)
    }

    private func handleReadError() {
        // Process exited, cleanup will happen via process monitor
    }

    // MARK: - Private: Process Monitor

    private func startProcessMonitor(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: DispatchQueue(label: "com.terminus.pty.process")
        )

        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, 0)

            // WIFEXITED / WEXITSTATUS are C macros not importable in Swift
            let exitStatus: Int32
            let wstatus = status & 0x7F
            if wstatus == 0 {
                // Process exited normally
                exitStatus = (status >> 8) & 0xFF
            } else {
                exitStatus = -1
            }

            Task { @MainActor [weak self] in
                await self?.handleProcessExit(exitStatus)
            }
        }

        source.resume()
        self.processSource = source
    }

    private func handleProcessExit(_ exitStatus: Int32) {
        state = .exited(status: exitStatus)
        readSource?.cancel()
        readSource = nil
        processSource?.cancel()
        processSource = nil

        if masterFileDescriptor >= 0 {
            Darwin.close(masterFileDescriptor)
            masterFileDescriptor = -1
        }

        outputContinuation?.finish()
        outputContinuation = nil
    }

    // MARK: - Private: Child Environment Setup

    nonisolated private func setupChildEnvironment() {
        // Set TERM for proper terminal identification
        setenv("TERM", "xterm-256color", 1)
        setenv("COLORTERM", "truecolor", 1)
        setenv("TERM_PROGRAM", "Terminus", 1)
        setenv("TERM_PROGRAM_VERSION", "0.1.0", 1)

        // Mark that shell integration is available
        setenv("TERMINUS_INTEGRATION", "1", 1)

        // Set user-specified environment variables
        for (key, value) in configuration.environment {
            setenv(key, value, 1)
        }

        // Inherit current locale settings
        if let lang = ProcessInfo.processInfo.environment["LANG"] {
            setenv("LANG", lang, 1)
        } else {
            setenv("LANG", "en_US.UTF-8", 1)
        }

        // Ensure HOME is set
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            setenv("HOME", home, 1)
        }

        // Set PATH if not already in environment
        if configuration.environment["PATH"] == nil,
           let path = ProcessInfo.processInfo.environment["PATH"] {
            setenv("PATH", path, 1)
        }

        // Set up shell integration rc file injection
        let shellName = (configuration.shell as NSString).lastPathComponent
        switch shellName {
        case "zsh":
            // Inject via ZDOTDIR or ENV
            setenv("TERMINUS_SHELL", "zsh", 1)
        case "bash":
            setenv("TERMINUS_SHELL", "bash", 1)
        case "fish":
            setenv("TERMINUS_SHELL", "fish", 1)
        default:
            break
        }
    }
}
