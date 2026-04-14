import SwiftUI
import SharedModels
import SharedUI
import SecureStorage

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
    @State private var selectedThemeID: String = "defaultDark"
    @State private var fontSize: Double = 14
    @State private var fontFamily: String = "SF Mono"
    @State private var windowOpacity: Double = 1.0
    @State private var enableVibrancy: Bool = false
    @State private var cursorStyle: CursorStyle = .block
    @State private var cursorBlink: Bool = true
    @State private var accentColorHue: Double = 0.6  // Blue

    // AI
    @State private var apiKey: String = ""
    @State private var hasAPIKey: Bool = false
    @State private var chatModel: String = DefaultModels.chat.modelID
    @State private var embeddingModel: String = DefaultModels.embedding.modelID

    private let secureStorage: SecureStorage

    private let availableFonts = [
        "SF Mono", "Menlo", "Monaco", "Courier New",
        "JetBrains Mono", "Fira Code", "Source Code Pro",
        "IBM Plex Mono", "Hack", "Cascadia Code",
    ]

    public init(secureStorage: SecureStorage = SecureStorage()) {
        self.secureStorage = secureStorage
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
            .frame(minWidth: 480)
        }
        .frame(width: 720, height: 520)
        .onAppear {
            hasAPIKey = (try? secureStorage.exists(key: SecureStorage.openRouterAPIKey)) ?? false
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

            // Theme grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
                ForEach(TerminusTheme.allThemes) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: selectedThemeID == theme.id,
                        action: { selectedThemeID = theme.id }
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

                VStack(alignment: .leading) {
                    Text("Size: \(Int(fontSize))pt")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(TerminusColors.textSecondary)
                    Slider(value: $fontSize, in: 10...28, step: 1)
                        .frame(width: 150)
                }
            }

            // Font preview
            Text("The quick brown fox jumps over the lazy dog\n$ git commit -m \"fix: resolve login bug\" && git push")
                .font(.custom(fontFamily, size: fontSize))
                .foregroundStyle(TerminusColors.textPrimary)
                .padding(TerminusDesign.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                )

            Divider()

            sectionHeader("Window")

            HStack(spacing: TerminusDesign.spacingLG) {
                VStack(alignment: .leading) {
                    Text("Opacity: \(Int(windowOpacity * 100))%")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(TerminusColors.textSecondary)
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
                            Circle().stroke(Color.white, lineWidth: accentColorHue == hue ? 2 : 0)
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
                .foregroundStyle(TerminusColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            sectionHeader("Environment")

            VStack(alignment: .leading, spacing: 4) {
                Text("TERM = xterm-256color")
                Text("COLORTERM = truecolor")
                Text("TERM_PROGRAM = Terminus")
            }
            .font(.terminusMono(size: 12))
            .foregroundStyle(TerminusColors.textSecondary)
            .padding(TerminusDesign.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                    .fill(Color.white.opacity(0.03))
            )

            sectionHeader("Key Bindings")

            Text("Terminal keybindings follow standard xterm conventions. Special keys are translated to VT100/xterm escape sequences.")
                .font(.terminusUI(size: 12))
                .foregroundStyle(TerminusColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - AI Settings

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            sectionHeader("OpenRouter")

            if hasAPIKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TerminusColors.accentSuccess)
                    Text("API key configured")
                        .foregroundStyle(TerminusColors.textSecondary)

                    Spacer()

                    Button("Remove Key") {
                        try? secureStorage.delete(key: SecureStorage.openRouterAPIKey)
                        hasAPIKey = false
                    }
                    .foregroundStyle(TerminusColors.accentError)
                }
            } else {
                VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
                    Text("Enter your OpenRouter API key to enable AI features.")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(TerminusColors.textSecondary)

                    HStack {
                        SecureField("sk-or-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)

                        Button("Save") {
                            if !apiKey.isEmpty {
                                try? secureStorage.store(
                                    key: SecureStorage.openRouterAPIKey,
                                    value: apiKey
                                )
                                hasAPIKey = true
                                apiKey = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)
                    }
                }
            }

            sectionHeader("Models")

            LabeledContent("Chat Model") {
                TextField("", text: $chatModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }

            LabeledContent("Embedding Model") {
                TextField("", text: $embeddingModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }

            sectionHeader("AI Features")

            Toggle("Enable AI features", isOn: $settings.enableAI)

            Text("AI features include: command explanation, natural language to command, semantic search over history, auto-generated saved command descriptions.")
                .font(.terminusUI(size: 11))
                .foregroundStyle(TerminusColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

            sectionHeader("Tools")
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

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.terminusUI(size: 13, weight: .semibold))
            .foregroundStyle(TerminusColors.textSecondary)
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
                .foregroundStyle(TerminusColors.textPrimary)
            Spacer()
            Text(shortcut)
                .font(.terminusMono(size: 11))
                .foregroundStyle(TerminusColors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }
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
                .foregroundStyle(TerminusColors.textSecondary)
                .padding(.top, 4)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? TerminusColors.accentPrimary : Color.clear, lineWidth: 2)
        )
        .onTapGesture(perform: action)
    }
}
