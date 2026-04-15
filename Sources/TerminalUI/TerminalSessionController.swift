import Foundation
import SwiftUI
import SharedModels
import SharedUI
import TerminalEmulator
import TerminalCore

// MARK: - Terminal Session Controller

@MainActor
@Observable
public final class TerminalSessionController: TerminalInputHandler {
    public let session: TerminalSession
    public let buffer: TerminalBuffer
    public let ptyProcess: PTYProcess
    public let parser: EscapeSequenceParser
    public private(set) var isRunning: Bool = false
    public var renderGeneration: UInt64 = 0

    // Shell integration state
    public var currentDirectory: String
    public var currentCommand: String?
    public var lastExitCode: Int32?
    public var shellIntegrationActive: Bool = false

    // Prediction state
    public var predictions: [Prediction] = []
    public var showPredictions: Bool = false
    public var selectedPredictionIndex: Int = 0
    public var inputPrefix: String = ""

    // Callbacks
    public var onCommandCompleted: ((String, Int32, String) -> Void)?

    private var outputTask: Task<Void, Never>?

    public init(
        session: TerminalSession,
        size: TerminalSize = .default80x24
    ) {
        self.session = session
        self.buffer = TerminalBuffer(size: size)
        self.parser = EscapeSequenceParser(buffer: buffer)
        self.currentDirectory = session.initialDirectory

        let config = PTYProcess.Configuration(
            shell: session.shell,
            workingDirectory: session.initialDirectory,
            initialSize: size
        )
        self.ptyProcess = PTYProcess(configuration: config)

        setupShellIntegration()
    }

    private func setupShellIntegration() {
        parser.shellIntegration.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleShellEvent(event)
            }
        }
    }

    private func handleShellEvent(_ event: ShellIntegrationEvent) {
        shellIntegrationActive = true
        switch event {
        case .promptStart:
            currentCommand = nil
            inputPrefix = ""
            predictions = []
            showPredictions = false
        case .commandStart(let command):
            currentCommand = command
        case .commandOutputStart:
            showPredictions = false
        case .commandFinished(let exitCode):
            lastExitCode = exitCode
            if let command = currentCommand, !command.isEmpty {
                onCommandCompleted?(command, exitCode, currentDirectory)
            }
            currentCommand = nil
        case .directoryChanged(let path):
            currentDirectory = path
        }
    }

    // MARK: - Start

    public func start() async {
        let outputStream = await ptyProcess.makeOutputStream()

        do {
            try await ptyProcess.start()
            isRunning = true
        } catch {
            print("Failed to start PTY: \(error)")
            return
        }

        outputTask = Task { [weak self] in
            for await data in outputStream {
                guard let self else { break }
                self.parser.feed(data)
                self.renderGeneration &+= 1
            }
            guard let self else { return }
            self.isRunning = false
        }
    }

    // MARK: - TerminalInputHandler

    public func sendInput(_ data: Data) async {
        try? await ptyProcess.write(data)
    }

    public func sendString(_ string: String) async {
        if let data = string.data(using: .utf8) {
            await sendInput(data)
        }
    }

    // MARK: - Resize

    public func resize(_ size: TerminalSize) async {
        buffer.resize(size)
        try? await ptyProcess.resize(columns: size.columns, rows: size.rows)
    }

    // MARK: - Stop

    public func stop() async {
        outputTask?.cancel()
        outputTask = nil
        await ptyProcess.terminate()
        isRunning = false
    }

    // MARK: - Window Title

    public var windowTitle: String? {
        parser.windowTitle
    }
}

// MARK: - Terminal Panel View

public struct TerminalPanelView: View {
    @State var controller: TerminalSessionController
    let theme: TerminusTheme
    let isFocused: Bool

    public init(
        controller: TerminalSessionController,
        theme: TerminusTheme = .defaultLight,
        isFocused: Bool = true
    ) {
        self.controller = controller
        self.theme = theme
        self.isFocused = isFocused
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main terminal view — NSView handles BOTH rendering and input
            TerminalNSViewRepresentable(
                buffer: controller.buffer,
                theme: theme,
                isFocused: isFocused,
                inputHandler: controller,
                renderGeneration: controller.renderGeneration
            )

            // Status bar overlay
            TerminalStatusBar(controller: controller, theme: theme)
        }
        .task {
            if !controller.isRunning {
                await controller.start()
            }
        }
    }
}

// MARK: - Terminal Status Bar

struct TerminalStatusBar: View {
    let controller: TerminalSessionController
    let theme: TerminusTheme

    var body: some View {
        HStack(spacing: TerminusDesign.spacingSM) {
            if controller.shellIntegrationActive {
                Circle()
                    .fill(TerminusAccent.success)
                    .frame(width: 6, height: 6)
            }

            Text(shortenPath(controller.currentDirectory))
                .font(.terminusUI(size: 11))
                .foregroundStyle(theme.chromeTextTertiary)
                .lineLimit(1)

            Spacer()

            if let exitCode = controller.lastExitCode, exitCode != 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                    Text("\(exitCode)")
                        .font(.terminusUI(size: 10))
                }
                .foregroundStyle(TerminusAccent.error)
            }

            Text("\(controller.buffer.size.columns)x\(controller.buffer.size.rows)")
                .font(.terminusUI(size: 10))
                .foregroundStyle(theme.chromeTextTertiary)
        }
        .padding(.horizontal, TerminusDesign.spacingSM)
        .padding(.vertical, 3)
        .background(theme.chromeBackground.opacity(0.9))
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Cell Metrics

public struct CellMetrics: Sendable {
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat

    public init(fontSize: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        cellWidth = font.advancement(forGlyph: font.glyph(withName: "M")).width
        cellHeight = font.ascender - font.descender + font.leading
    }
}
