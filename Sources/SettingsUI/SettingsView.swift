import SwiftUI
import SharedModels
import SharedUI
import SecureStorage
import AIService

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case terminal = "Terminal"
    case ai = "AI"
    case shortcuts = "Shortcuts"
}

// MARK: - Settings View

public struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var settings: UserSettings = .defaults

    // Appearance
    @State private var selectedThemeID: String
    @State private var fontSize: Double
    @State private var fontFamily: String
    @State private var windowOpacity: Double = 1.0
    @State private var enableVibrancy: Bool = false
    @State private var cursorStyle: CursorStyle = .block
    @State private var cursorBlink: Bool = true
    @State private var accentColorHue: Double = 0.6

    // AI
    @State private var apiKey: String = ""
    @State private var hasAPIKey: Bool = false
    @State private var chatModel: String = DefaultModels.chat.modelID
    @State private var embeddingModel: String = DefaultModels.embedding.modelID
    @State private var isValidatingKey: Bool = false
    @State private var keyValidationResult: KeyValidationResult?
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Double = 4096
    @State private var safetyLevel: CommandSafetyLevel = .dangerous
    @State private var showModelBrowser: Bool = false
    @State private var availableModels: [OpenRouterModel] = []
    @State private var isLoadingModels: Bool = false
    @State private var modelSearchText: String = ""

    private let secureStorage: SecureStorage
    private let onThemeChanged: (String) -> Void
    private let onFontSizeChanged: (Double) -> Void
    private let onFontFamilyChanged: (String) -> Void

    private let availableFonts = [
        "SF Mono", "Menlo", "Monaco", "Courier New",
        "JetBrains Mono", "Fira Code", "Source Code Pro",
        "IBM Plex Mono", "Hack", "Cascadia Code",
    ]

    public init(
        secureStorage: SecureStorage = SecureStorage(),
        currentThemeID: String = "defaultLight",
        currentFontSize: Double = 14,
        currentFontFamily: String = "SF Mono",
        onThemeChanged: @escaping (String) -> Void = { _ in },
        onFontSizeChanged: @escaping (Double) -> Void = { _ in },
        onFontFamilyChanged: @escaping (String) -> Void = { _ in }
    ) {
        self.secureStorage = secureStorage
        self._selectedThemeID = State(initialValue: currentThemeID)
        self._fontSize = State(initialValue: currentFontSize)
        self._fontFamily = State(initialValue: currentFontFamily)
        self.onThemeChanged = onThemeChanged
        self.onFontSizeChanged = onFontSizeChanged
        self.onFontFamilyChanged = onFontFamilyChanged
    }

    // Get the preview theme for settings
    private var previewTheme: TerminusTheme {
        TerminusTheme.theme(withID: selectedThemeID)
    }

    public var body: some View {
        HSplitView {
            // Sidebar
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: iconFor(tab))
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: TerminusDesign.spacingLG) {
                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .appearance:
                        appearanceSettings
                    case .terminal:
                        terminalSettings
                    case .ai:
                        aiSettings
                    case .shortcuts:
                        shortcutsSettings
                    }
                }
                .padding(TerminusDesign.spacingXL)
            }
            .frame(minWidth: 520)
        }
        .frame(width: 760, height: 600)
        .onAppear {
            hasAPIKey = (try? secureStorage.exists(key: SecureStorage.openRouterAPIKey)) ?? false
            // Load persisted AI settings
            if let savedTemp = UserDefaults.standard.object(forKey: "terminus.ai.temperature") as? Double {
                temperature = savedTemp
            }
            if let savedTokens = UserDefaults.standard.object(forKey: "terminus.ai.maxTokens") as? Double {
                maxTokens = savedTokens
            }
            if let savedChatModel = UserDefaults.standard.string(forKey: "terminus.ai.chatModel") {
                chatModel = savedChatModel
            }
            if let savedEmbedModel = UserDefaults.standard.string(forKey: "terminus.ai.embeddingModel") {
                embeddingModel = savedEmbedModel
            }
        }
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            sectionHeader("Shell")

            LabeledContent("Default Shell") {
                TextField("", text: $settings.defaultShell)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }

            LabeledContent("Startup Directory") {
                TextField("", text: $settings.startupDirectory)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }

            sectionHeader("Behavior")

            Toggle("Enable bell sound", isOn: $settings.enableBell)
            Toggle("Smart predictions", isOn: $settings.predictionEnabled)
            Toggle("Auto-embed commands for semantic search", isOn: $settings.autoEmbed)

            sectionHeader("Data")

            LabeledContent("Scrollback limit") {
                TextField("", value: $settings.scrollbackLimit, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        }
    }

    // MARK: - Appearance Settings

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingLG) {
            sectionHeader("Theme")

            // Light themes
            Text("Light")
                .font(.terminusUI(size: 11))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
                ForEach(TerminusTheme.allThemes.filter({ !$0.isDark })) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: selectedThemeID == theme.id,
                        action: {
                            selectedThemeID = theme.id
                            onThemeChanged(theme.id)
                        }
                    )
                }
            }

            // Dark themes
            Text("Dark")
                .font(.terminusUI(size: 11))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
                ForEach(TerminusTheme.allThemes.filter({ $0.isDark })) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: selectedThemeID == theme.id,
                        action: {
                            selectedThemeID = theme.id
                            onThemeChanged(theme.id)
                        }
                    )
                }
            }

            Divider()

            sectionHeader("Font")

            HStack(spacing: TerminusDesign.spacingLG) {
                Picker("Family", selection: $fontFamily) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font)
                            .font(.custom(font, size: 13))
                            .tag(font)
                    }
                }
                .frame(width: 200)
                .onChange(of: fontFamily) { _, newValue in
                    onFontFamilyChanged(newValue)
                }

                VStack(alignment: .leading) {
                    Text("Size: \(Int(fontSize))pt")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $fontSize, in: 10...28, step: 1)
                        .frame(width: 150)
                        .onChange(of: fontSize) { _, newValue in
                            onFontSizeChanged(newValue)
                        }
                }
            }

            // Font preview
            Text("The quick brown fox jumps over the lazy dog\n$ git commit -m \"fix: resolve login bug\" && git push")
                .font(.custom(fontFamily, size: fontSize))
                .foregroundStyle(previewTheme.foregroundColor)
                .padding(TerminusDesign.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                        .fill(previewTheme.backgroundColor)
                )

            Divider()

            sectionHeader("Window")

            HStack(spacing: TerminusDesign.spacingLG) {
                VStack(alignment: .leading) {
                    Text("Opacity: \(Int(windowOpacity * 100))%")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $windowOpacity, in: 0.5...1.0, step: 0.05)
                        .frame(width: 200)
                }

                Toggle("Background blur (vibrancy)", isOn: $enableVibrancy)
            }

            Divider()

            sectionHeader("Cursor")

            HStack(spacing: TerminusDesign.spacingLG) {
                Picker("Style", selection: $cursorStyle) {
                    Label("Block", systemImage: "square.fill").tag(CursorStyle.block)
                    Label("Underline", systemImage: "underline").tag(CursorStyle.underline)
                    Label("Bar", systemImage: "line.vertical").tag(CursorStyle.bar)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Toggle("Blink", isOn: $cursorBlink)
            }

            Divider()

            sectionHeader("Accent Color")

            HStack(spacing: TerminusDesign.spacingMD) {
                ForEach([
                    ("Blue", 0.6),
                    ("Purple", 0.75),
                    ("Green", 0.35),
                    ("Orange", 0.08),
                    ("Red", 0.0),
                    ("Cyan", 0.5),
                ], id: \.0) { name, hue in
                    Circle()
                        .fill(Color(hue: hue, saturation: 0.7, brightness: 0.9))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(
                                accentColorHue == hue ? Color.primary : Color.clear,
                                lineWidth: 2
                            )
                        )
                        .onTapGesture { accentColorHue = hue }
                        .help(name)
                }
            }
        }
    }

    // MARK: - Terminal Settings

    private var terminalSettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            sectionHeader("Shell Integration")

            Text("Terminus injects OSC 133 hooks into your shell for command detection, exit code tracking, and directory monitoring.")
                .font(.terminusUI(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sectionHeader("Environment")

            VStack(alignment: .leading, spacing: 4) {
                Text("TERM = xterm-256color")
                Text("COLORTERM = truecolor")
                Text("TERM_PROGRAM = Terminus")
            }
            .font(.terminusMono(size: 12))
            .foregroundStyle(.secondary)
            .padding(TerminusDesign.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                    .fill(Color.primary.opacity(0.03))
            )

            sectionHeader("Key Bindings")

            Text("Terminal keybindings follow standard xterm conventions. Special keys are translated to VT100/xterm escape sequences.")
                .font(.terminusUI(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - AI Settings (Enhanced)

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingLG) {
            // Connection Status Header
            aiConnectionStatus

            Divider()

            // API Key Management
            sectionHeader("OpenRouter API Key")
            apiKeyManagement

            Divider()

            // Model Selection
            sectionHeader("Model Configuration")
            modelConfiguration

            Divider()

            // AI Parameters
            sectionHeader("AI Parameters")
            aiParameters

            Divider()

            // Safety Settings
            sectionHeader("Safety")
            safetySettings

            Divider()

            // Feature Toggles
            sectionHeader("AI Features")
            aiFeatureToggles
        }
    }

    // MARK: - AI Connection Status

    private var aiConnectionStatus: some View {
        HStack(spacing: TerminusDesign.spacingMD) {
            // Status icon
            ZStack {
                Circle()
                    .fill(hasAPIKey ? TerminusAccent.success.opacity(0.15) : TerminusAccent.error.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(hasAPIKey ? TerminusAccent.success : TerminusAccent.error)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(hasAPIKey ? "Connected to OpenRouter" : "Not Connected")
                    .font(.terminusUI(size: 14, weight: .semibold))

                if hasAPIKey {
                    HStack(spacing: TerminusDesign.spacingXS) {
                        Text("Model:")
                            .font(.terminusUI(size: 11))
                            .foregroundStyle(.secondary)
                        Text(chatModel.split(separator: "/").last.map(String.init) ?? chatModel)
                            .font(.terminusMono(size: 11))
                            .foregroundStyle(TerminusAccent.primary)
                    }
                } else {
                    Text("Enter your OpenRouter API key to enable AI features")
                        .font(.terminusUI(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if hasAPIKey {
                Button("Validate") {
                    validateKey()
                }
                .buttonStyle(.bordered)
                .disabled(isValidatingKey)

                if isValidatingKey {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(TerminusDesign.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .fill(
                    hasAPIKey
                        ? TerminusAccent.success.opacity(0.05)
                        : Color.primary.opacity(0.03)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .stroke(
                    hasAPIKey ? TerminusAccent.success.opacity(0.2) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - API Key Management

    private var apiKeyManagement: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
            if hasAPIKey {
                HStack(spacing: TerminusDesign.spacingMD) {
                    HStack(spacing: TerminusDesign.spacingSM) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(TerminusAccent.primary)
                        Text("sk-or-\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                            .font(.terminusMono(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Update Key") {
                        hasAPIKey = false
                    }
                    .buttonStyle(.bordered)

                    Button("Remove") {
                        try? secureStorage.delete(key: SecureStorage.openRouterAPIKey)
                        hasAPIKey = false
                        keyValidationResult = nil
                    }
                    .foregroundStyle(TerminusAccent.error)
                    .buttonStyle(.bordered)
                }

                // Validation result
                if let result = keyValidationResult {
                    HStack(spacing: TerminusDesign.spacingXS) {
                        Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(result.isValid ? TerminusAccent.success : TerminusAccent.error)
                        Text(result.message)
                            .font(.terminusUI(size: 11))
                            .foregroundStyle(result.isValid ? TerminusAccent.success : TerminusAccent.error)
                    }
                }
            } else {
                HStack(spacing: TerminusDesign.spacingSM) {
                    Image(systemName: "key")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    SecureField("sk-or-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)

                    Button("Save Key") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty)
                }

                Text("Get your API key at openrouter.ai/keys")
                    .font(.terminusUI(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Model Configuration

    private var modelConfiguration: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            // Chat model
            VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
                Text("Chat Model")
                    .font(.terminusUI(size: 12, weight: .medium))

                HStack {
                    TextField("e.g. anthropic/claude-sonnet-4", text: $chatModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .onChange(of: chatModel) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "terminus.ai.chatModel")
                        }

                    Button("Browse") {
                        loadModels()
                        showModelBrowser = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasAPIKey)
                }

                Text("Used for natural language commands, explanations, and suggestions")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Embedding model
            VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
                Text("Embedding Model")
                    .font(.terminusUI(size: 12, weight: .medium))

                TextField("e.g. openai/text-embedding-3-small", text: $embeddingModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: embeddingModel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "terminus.ai.embeddingModel")
                    }

                Text("Used for semantic search over command history")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showModelBrowser) {
            modelBrowserSheet
        }
    }

    // MARK: - Model Browser Sheet

    private var modelBrowserSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("OpenRouter Models")
                    .font(.terminusUI(size: 15, weight: .semibold))

                Spacer()

                Button("Done") {
                    showModelBrowser = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(TerminusDesign.spacingMD)

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $modelSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Model list
            if isLoadingModels {
                VStack {
                    Spacer()
                    ProgressView("Loading models...")
                    Spacer()
                }
            } else {
                List(filteredModels, id: \.id) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(.terminusUI(size: 13, weight: .medium))
                            Text(model.id)
                                .font(.terminusMono(size: 11))
                                .foregroundStyle(.secondary)
                            if let ctx = model.contextLength {
                                Text("\(ctx / 1000)K context")
                                    .font(.terminusUI(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if model.id == chatModel {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TerminusAccent.primary)
                        }

                        Button("Select") {
                            chatModel = model.id
                            UserDefaults.standard.set(model.id, forKey: "terminus.ai.chatModel")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .frame(width: 560, height: 480)
    }

    private var filteredModels: [OpenRouterModel] {
        if modelSearchText.isEmpty {
            return availableModels
        }
        let query = modelSearchText.lowercased()
        return availableModels.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    // MARK: - AI Parameters

    private var aiParameters: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
                HStack {
                    Text("Temperature")
                        .font(.terminusUI(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .font(.terminusMono(size: 12))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                    .frame(maxWidth: 300)
                    .onChange(of: temperature) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "terminus.ai.temperature")
                    }
                Text("Lower = more precise commands, Higher = more creative suggestions")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
                HStack {
                    Text("Max Tokens")
                        .font(.terminusUI(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(maxTokens))")
                        .font(.terminusMono(size: 12))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $maxTokens, in: 256...8192, step: 256)
                    .frame(maxWidth: 300)
                    .onChange(of: maxTokens) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "terminus.ai.maxTokens")
                    }
                Text("Maximum response length for AI commands")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Safety Settings

    private var safetySettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
                Text("Require confirmation for")
                    .font(.terminusUI(size: 12, weight: .medium))

                Picker("", selection: $safetyLevel) {
                    Text("All commands").tag(CommandSafetyLevel.safe)
                    Text("Moderate+ (file modifications)").tag(CommandSafetyLevel.moderate)
                    Text("Dangerous+ (destructive ops)").tag(CommandSafetyLevel.dangerous)
                    Text("Critical only (system-level)").tag(CommandSafetyLevel.critical)
                }
                .pickerStyle(.radioGroup)

                Text("AI-generated commands at or above this risk level will require explicit confirmation before execution")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Safety preview
            VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
                safetyPreviewRow("ls -la", level: .safe)
                safetyPreviewRow("mkdir new_folder", level: .moderate)
                safetyPreviewRow("rm -rf node_modules", level: .dangerous)
                safetyPreviewRow("sudo rm -rf /", level: .critical)
            }
            .padding(TerminusDesign.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    private func safetyPreviewRow(_ command: String, level: CommandSafetyLevel) -> some View {
        HStack(spacing: TerminusDesign.spacingSM) {
            Image(systemName: iconForSafetyLevel(level))
                .font(.system(size: 10))
                .foregroundStyle(colorForSafetyLevel(level))
                .frame(width: 16)

            Text(command)
                .font(.terminusMono(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if level >= safetyLevel {
                Text("Requires confirmation")
                    .font(.terminusUI(size: 9))
                    .foregroundStyle(TerminusAccent.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.warning.opacity(0.1)))
            } else {
                Text("Auto-execute")
                    .font(.terminusUI(size: 9))
                    .foregroundStyle(TerminusAccent.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.success.opacity(0.1)))
            }
        }
    }

    // MARK: - AI Feature Toggles

    private var aiFeatureToggles: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            Toggle("Enable AI features", isOn: $settings.enableAI)

            VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
                featureToggleRow(
                    icon: "text.bubble",
                    title: "Natural Language Commands",
                    description: "Type requests in plain English to generate shell commands",
                    isEnabled: settings.enableAI
                )
                featureToggleRow(
                    icon: "lightbulb",
                    title: "Command Explanations",
                    description: "Get AI-powered explanations for commands",
                    isEnabled: settings.enableAI
                )
                featureToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Error Recovery Suggestions",
                    description: "AI suggests fixes when commands fail",
                    isEnabled: settings.enableAI
                )
                featureToggleRow(
                    icon: "magnifyingglass",
                    title: "Semantic Search",
                    description: "Search command history using natural language",
                    isEnabled: settings.enableAI
                )
            }
            .padding(.leading, TerminusDesign.spacingMD)
        }
    }

    private func featureToggleRow(icon: String, title: String, description: String, isEnabled: Bool) -> some View {
        HStack(alignment: .top, spacing: TerminusDesign.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isEnabled ? TerminusAccent.primary : Color.gray)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.terminusUI(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                Text(description)
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    // MARK: - Shortcuts

    private var shortcutsSettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            sectionHeader("Panel Management")
            shortcutRow("Split Horizontally", "Cmd + D")
            shortcutRow("Split Vertically", "Cmd + Shift + D")
            shortcutRow("Close Panel", "Cmd + W")
            shortcutRow("New Tab", "Cmd + T")
            shortcutRow("Next Panel", "Cmd + Shift + ]")
            shortcutRow("Previous Panel", "Cmd + Shift + [")
            shortcutRow("Focus Right", "Cmd + Option + Right")
            shortcutRow("Focus Left", "Cmd + Option + Left")

            sectionHeader("AI & Tools")
            shortcutRow("AI Command Bar", "Cmd + L")
            shortcutRow("Command Palette", "Cmd + Shift + P")
            shortcutRow("Semantic Search", "Cmd + Shift + F")
            shortcutRow("Toggle Sidebar", "Cmd + B")
            shortcutRow("System Monitor", "Cmd + Shift + M")
            shortcutRow("Settings", "Cmd + ,")

            sectionHeader("Terminal")
            shortcutRow("Copy", "Cmd + C")
            shortcutRow("Paste", "Cmd + V")
            shortcutRow("Clear", "Cmd + K")
        }
    }

    // MARK: - Actions

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        try? secureStorage.store(
            key: SecureStorage.openRouterAPIKey,
            value: apiKey
        )
        hasAPIKey = true
        apiKey = ""
        validateKey()
    }

    private func validateKey() {
        isValidatingKey = true
        keyValidationResult = nil

        Task {
            do {
                let storage = SecureStorage()
                let ai = AIServiceClient(secureStorage: storage)
                let valid = try await ai.validateAPIKey()
                await MainActor.run {
                    isValidatingKey = false
                    keyValidationResult = KeyValidationResult(
                        isValid: valid,
                        message: valid ? "API key is valid" : "API key validation failed"
                    )
                }
            } catch {
                await MainActor.run {
                    isValidatingKey = false
                    keyValidationResult = KeyValidationResult(
                        isValid: false,
                        message: "Validation failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func loadModels() {
        isLoadingModels = true
        Task {
            do {
                let storage = SecureStorage()
                let ai = AIServiceClient(secureStorage: storage)
                let models = try await ai.listModels()
                await MainActor.run {
                    availableModels = models
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    isLoadingModels = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.terminusUI(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func iconFor(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: "gear"
        case .appearance: "paintbrush"
        case .terminal: "terminal"
        case .ai: "sparkles"
        case .shortcuts: "keyboard"
        }
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.terminusUI(size: 13))
            Spacer()
            Text(shortcut)
                .font(.terminusMono(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    private func iconForSafetyLevel(_ level: CommandSafetyLevel) -> String {
        switch level {
        case .safe: "checkmark.circle"
        case .moderate: "pencil.circle"
        case .dangerous: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }

    private func colorForSafetyLevel(_ level: CommandSafetyLevel) -> Color {
        switch level {
        case .safe: TerminusAccent.success
        case .moderate: TerminusAccent.warning
        case .dangerous: TerminusAccent.error
        case .critical: TerminusAccent.error
        }
    }
}

// MARK: - Key Validation Result

struct KeyValidationResult {
    let isValid: Bool
    let message: String
}

// MARK: - Theme Preview Card

struct ThemePreviewCard: View {
    let theme: TerminusTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Mini preview
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Circle().fill(.yellow).frame(width: 5, height: 5)
                    Circle().fill(.green).frame(width: 5, height: 5)
                }
                .padding(.bottom, 2)

                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.foregroundColor.opacity(0.3))
                    .frame(width: 60, height: 3)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.cursorColor)
                        .frame(width: 4, height: 8)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.foregroundColor.opacity(0.2))
                        .frame(width: 40, height: 3)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.foregroundColor.opacity(0.15))
                    .frame(width: 50, height: 3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(theme.name)
                .font(.terminusUI(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? TerminusAccent.primary : Color.clear, lineWidth: 2)
        )
        .onTapGesture(perform: action)
    }
}
