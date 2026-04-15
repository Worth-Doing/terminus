import SwiftUI
import SharedModels
import SharedUI
import DataStore
import SecureStorage
import TerminalCore
import TerminalEmulator
import TerminalUI
import WorkspaceEngine
import HistoryEngine
import PredictionEngine
import SavedCommands
import AIService
import EmbeddingPipeline
import OnboardingUI
import SettingsUI
import SystemMonitor

// MARK: - Service Container

/// Holds all backend services and engines. Extracted from AppState to separate
/// data/business logic from UI state. Initialized once at app launch.
@MainActor
struct ServiceContainer {
    let secureStorage = SecureStorage()
    let dataAccess: DataAccess?
    let historyEngine: HistoryEngine?
    let predictionEngine: PredictionEngine?
    let savedCommandsManager: SavedCommandsManager?
    let aiService: AIServiceClient?
    let embeddingPipeline: EmbeddingPipeline?
    let nlPipeline: NLCommandPipeline?
    let commandIntelligence: CommandIntelligence?

    init() {
        do {
            let da = try DataAccess.createDefault()
            self.dataAccess = da
            let he = HistoryEngine(dataAccess: da)
            self.historyEngine = he
            self.predictionEngine = PredictionEngine(history: he)
            self.savedCommandsManager = SavedCommandsManager(dataAccess: da)
            let ai = AIServiceClient(secureStorage: secureStorage)
            self.aiService = ai
            self.embeddingPipeline = EmbeddingPipeline(aiService: ai, dataAccess: da)
            self.nlPipeline = NLCommandPipeline(aiService: ai)
            self.commandIntelligence = CommandIntelligence(aiService: ai)
        } catch {
            print("Failed to initialize database: \(error)")
            self.dataAccess = nil
            self.historyEngine = nil
            self.predictionEngine = nil
            self.savedCommandsManager = nil
            self.aiService = nil
            self.embeddingPipeline = nil
            self.nlPipeline = nil
            self.commandIntelligence = nil
        }
    }
}

// MARK: - App State

@MainActor
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool
    var theme: TerminusTheme
    var settings: UserSettings
    var controllers: [SessionID: TerminalSessionController] = [:]

    let windowState = WindowState()
    var workspaces: [String: WorkspaceState] = [:]

    // Services (extracted into container)
    let services: ServiceContainer

    // Convenience accessors
    var secureStorage: SecureStorage { services.secureStorage }
    var dataAccess: DataAccess? { services.dataAccess }
    var historyEngine: HistoryEngine? { services.historyEngine }
    var predictionEngine: PredictionEngine? { services.predictionEngine }
    var savedCommandsManager: SavedCommandsManager? { services.savedCommandsManager }
    var aiService: AIServiceClient? { services.aiService }
    var embeddingPipeline: EmbeddingPipeline? { services.embeddingPipeline }
    var nlPipeline: NLCommandPipeline? { services.nlPipeline }

    // UI state
    var showSidebar: Bool = false
    var showCommandPalette: Bool = false
    var showSemanticSearch: Bool = false
    var showSaveCommandSheet: Bool = false
    var showMetrics: Bool = false
    var savedCommands: [SavedCommand] = []
    var semanticSearchResults: [(String, Float)] = []
    var semanticSearchQuery: String = ""

    // AI state
    var showNLBar: Bool = false
    var nlInput: String = ""
    var isAIProcessing: Bool = false
    var currentAIResponse: NLCommandResponse?
    var aiResponses: [NLCommandResponse] = []
    var blockManagers: [SessionID: BlockManager] = [:]

    // New feature state
    var showHistoryPanel: Bool = false
    var showFileExplorer: Bool = false
    var showWorkflowEditor: Bool = false
    var historyEntries: [CommandEntry] = []
    var favoriteCommands: Set<String> = []
    var workflows: [WorkflowSequence] = []
    let workflowRunner = WorkflowRunner()
    var fileExplorerState = FileExplorerState()
    var commandExplanation: CommandExplanation?
    var isExplaining: Bool = false
    var errorRecoverySuggestion: NLCommandResponse?
    var lastFailedCommand: String?
    var lastFailedOutput: String?

    // AI availability — enabled automatically when API key exists
    var isAIAvailable: Bool {
        (try? secureStorage.exists(key: SecureStorage.openRouterAPIKey)) ?? false
    }

    var currentChatModel: ModelConfiguration {
        let modelID = UserDefaults.standard.string(forKey: "terminus.ai.chatModel") ?? DefaultModels.chat.modelID
        let temp = UserDefaults.standard.object(forKey: "terminus.ai.temperature") as? Double ?? 0.7
        let tokens = UserDefaults.standard.object(forKey: "terminus.ai.maxTokens") as? Int ?? 4096
        return ModelConfiguration(
            id: "user-chat",
            provider: "openrouter",
            modelID: modelID,
            purpose: .chat,
            maxTokens: tokens,
            temperature: temp
        )
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.services = ServiceContainer()

        // Load persisted settings
        let savedThemeID = UserDefaults.standard.string(forKey: "terminus.themeID") ?? "defaultLight"
        self.theme = TerminusTheme.theme(withID: savedThemeID)
        self.settings = UserSettings()
        self.settings.theme = savedThemeID

        if let savedFontSize = UserDefaults.standard.object(forKey: "terminus.fontSize") as? Double {
            self.settings.fontSize = savedFontSize
            self.theme.fontSize = CGFloat(savedFontSize)
        }
        if let savedFontFamily = UserDefaults.standard.string(forKey: "terminus.fontFamily") {
            self.settings.fontFamily = savedFontFamily
            self.theme.fontFamily = savedFontFamily
        }
        if UserDefaults.standard.object(forKey: "terminus.enableAI") != nil {
            self.settings.enableAI = UserDefaults.standard.bool(forKey: "terminus.enableAI")
        }

        // Load saved commands
        self.savedCommands = (try? savedCommandsManager?.list()) ?? []

        // Create first workspace
        let firstTab = windowState.tabs[0]
        workspaces[firstTab.workspaceID] = WorkspaceState()
    }

    var activeWorkspace: WorkspaceState {
        let tab = windowState.activeTab
        if let ws = workspaces[tab.workspaceID] {
            return ws
        }
        let ws = WorkspaceState()
        workspaces[tab.workspaceID] = ws
        return ws
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Theme Management

    func applyTheme(_ themeID: String) {
        theme = TerminusTheme.theme(withID: themeID)
        // Preserve user font settings
        if let fontFamily = settings.fontFamily {
            theme.fontFamily = fontFamily
        }
        theme.fontSize = CGFloat(settings.fontSize)
        settings.theme = themeID
        UserDefaults.standard.set(themeID, forKey: "terminus.themeID")
    }

    func applyFontSize(_ size: Double) {
        settings.fontSize = size
        theme.fontSize = CGFloat(size)
        UserDefaults.standard.set(size, forKey: "terminus.fontSize")
    }

    func applyFontFamily(_ family: String) {
        settings.fontFamily = family
        theme.fontFamily = family
        UserDefaults.standard.set(family, forKey: "terminus.fontFamily")
    }

    // MARK: - Session Management

    func controllerForSession(_ sessionID: SessionID) -> TerminalSessionController {
        if let existing = controllers[sessionID] {
            return existing
        }

        let session = TerminalSession(
            id: sessionID,
            initialDirectory: NSHomeDirectory(),
            shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        )

        let controller = TerminalSessionController(session: session)

        // Ensure block manager exists for this session
        if blockManagers[sessionID] == nil {
            blockManagers[sessionID] = BlockManager()
        }

        // Wire command completion to history engine + n-gram recording + block manager
        controller.onCommandCompleted = { [weak self] command, exitCode, directory in
            guard let self, let historyEngine = self.historyEngine else { return }

            let projectType = ProjectDetector.detect(directory: directory)
            let gitBranch = ProjectDetector.detectGitBranch(directory: directory)

            let entry = CommandEntry(
                command: command,
                workingDirectory: directory,
                shell: session.shell,
                exitCode: exitCode,
                startedAt: Date(),
                finishedAt: Date(),
                sessionID: session.id,
                hostname: Host.current().localizedName,
                projectType: projectType,
                gitBranch: gitBranch
            )

            try? historyEngine.record(entry)

            // Record bigram for n-gram predictions
            if let prev = controller.previousCommand, !prev.isEmpty {
                try? historyEngine.recordNgram(
                    context: prev,
                    prediction: command,
                    gramSize: 2,
                    directory: directory
                )
            }

            // Update NL pipeline context
            Task {
                await self.nlPipeline?.updateContext(
                    directory: directory,
                    recentCommand: command,
                    output: nil
                )
                await self.nlPipeline?.updateProjectType(projectType)
            }
        }

        // Wire window title changes to tab title
        controller.onWindowTitleChanged = { [weak self] title in
            guard let self else { return }
            for (index, tab) in self.windowState.tabs.enumerated() {
                if let ws = self.workspaces[tab.workspaceID],
                   ws.allLeaves(in: ws.root).contains(where: { $0.sessionID == sessionID }) {
                    self.windowState.tabs[index].title = title
                    break
                }
            }
        }

        controllers[sessionID] = controller
        return controller
    }

    func addTab() {
        let tab = windowState.addTab()
        workspaces[tab.workspaceID] = WorkspaceState()
    }

    func closeCurrentTab() {
        let index = windowState.activeTabIndex
        let tab = windowState.tabs[index]

        if let ws = workspaces[tab.workspaceID] {
            for sessionID in ws.allSessionIDs {
                if let controller = controllers[sessionID] {
                    Task { await controller.stop() }
                    controllers.removeValue(forKey: sessionID)
                }
                blockManagers.removeValue(forKey: sessionID)
            }
            workspaces.removeValue(forKey: tab.workspaceID)
        }

        windowState.closeTab(at: index)
    }

    func splitFocused(direction: SplitDirection) {
        let ws = activeWorkspace
        let sessionID = ws.splitPanel(ws.focusedPanelID, direction: direction)
        _ = controllerForSession(sessionID)
    }

    func closeFocusedPanel() {
        let ws = activeWorkspace
        if ws.panelCount > 1 {
            if let leaf = findLeaf(ws.focusedPanelID, in: ws.root) {
                let sessionID = leaf.sessionID
                ws.closePanel(ws.focusedPanelID)

                let allSessions = ws.allSessionIDs
                if !allSessions.contains(sessionID) {
                    if let controller = controllers[sessionID] {
                        Task { await controller.stop() }
                        controllers.removeValue(forKey: sessionID)
                    }
                    blockManagers.removeValue(forKey: sessionID)
                }
            }
        } else if windowState.tabs.count > 1 {
            closeCurrentTab()
        }
    }

    private func findLeaf(_ id: PanelID, in node: PanelNode) -> PanelLeaf? {
        switch node {
        case .leaf(let leaf): leaf.id == id ? leaf : nil
        case .split(let split):
            findLeaf(id, in: split.first) ?? findLeaf(id, in: split.second)
        }
    }

    // MARK: - Saved Commands

    func reloadSavedCommands() {
        savedCommands = (try? savedCommandsManager?.list()) ?? []
    }

    func saveCommand(_ command: SavedCommand) {
        try? savedCommandsManager?.save(command)
        reloadSavedCommands()
    }

    func deleteSavedCommand(_ command: SavedCommand) {
        try? savedCommandsManager?.delete(id: command.id)
        reloadSavedCommands()
    }

    func insertSavedCommand(_ command: SavedCommand) {
        let ws = activeWorkspace
        let leaves = ws.allLeaves(in: ws.root)
        guard let focused = leaves.first(where: { $0.id == ws.focusedPanelID }),
              let controller = controllers[focused.sessionID] else { return }

        let resolved = savedCommandsManager?.resolve(command, parameters: [:]) ?? command.commandTemplate
        Task {
            await controller.sendString(resolved)
        }
    }

    // MARK: - AI / NL Command System

    func processNLInput(_ input: String, intent: InputIntent) {
        let ws = activeWorkspace
        let leaves = ws.allLeaves(in: ws.root)
        guard let focused = leaves.first(where: { $0.id == ws.focusedPanelID }),
              let controller = controllers[focused.sessionID] else { return }

        if intent == .rawCommand {
            // Send directly to terminal
            Task {
                await controller.sendString(input + "\n")
            }
            return
        }

        // Natural language processing
        guard let pipeline = nlPipeline else { return }

        isAIProcessing = true
        currentAIResponse = nil

        let directory = controller.currentDirectory
        let previousCmds = controller.previousCommand.map { [$0] } ?? []
        let projectType = ProjectDetector.detect(directory: directory)

        Task {
            do {
                let request = NLCommandRequest(
                    query: input,
                    currentDirectory: directory,
                    shell: controller.session.shell,
                    previousCommands: previousCmds,
                    projectType: projectType
                )

                let response = try await pipeline.generateCommand(
                    from: request,
                    model: currentChatModel
                )

                await MainActor.run {
                    self.currentAIResponse = response
                    self.aiResponses.append(response)
                    self.isAIProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.isAIProcessing = false
                }
            }
        }
    }

    func executeAICommand(_ command: String) {
        let ws = activeWorkspace
        let leaves = ws.allLeaves(in: ws.root)
        guard let focused = leaves.first(where: { $0.id == ws.focusedPanelID }),
              let controller = controllers[focused.sessionID] else { return }

        currentAIResponse = nil

        Task {
            await controller.sendString(command + "\n")
        }
    }

    func dismissAIResponse() {
        currentAIResponse = nil
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Predictions

    func fetchPredictions(prefix: String, sessionID: SessionID) -> [Prediction] {
        guard let controller = controllers[sessionID],
              let engine = predictionEngine else { return [] }

        let directory = controller.currentDirectory
        let projectType = ProjectDetector.detect(directory: directory)

        return (try? engine.predict(
            prefix: prefix,
            currentDirectory: directory,
            previousCommand: controller.previousCommand,
            projectType: projectType,
            limit: 8
        )) ?? []
    }

    // MARK: - History

    func loadHistory() {
        historyEntries = (try? historyEngine?.recentCommands(limit: 200)) ?? []
    }

    func toggleFavorite(_ command: String) {
        if favoriteCommands.contains(command) {
            favoriteCommands.remove(command)
        } else {
            favoriteCommands.insert(command)
        }
        // Persist favorites
        UserDefaults.standard.set(Array(favoriteCommands), forKey: "terminus.favorites")
    }

    func loadFavorites() {
        if let saved = UserDefaults.standard.array(forKey: "terminus.favorites") as? [String] {
            favoriteCommands = Set(saved)
        }
    }

    // MARK: - Command Intelligence

    func explainCurrentCommand(_ command: String) {
        guard let intelligence = services.commandIntelligence else { return }
        isExplaining = true

        Task {
            do {
                let explanation = try await intelligence.explainCommand(command, model: currentChatModel)
                await MainActor.run {
                    self.commandExplanation = explanation
                    self.isExplaining = false
                }
            } catch {
                await MainActor.run {
                    self.isExplaining = false
                }
            }
        }
    }

    func dismissExplanation() {
        commandExplanation = nil
    }

    // MARK: - Error Recovery

    func suggestErrorFix(command: String, exitCode: Int32, output: String) {
        guard let pipeline = nlPipeline else { return }
        lastFailedCommand = command
        lastFailedOutput = output

        Task {
            do {
                let response = try await pipeline.suggestFix(
                    command: command,
                    exitCode: exitCode,
                    output: output,
                    model: currentChatModel
                )
                await MainActor.run {
                    self.errorRecoverySuggestion = response
                }
            } catch {
                // Silently fail - error recovery is best-effort
            }
        }
    }

    func dismissErrorRecovery() {
        errorRecoverySuggestion = nil
        lastFailedCommand = nil
        lastFailedOutput = nil
    }

    // MARK: - File Explorer

    func updateFileExplorer(directory: String) {
        fileExplorerState.loadDirectory(directory)
    }

    func insertPathInTerminal(_ path: String) {
        insertCommandString(path)
    }

    func cdToDirectory(_ path: String) {
        insertCommandString("cd \"\(path)\"\n")
    }

    // MARK: - Workflows

    func loadWorkflows() {
        // Workflows stored in UserDefaults as JSON for now
        if let data = UserDefaults.standard.data(forKey: "terminus.workflows"),
           let decoded = try? JSONDecoder().decode([WorkflowSequence].self, from: data) {
            workflows = decoded
        }
    }

    func saveWorkflow(_ workflow: WorkflowSequence) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
        } else {
            workflows.append(workflow)
        }
        persistWorkflows()
    }

    func deleteWorkflow(_ workflow: WorkflowSequence) {
        workflows.removeAll { $0.id == workflow.id }
        persistWorkflows()
    }

    func runWorkflow(_ workflow: WorkflowSequence) {
        workflowRunner.start(workflow)
        if let step = workflowRunner.currentStep {
            executeAICommand(step.command)
        }
    }

    private func persistWorkflows() {
        if let data = try? JSONEncoder().encode(workflows) {
            UserDefaults.standard.set(data, forKey: "terminus.workflows")
        }
    }

    // MARK: - Command Palette Items

    func buildPaletteItems() -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        items.append(CommandPaletteItem(
            title: "Split Horizontally", icon: "rectangle.split.1x2", category: .action,
            action: { [weak self] in self?.splitFocused(direction: .horizontal) }
        ))
        items.append(CommandPaletteItem(
            title: "Split Vertically", icon: "rectangle.split.2x1", category: .action,
            action: { [weak self] in self?.splitFocused(direction: .vertical) }
        ))
        items.append(CommandPaletteItem(
            title: "Close Panel", icon: "xmark.square", category: .action,
            action: { [weak self] in self?.closeFocusedPanel() }
        ))
        items.append(CommandPaletteItem(
            title: "New Tab", icon: "plus.square", category: .action,
            action: { [weak self] in self?.addTab() }
        ))
        items.append(CommandPaletteItem(
            title: "Toggle Sidebar", icon: "sidebar.right", category: .action,
            action: { [weak self] in self?.showSidebar.toggle() }
        ))
        items.append(CommandPaletteItem(
            title: "Semantic Search", icon: "magnifyingglass", category: .action,
            action: { [weak self] in self?.showSemanticSearch = true }
        ))
        items.append(CommandPaletteItem(
            title: "Save Current Command", icon: "bookmark.fill", category: .action,
            action: { [weak self] in self?.showSaveCommandSheet = true }
        ))

        // AI command
        if isAIAvailable {
            items.append(CommandPaletteItem(
                title: "AI Command Bar", icon: "sparkles", category: .action,
                action: { [weak self] in self?.showNLBar.toggle() }
            ))
        }

        // New feature toggles
        items.append(CommandPaletteItem(
            title: "Command History", icon: "clock.arrow.circlepath", category: .action,
            action: { [weak self] in
                self?.loadHistory()
                self?.showHistoryPanel.toggle()
            }
        ))
        items.append(CommandPaletteItem(
            title: "File Explorer", icon: "folder", category: .action,
            action: { [weak self] in self?.showFileExplorer.toggle() }
        ))
        items.append(CommandPaletteItem(
            title: "Workflows", icon: "arrow.triangle.2.circlepath.circle", category: .action,
            action: { [weak self] in self?.showSidebar = true }
        ))
        items.append(CommandPaletteItem(
            title: "System Monitor", icon: "gauge.with.dots.needle.33percent", category: .action,
            action: { [weak self] in self?.showMetrics.toggle() }
        ))

        // Theme switching
        for t in TerminusTheme.allThemes {
            items.append(CommandPaletteItem(
                title: "Theme: \(t.name)",
                icon: t.isDark ? "moon.fill" : "sun.max.fill",
                category: .setting,
                action: { [weak self] in self?.applyTheme(t.id) }
            ))
        }

        // Saved commands
        for cmd in savedCommands {
            items.append(CommandPaletteItem(
                title: cmd.name,
                subtitle: cmd.commandTemplate,
                icon: "bookmark",
                category: .savedCommand,
                action: { [weak self] in self?.insertSavedCommand(cmd) }
            ))
        }

        // Recent history
        if let recent = try? historyEngine?.recentCommands(limit: 20) {
            let uniqueCommands = Array(Set(recent.map(\.command)).prefix(15))
            for cmd in uniqueCommands {
                items.append(CommandPaletteItem(
                    title: cmd, icon: "clock", category: .history,
                    action: { [weak self] in
                        let ws = self?.activeWorkspace
                        guard let ws,
                              let leaf = ws.allLeaves(in: ws.root).first(where: { $0.id == ws.focusedPanelID }),
                              let controller = self?.controllers[leaf.sessionID] else { return }
                        Task { await controller.sendString(cmd) }
                    }
                ))
            }
        }

        return items
    }
}

// MARK: - App Entry Point

@main
struct TerminusApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    MainView(appState: appState)
                } else {
                    OnboardingView(
                        secureStorage: appState.secureStorage,
                        theme: appState.theme
                    ) {
                        appState.completeOnboarding()
                    }
                }
            }
            .preferredColorScheme(appState.theme.isDark ? .dark : .light)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            TerminusCommands(appState: appState)
        }

        Settings {
            SettingsView(
                secureStorage: appState.secureStorage,
                currentThemeID: appState.settings.theme,
                currentFontSize: appState.settings.fontSize,
                currentFontFamily: appState.settings.fontFamily ?? "SF Mono",
                onThemeChanged: { appState.applyTheme($0) },
                onFontSizeChanged: { appState.applyFontSize($0) },
                onFontFamilyChanged: { appState.applyFontFamily($0) }
            )
        }
    }
}

// MARK: - Menu Commands

struct TerminusCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                appState.addTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Split Horizontally") {
                appState.splitFocused(direction: .horizontal)
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Split Vertically") {
                appState.splitFocused(direction: .vertical)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("Close Panel") {
                appState.closeFocusedPanel()
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Command Palette") {
                appState.showCommandPalette.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("AI Command Bar") {
                appState.showNLBar.toggle()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Semantic Search") {
                appState.showSemanticSearch.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Toggle Sidebar") {
                appState.showSidebar.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("System Monitor") {
                appState.showMetrics.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Command History") {
                appState.loadHistory()
                appState.showHistoryPanel.toggle()
            }
            .keyboardShortcut("y", modifiers: .command)

            Button("File Explorer") {
                appState.showFileExplorer.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Focus Next Panel") {
                appState.activeWorkspace.focusNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Focus Previous Panel") {
                appState.activeWorkspace.focusPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button("Focus Panel Right") {
                appState.activeWorkspace.focusInDirection(.horizontal, forward: true)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

            Button("Focus Panel Left") {
                appState.activeWorkspace.focusInDirection(.horizontal, forward: false)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

            Button("Focus Panel Down") {
                appState.activeWorkspace.focusInDirection(.vertical, forward: true)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Button("Focus Panel Up") {
                appState.activeWorkspace.focusInDirection(.vertical, forward: false)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @Bindable var appState: AppState

    private var theme: TerminusTheme { appState.theme }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab bar (only show if multiple tabs)
                if appState.windowState.tabs.count > 1 {
                    TabBarView(appState: appState)
                        .frame(height: 36)
                        .glassBackground(isDark: theme.isDark)
                }

                // Toolbar with glass treatment
                TerminusToolbar(appState: appState)
                    .frame(height: 40)
                    .glassBackground(isDark: theme.isDark)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [theme.chromeDivider, theme.chromeDivider.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 1)
                    }

                // Workflow progress bar
                WorkflowProgressView(
                    runner: appState.workflowRunner,
                    theme: theme,
                    onStop: { appState.workflowRunner.stop() }
                )

                // Main content area
                HStack(spacing: 0) {
                    // Left panels stack
                    if appState.showMetrics {
                        MetricsPanel(theme: theme)
                            .glassBackground(isDark: theme.isDark)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(theme.chromeDivider).frame(width: 0.5)
                            }
                            .terminusShadow(.soft)
                            .zIndex(1)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    if appState.showFileExplorer {
                        FileExplorerPanel(
                            state: appState.fileExplorerState,
                            theme: theme,
                            onInsertPath: { appState.insertPathInTerminal($0) },
                            onCdTo: { appState.cdToDirectory($0) }
                        )
                        .glassBackground(isDark: theme.isDark)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(theme.chromeDivider).frame(width: 0.5)
                        }
                        .terminusShadow(.soft)
                        .zIndex(1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    // Panel workspace
                    VStack(spacing: 0) {
                        PanelTreeView(
                            node: appState.activeWorkspace.root,
                            appState: appState
                        )

                        // Error recovery suggestion
                        if let errorSuggestion = appState.errorRecoverySuggestion {
                            AICommandBlockView(
                                response: errorSuggestion,
                                theme: theme,
                                onRun: { cmd in
                                    appState.dismissErrorRecovery()
                                    appState.executeAICommand(cmd)
                                },
                                onEdit: { cmd in
                                    appState.nlInput = cmd
                                    appState.dismissErrorRecovery()
                                    appState.showNLBar = true
                                },
                                onCopy: { appState.copyToClipboard($0) },
                                onReject: { appState.dismissErrorRecovery() }
                            )
                            .padding(.horizontal, TerminusDesign.spacingMD)
                            .padding(.vertical, TerminusDesign.spacingSM)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // AI Response overlay (above the NL bar)
                        if let response = appState.currentAIResponse {
                            AICommandBlockView(
                                response: response,
                                theme: theme,
                                onRun: { appState.executeAICommand($0) },
                                onEdit: { command in
                                    appState.nlInput = command
                                    appState.currentAIResponse = nil
                                },
                                onCopy: { appState.copyToClipboard($0) },
                                onReject: { appState.dismissAIResponse() }
                            )
                            .padding(.horizontal, TerminusDesign.spacingMD)
                            .padding(.vertical, TerminusDesign.spacingSM)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Command explanation overlay
                        if let explanation = appState.commandExplanation {
                            CommandExplanationView(
                                explanation: explanation,
                                theme: theme,
                                onDismiss: { appState.dismissExplanation() }
                            )
                            .padding(.horizontal, TerminusDesign.spacingMD)
                            .padding(.vertical, TerminusDesign.spacingSM)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // NL Input Bar (always visible at bottom when toggled)
                        if appState.showNLBar {
                            NLInputBar(
                                text: $appState.nlInput,
                                theme: theme,
                                isAIAvailable: appState.isAIAvailable,
                                isProcessing: appState.isAIProcessing,
                                currentModel: appState.currentChatModel.modelID,
                                suggestions: appState.fetchPredictions(
                                    prefix: appState.nlInput,
                                    sessionID: focusedSessionID
                                ),
                                onSubmit: { text, intent in
                                    appState.processNLInput(text, intent: intent)
                                },
                                onCancel: {
                                    appState.isAIProcessing = false
                                    appState.currentAIResponse = nil
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    // Right panels: History, Saved Commands
                    if appState.showHistoryPanel {
                        HistoryPanelView(
                            entries: appState.historyEntries,
                            favorites: appState.favoriteCommands,
                            theme: theme,
                            onSelect: { cmd in
                                appState.insertCommandString(cmd)
                            },
                            onRerun: { cmd in
                                appState.insertCommandString(cmd + "\n")
                            },
                            onToggleFavorite: { appState.toggleFavorite($0) },
                            onSearch: { query in
                                if query.isEmpty {
                                    appState.loadHistory()
                                } else {
                                    appState.historyEntries = (try? appState.historyEngine?.search(query: query, limit: 200)) ?? []
                                }
                            }
                        )
                        .glassBackground(isDark: theme.isDark)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(theme.chromeDivider).frame(width: 0.5)
                        }
                        .terminusShadow(.soft)
                        .zIndex(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    if appState.showSidebar {
                        SavedCommandsSidebar(
                            commands: appState.savedCommands,
                            theme: theme,
                            onSelect: { appState.insertSavedCommand($0) },
                            onDelete: { appState.deleteSavedCommand($0) },
                            onAdd: { appState.showSaveCommandSheet = true }
                        )
                        .glassBackground(isDark: theme.isDark)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(theme.chromeDivider).frame(width: 0.5)
                        }
                        .terminusShadow(.soft)
                        .zIndex(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .background(theme.backgroundColor)

            // Command palette overlay — glass floating panel
            if appState.showCommandPalette {
                Color.black.opacity(theme.isDark ? 0.5 : 0.25)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showCommandPalette = false }

                VStack {
                    CommandPaletteView(
                        isPresented: $appState.showCommandPalette,
                        items: appState.buildPaletteItems(),
                        theme: theme
                    )
                    .glassPanel(cornerRadius: TerminusDesign.radiusXL, shadow: .medium, isDark: theme.isDark)
                    .padding(.top, 80)
                    .padding(.horizontal, 40)

                    Spacer()
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(10)
            }

            // Semantic search overlay — glass floating panel
            if appState.showSemanticSearch {
                Color.black.opacity(theme.isDark ? 0.5 : 0.25)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showSemanticSearch = false }

                VStack {
                    SemanticSearchOverlay(
                        isPresented: $appState.showSemanticSearch,
                        query: $appState.semanticSearchQuery,
                        results: appState.semanticSearchResults,
                        theme: theme,
                        onSearch: { query in
                            Task {
                                await performSemanticSearch(query)
                            }
                        },
                        onSelect: { command in
                            appState.insertCommandString(command)
                            appState.showSemanticSearch = false
                        }
                    )
                    .glassPanel(cornerRadius: TerminusDesign.radiusXL, shadow: .medium, isDark: theme.isDark)
                    .padding(.top, 80)
                    .padding(.horizontal, 40)

                    Spacer()
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(TerminusDesign.springDefault, value: appState.showSidebar)
        .animation(TerminusDesign.springDefault, value: appState.showMetrics)
        .animation(TerminusDesign.springDefault, value: appState.showHistoryPanel)
        .animation(TerminusDesign.springDefault, value: appState.showFileExplorer)
        .animation(TerminusDesign.springSnappy, value: appState.showCommandPalette)
        .animation(TerminusDesign.springSnappy, value: appState.showSemanticSearch)
        .animation(TerminusDesign.springSnappy, value: appState.showNLBar)
        .animation(TerminusDesign.springDefault, value: appState.currentAIResponse?.id)
        .animation(TerminusDesign.springSnappy, value: appState.errorRecoverySuggestion?.id)
        .animation(TerminusDesign.springSnappy, value: appState.commandExplanation?.command)
        .sheet(isPresented: $appState.showSaveCommandSheet) {
            SaveCommandSheet(
                isPresented: $appState.showSaveCommandSheet,
                initialCommand: "",
                theme: theme,
                onSave: { appState.saveCommand($0) }
            )
        }
    }

    private var focusedSessionID: SessionID {
        let ws = appState.activeWorkspace
        let leaves = ws.allLeaves(in: ws.root)
        return leaves.first(where: { $0.id == ws.focusedPanelID })?.sessionID ?? ""
    }

    private func performSemanticSearch(_ query: String) async {
        guard let pipeline = appState.embeddingPipeline, !query.isEmpty else {
            appState.semanticSearchResults = []
            return
        }

        do {
            let results = try await pipeline.search(query: query, limit: 15)
            appState.semanticSearchResults = results.map { ($0.matchedText, $0.similarity) }
        } catch {
            if let history = appState.historyEngine {
                let entries = (try? history.search(query: query, limit: 15)) ?? []
                appState.semanticSearchResults = entries.map { ($0.command, 1.0) }
            }
        }
    }
}

// MARK: - Insert Command String Helper

extension AppState {
    func insertCommandString(_ command: String) {
        let ws = activeWorkspace
        let leaves = ws.allLeaves(in: ws.root)
        guard let focused = leaves.first(where: { $0.id == ws.focusedPanelID }),
              let controller = controllers[focused.sessionID] else { return }
        Task { await controller.sendString(command) }
    }
}

// MARK: - Semantic Search Overlay

struct SemanticSearchOverlay: View {
    @Binding var isPresented: Bool
    @Binding var query: String
    let results: [(String, Float)]
    let theme: TerminusTheme
    let onSearch: (String) -> Void
    let onSelect: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var selectedIndex: Int = 0
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(TerminusAccent.primary)

                TextField("Search commands semantically...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.terminusUI(size: 15))
                    .foregroundStyle(theme.chromeText)
                    .focused($isFocused)
                    .onSubmit {
                        if selectedIndex < results.count {
                            onSelect(results[selectedIndex].0)
                        }
                    }
                    .onChange(of: query) { _, newValue in
                        selectedIndex = 0
                        // Debounce: wait 400ms before triggering API search
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled else { return }
                            onSearch(newValue)
                        }
                    }
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingMD)

            Divider().background(theme.chromeDivider)

            if results.isEmpty && !query.isEmpty {
                VStack {
                    Spacer()
                    Text("No results")
                        .font(.terminusUI(size: 14))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Spacer()
                }
                .frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                            HStack {
                                Text(result.0)
                                    .font(.terminusMono(size: 13))
                                    .foregroundStyle(theme.chromeText)
                                    .lineLimit(2)

                                Spacer()

                                Text("\(Int(result.1 * 100))%")
                                    .font(.terminusUI(size: 10, weight: .medium))
                                    .foregroundStyle(theme.chromeTextTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(theme.chromeHover)
                                    )
                            }
                            .padding(.horizontal, TerminusDesign.spacingMD)
                            .padding(.vertical, 6)
                            .background(
                                index == selectedIndex
                                    ? TerminusAccent.primary.opacity(0.15)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(result.0) }
                        }
                    }
                    .padding(.vertical, TerminusDesign.spacingXS)
                }
                .frame(maxHeight: 300)
            }

            Divider().background(theme.chromeDivider)

            HStack(spacing: TerminusDesign.spacingMD) {
                Text("Powered by OpenRouter embeddings")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)
                Spacer()
                keyHint("Esc", label: "close")
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 6)
        }
        .frame(width: 550)
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusLG)
                .fill(theme.chromeBackground)
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.2), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusLG)
                .stroke(theme.chromeBorder, lineWidth: 1)
        )
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < results.count - 1 { selectedIndex += 1 }
            return .handled
        }
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.terminusUI(size: 10, weight: .medium))
                .foregroundStyle(theme.chromeTextTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(theme.chromeHover))
            Text(label)
                .font(.terminusUI(size: 10))
                .foregroundStyle(theme.chromeTextTertiary)
        }
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @Bindable var appState: AppState

    private var theme: TerminusTheme { appState.theme }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(appState.windowState.tabs.enumerated()), id: \.element.id) { index, tab in
                TabItemView(
                    title: tab.title,
                    isActive: index == appState.windowState.activeTabIndex,
                    theme: theme,
                    onSelect: { appState.windowState.selectTab(at: index) },
                    onClose: {
                        if appState.windowState.tabs.count > 1 {
                            appState.windowState.closeTab(at: index)
                        }
                    }
                )

                if index < appState.windowState.tabs.count - 1 {
                    Rectangle()
                        .fill(theme.chromeDivider)
                        .frame(width: 1)
                }
            }

            Button(action: { appState.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.chromeTextTertiary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TerminusDesign.spacingSM)

            Spacer()
        }
        .padding(.horizontal, TerminusDesign.spacingXS)
    }
}

struct TabItemView: View {
    let title: String
    let isActive: Bool
    let theme: TerminusTheme
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: TerminusDesign.spacingXS) {
            Text(title)
                .font(.terminusUI(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? theme.chromeText : theme.chromeTextSecondary)
                .lineLimit(1)

            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, TerminusDesign.spacingXS)
        .background(isActive ? theme.chromeHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: TerminusDesign.radiusSM))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Panel Tree View

struct PanelTreeView: View {
    let node: PanelNode
    @Bindable var appState: AppState

    var body: some View {
        switch node {
        case .leaf(let leaf):
            let controller = appState.controllerForSession(leaf.sessionID)
            TerminalPanelView(
                controller: controller,
                theme: appState.theme,
                isFocused: leaf.id == appState.activeWorkspace.focusedPanelID
            )
            .onTapGesture {
                appState.activeWorkspace.focusPanel(leaf.id)
            }

        case .split(let split):
            SplitPanelView(split: split, appState: appState)
        }
    }
}

// MARK: - Split Panel View

struct SplitPanelView: View {
    let split: PanelSplit
    @Bindable var appState: AppState

    var body: some View {
        let ratio = appState.activeWorkspace.splitRatios[split.id] ?? split.ratio

        GeometryReader { geometry in
            let isHorizontal = split.direction == .horizontal

            if isHorizontal {
                HStack(spacing: 0) {
                    PanelTreeView(node: split.first, appState: appState)
                        .frame(width: max(TerminusDesign.panelMinWidth, geometry.size.width * ratio - 1))

                    SplitDivider(
                        isHorizontal: true,
                        theme: appState.theme,
                        onDrag: { delta in
                            let newRatio = ratio + delta / geometry.size.width
                            appState.activeWorkspace.updateSplitRatio(split.id, ratio: newRatio)
                        },
                        onDoubleTap: {
                            appState.activeWorkspace.updateSplitRatio(split.id, ratio: 0.5)
                        }
                    )

                    PanelTreeView(node: split.second, appState: appState)
                }
            } else {
                VStack(spacing: 0) {
                    PanelTreeView(node: split.first, appState: appState)
                        .frame(height: max(TerminusDesign.panelMinHeight, geometry.size.height * ratio - 1))

                    SplitDivider(
                        isHorizontal: false,
                        theme: appState.theme,
                        onDrag: { delta in
                            let newRatio = ratio + delta / geometry.size.height
                            appState.activeWorkspace.updateSplitRatio(split.id, ratio: newRatio)
                        },
                        onDoubleTap: {
                            appState.activeWorkspace.updateSplitRatio(split.id, ratio: 0.5)
                        }
                    )

                    PanelTreeView(node: split.second, appState: appState)
                }
            }
        }
    }
}

// MARK: - Split Divider

struct SplitDivider: View {
    let isHorizontal: Bool
    let theme: TerminusTheme
    let onDrag: (CGFloat) -> Void
    let onDoubleTap: () -> Void

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? TerminusAccent.primary.opacity(0.5) : theme.chromeDivider)
            .frame(
                width: isHorizontal ? 2 : nil,
                height: isHorizontal ? nil : 2
            )
            .contentShape(Rectangle().size(
                width: isHorizontal ? TerminusDesign.dividerHitArea : 10000,
                height: isHorizontal ? 10000 : TerminusDesign.dividerHitArea
            ))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let delta = isHorizontal
                            ? value.translation.width
                            : value.translation.height
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onHover { hovering in
                if hovering {
                    if isHorizontal {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Toolbar

struct TerminusToolbar: View {
    @Bindable var appState: AppState

    private var theme: TerminusTheme { appState.theme }

    var body: some View {
        HStack(spacing: 0) {
            // Left group: panel management
            HStack(spacing: TerminusDesign.spacingSM) {
                toolbarButton("rectangle.split.1x2", active: false, tooltip: "Split Horizontally (Cmd+D)") {
                    appState.splitFocused(direction: .horizontal)
                }
                toolbarButton("rectangle.split.2x1", active: false, tooltip: "Split Vertically (Cmd+Shift+D)") {
                    appState.splitFocused(direction: .vertical)
                }

                Divider().frame(height: 14)

                toolbarButton("xmark.square", active: false, tooltip: "Close Panel (Cmd+W)") {
                    appState.closeFocusedPanel()
                }

                let count = appState.activeWorkspace.panelCount
                if count > 1 {
                    Text("\(count) panels")
                        .font(.terminusUI(size: 10))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
            }
            .fixedSize()

            Spacer(minLength: TerminusDesign.spacingSM)

            // Right group: toggle panels — fixedSize so they never compress
            HStack(spacing: TerminusDesign.spacingSM) {
                // AI
                Button {
                    withAnimation(TerminusDesign.springSnappy) {
                        appState.showNLBar.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        if appState.isAIAvailable {
                            Circle()
                                .fill(TerminusAccent.success)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.showNLBar ? TerminusAccent.primary : theme.chromeTextSecondary)
                .help("AI Command Bar (Cmd+L)")

                toolbarButton("command", active: false, tooltip: "Command Palette (Cmd+Shift+P)") {
                    appState.showCommandPalette.toggle()
                }

                toolbarButton("magnifyingglass", active: false, tooltip: "Search (Cmd+Shift+F)") {
                    appState.showSemanticSearch.toggle()
                }

                Divider().frame(height: 14)

                // Panel toggles
                toolbarButton("clock.arrow.circlepath", active: appState.showHistoryPanel, tooltip: "History (Cmd+Y)") {
                    appState.loadHistory()
                    appState.showHistoryPanel.toggle()
                }

                toolbarButton("folder", active: appState.showFileExplorer, tooltip: "File Explorer (Cmd+Shift+E)") {
                    appState.showFileExplorer.toggle()
                }

                toolbarButton("chart.bar", active: appState.showMetrics, tooltip: "System Monitor (Cmd+Shift+M)") {
                    appState.showMetrics.toggle()
                }

                toolbarButton("sidebar.right", active: appState.showSidebar, tooltip: "Saved Commands (Cmd+B)") {
                    appState.showSidebar.toggle()
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
    }

    private func toolbarButton(_ icon: String, active: Bool, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: active ? icon + ".fill" : icon)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? TerminusAccent.primary : theme.chromeTextSecondary)
        .help(tooltip)
    }
}
