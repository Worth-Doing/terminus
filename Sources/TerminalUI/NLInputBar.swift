import SwiftUI
import SharedModels
import SharedUI

// MARK: - Input Mode

public enum InputMode: String, Sendable {
    case command = "Command"
    case naturalLanguage = "AI"
}

// MARK: - NL Input Bar

public struct NLInputBar: View {
    @Binding var text: String
    let theme: TerminusTheme
    let isAIAvailable: Bool
    let isProcessing: Bool
    let currentModel: String
    let suggestions: [Prediction]
    let onSubmit: (String, InputIntent) -> Void
    let onCancel: () -> Void

    @State private var mode: InputMode = .naturalLanguage
    @State private var selectedSuggestionIndex: Int = -1
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        theme: TerminusTheme,
        isAIAvailable: Bool = false,
        isProcessing: Bool = false,
        currentModel: String = "",
        suggestions: [Prediction] = [],
        onSubmit: @escaping (String, InputIntent) -> Void = { _, _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self._text = text
        self.theme = theme
        self.isAIAvailable = isAIAvailable
        self.isProcessing = isProcessing
        self.currentModel = currentModel
        self.suggestions = suggestions
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Inline suggestions dropdown
            if !suggestions.isEmpty && !text.isEmpty && mode == .command {
                suggestionsView
            }

            // Input bar
            HStack(spacing: TerminusDesign.spacingSM) {
                // Mode toggle button
                modeToggle

                // Text input
                TextField(placeholderText, text: $text)
                    .textFieldStyle(.plain)
                    .font(.terminusMono(size: 13))
                    .foregroundStyle(theme.chromeText)
                    .focused($isFocused)
                    .onSubmit {
                        submitCurrent()
                    }

                // Right side action
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                        Text("Thinking...")
                            .font(.terminusUI(size: 11))
                            .foregroundStyle(theme.chromeTextTertiary)
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.chromeTextTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .fixedSize()
                } else if !text.isEmpty {
                    submitButton
                        .fixedSize()
                }

                // Keyboard hint
                if !isProcessing && text.isEmpty {
                    HStack(spacing: 4) {
                        Text("Enter")
                            .font(.terminusUI(size: 9, weight: .medium))
                            .foregroundStyle(theme.chromeTextTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.chromeHover)
                            )
                        Text("to \(mode == .naturalLanguage ? "ask AI" : "run")")
                            .font(.terminusUI(size: 9))
                            .foregroundStyle(theme.chromeTextTertiary)
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 8)
        }
        .background(
            theme.isDark
                ? Color.black.opacity(0.3)
                : Color.white.opacity(0.5)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.chromeDivider)
                .frame(height: 0.5)
        }
        .onAppear {
            isFocused = true
            // Default to AI mode if available, command mode otherwise
            mode = isAIAvailable ? .naturalLanguage : .command
        }
        .onKeyPress(.escape) {
            if isProcessing {
                onCancel()
            } else if !text.isEmpty {
                text = ""
            }
            return .handled
        }
        .onKeyPress(.tab) {
            // Tab toggles mode
            if isAIAvailable {
                withAnimation(TerminusDesign.springSnappy) {
                    mode = mode == .command ? .naturalLanguage : .command
                }
            }
            return .handled
        }
    }

    // MARK: - Placeholder

    private var placeholderText: String {
        switch mode {
        case .command:
            return "Type a shell command..."
        case .naturalLanguage:
            return "Ask in natural language... (e.g. \"find large files here\")"
        }
    }

    // MARK: - Submit

    private func submitCurrent() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let intent: InputIntent = mode == .naturalLanguage ? .naturalLanguage : .rawCommand
        onSubmit(trimmed, intent)
        text = ""
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        Button {
            if isAIAvailable {
                withAnimation(TerminusDesign.springSnappy) {
                    mode = mode == .command ? .naturalLanguage : .command
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode == .naturalLanguage ? "sparkles" : "terminal")
                    .font(.system(size: 10))

                Text(mode == .naturalLanguage ? "AI" : "$")
                    .font(.terminusMono(size: 11, weight: .bold))
            }
            .foregroundStyle(
                mode == .naturalLanguage ? TerminusAccent.primary : theme.chromeText
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                    .fill(
                        mode == .naturalLanguage
                            ? TerminusAccent.primary.opacity(0.15)
                            : theme.chromeHover
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                    .stroke(
                        mode == .naturalLanguage
                            ? TerminusAccent.primary.opacity(0.3)
                            : theme.chromeBorder,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isAIAvailable ? "Toggle mode (Tab)" : "AI requires OpenRouter API key")
        .fixedSize()
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            submitCurrent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode == .naturalLanguage ? "sparkles" : "play.fill")
                    .font(.system(size: 10))
                Text(mode == .naturalLanguage ? "Ask AI" : "Run")
                    .font(.terminusUI(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    mode == .naturalLanguage
                        ? TerminusAccent.primary
                        : TerminusAccent.success
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.prefix(6).enumerated()), id: \.element.id) { index, prediction in
                HStack(spacing: TerminusDesign.spacingSM) {
                    Image(systemName: iconForSource(prediction.source))
                        .font(.system(size: 10))
                        .foregroundStyle(colorForSource(prediction.source))
                        .frame(width: 16)

                    highlightedCommand(prediction.command, prefix: text)

                    Spacer()

                    Text(String(format: "%.0f%%", prediction.score * 100))
                        .font(.terminusUI(size: 9))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, 5)
                .background(
                    index == selectedSuggestionIndex
                        ? TerminusAccent.primary.opacity(0.12)
                        : Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    text = prediction.command
                    onSubmit(prediction.command, .rawCommand)
                    text = ""
                }
            }
        }
        .padding(.vertical, TerminusDesign.spacingXS)
        .background(theme.chromeBackground)
        .overlay(alignment: .bottom) {
            Divider().background(theme.chromeDivider)
        }
    }

    // MARK: - Helpers

    private func iconForSource(_ source: PredictionSource) -> String {
        switch source {
        case .frequencyHistory: "clock"
        case .ngramSequence: "arrow.right.circle"
        case .directoryContext: "folder"
        case .savedCommand: "bookmark"
        case .aiSuggestion: "sparkles"
        }
    }

    private func colorForSource(_ source: PredictionSource) -> Color {
        switch source {
        case .frequencyHistory: theme.chromeTextTertiary
        case .ngramSequence: TerminusAccent.primary
        case .directoryContext: TerminusAccent.warning
        case .savedCommand: TerminusAccent.success
        case .aiSuggestion: TerminusAccent.primary
        }
    }

    @ViewBuilder
    private func highlightedCommand(_ command: String, prefix: String) -> some View {
        let lowCmd = command.lowercased()
        let lowPrefix = prefix.lowercased()

        if let range = lowCmd.range(of: lowPrefix) {
            let before = String(command[command.startIndex..<range.lowerBound])
            let match = String(command[range])
            let after = String(command[range.upperBound...])

            HStack(spacing: 0) {
                if !before.isEmpty {
                    Text(before)
                        .font(.terminusMono(size: 12))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
                Text(match)
                    .font(.terminusMono(size: 12, weight: .bold))
                    .foregroundStyle(theme.chromeText)
                if !after.isEmpty {
                    Text(after)
                        .font(.terminusMono(size: 12))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
            }
        } else {
            HStack(spacing: 0) {
                Text(command)
                    .font(.terminusMono(size: 12))
                    .foregroundStyle(theme.chromeTextSecondary)
            }
        }
    }
}
