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
        } catch {
            print("Failed to initialize database: \(error)")
            self.dataAccess = nil
            self.historyEngine = nil
            self.predictionEngine = nil
            self.savedCommandsManager = nil
            self.aiService = nil
            self.embeddingPipeline = nil
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

    // UI state
    var showSidebar: Bool = false
    var showCommandPalette: Bool = false
    var showSemanticSearch: Bool = false
    var showSaveCommandSheet: Bool = false
    var showMetrics: Bool = false
    var savedCommands: [SavedCommand] = []
    var semanticSearchResults: [(String, Float)] = []
    var semanticSearchQuery: String = ""

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

        // Wire command completion to history engine + n-gram recording
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

                // Main content area
                HStack(spacing: 0) {
                    // System metrics panel (left) — glass sidebar
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

                    // Panel workspace
                    PanelTreeView(
                        node: appState.activeWorkspace.root,
                        appState: appState
                    )

                    // Saved commands sidebar (right) — glass sidebar
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
        .animation(TerminusDesign.springSnappy, value: appState.showCommandPalette)
        .animation(TerminusDesign.springSnappy, value: appState.showSemanticSearch)
        .sheet(isPresented: $appState.showSaveCommandSheet) {
            SaveCommandSheet(
                isPresented: $appState.showSaveCommandSheet,
                initialCommand: "",
                theme: theme,
                onSave: { appState.saveCommand($0) }
            )
        }
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
        HStack(spacing: TerminusDesign.spacingMD) {
            Button(action: { appState.splitFocused(direction: .horizontal) }) {
                Image(systemName: "rectangle.split.1x2")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chromeTextSecondary)
            .help("Split Horizontally (Cmd+D)")

            Button(action: { appState.splitFocused(direction: .vertical) }) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chromeTextSecondary)
            .help("Split Vertically (Cmd+Shift+D)")

            Divider()
                .frame(height: 16)

            Button(action: { appState.closeFocusedPanel() }) {
                Image(systemName: "xmark.square")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chromeTextSecondary)
            .help("Close Panel (Cmd+W)")

            Spacer()

            let count = appState.activeWorkspace.panelCount
            if count > 1 {
                Text("\(count) panels")
                    .font(.terminusUI(size: 11))
                    .foregroundStyle(theme.chromeTextTertiary)
            }

            Spacer()

            Button(action: { appState.showCommandPalette.toggle() }) {
                Image(systemName: "command")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chromeTextSecondary)
            .help("Command Palette (Cmd+Shift+P)")

            Button(action: { appState.showSemanticSearch.toggle() }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chromeTextSecondary)
            .help("Search (Cmd+Shift+F)")

            Button(action: { appState.showMetrics.toggle() }) {
                Image(systemName: appState.showMetrics ? "gauge.with.dots.needle.33percent.badge.plus" : "gauge.with.dots.needle.33percent")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                appState.showMetrics ? TerminusAccent.primary : theme.chromeTextSecondary
            )
            .help("System Monitor (Cmd+Shift+M)")

            Button(action: { appState.showSidebar.toggle() }) {
                Image(systemName: appState.showSidebar ? "sidebar.right.fill" : "sidebar.right")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                appState.showSidebar ? TerminusAccent.primary : theme.chromeTextSecondary
            )
            .help("Saved Commands (Cmd+B)")
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
    }
}
