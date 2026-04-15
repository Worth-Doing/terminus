import SwiftUI
import SharedModels
import SharedUI
import AIService

// MARK: - Command Explanation View

public struct CommandExplanationView: View {
    let explanation: CommandExplanation
    let theme: TerminusTheme
    let onDismiss: () -> Void

    public init(
        explanation: CommandExplanation,
        theme: TerminusTheme,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.explanation = explanation
        self.theme = theme
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TerminusAccent.warning)

                Text("Command Explanation")
                    .font(.terminusUI(size: 12, weight: .semibold))
                    .foregroundStyle(theme.chromeText)

                Spacer()

                // Risk level badge
                riskBadge

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)

            Divider().background(theme.chromeDivider)

            // Command display
            Text("$ \(explanation.command)")
                .font(.terminusMono(size: 12, weight: .medium))
                .foregroundStyle(theme.chromeText)
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, TerminusDesign.spacingSM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.03))

            // Summary
            Text(explanation.summary)
                .font(.terminusUI(size: 12))
                .foregroundStyle(theme.chromeTextSecondary)
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, TerminusDesign.spacingSM)

            // Parts breakdown
            if !explanation.parts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(explanation.parts) { part in
                        HStack(alignment: .top, spacing: TerminusDesign.spacingSM) {
                            Text(part.token)
                                .font(.terminusMono(size: 11, weight: .medium))
                                .foregroundStyle(TerminusAccent.primary)
                                .frame(minWidth: 60, alignment: .leading)

                            Text(part.explanation)
                                .font(.terminusUI(size: 11))
                                .foregroundStyle(theme.chromeTextSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.bottom, TerminusDesign.spacingSM)
            }

            // Tips
            if !explanation.tips.isEmpty {
                Divider().background(theme.chromeDivider)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(explanation.tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: TerminusDesign.spacingSM) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 9))
                                .foregroundStyle(TerminusAccent.warning)
                            Text(tip)
                                .font(.terminusUI(size: 11))
                                .foregroundStyle(theme.chromeTextSecondary)
                        }
                    }
                }
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, TerminusDesign.spacingSM)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .fill(TerminusAccent.warning.opacity(theme.isDark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .stroke(TerminusAccent.warning.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var riskBadge: some View {
        Group {
            switch explanation.riskLevel {
            case "safe":
                Label("Safe", systemImage: "checkmark.shield")
                    .font(.terminusUI(size: 9, weight: .medium))
                    .foregroundStyle(TerminusAccent.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.success.opacity(0.15)))
            case "moderate":
                Label("Moderate", systemImage: "exclamationmark.shield")
                    .font(.terminusUI(size: 9, weight: .medium))
                    .foregroundStyle(TerminusAccent.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.warning.opacity(0.15)))
            case "dangerous":
                Label("Dangerous", systemImage: "exclamationmark.triangle.fill")
                    .font(.terminusUI(size: 9, weight: .medium))
                    .foregroundStyle(TerminusAccent.error)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.error.opacity(0.15)))
            default:
                EmptyView()
            }
        }
    }
}
