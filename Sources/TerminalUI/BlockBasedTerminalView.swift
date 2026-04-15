import SwiftUI
import SharedModels
import SharedUI

// MARK: - Block Manager

@MainActor
@Observable
public final class BlockManager {
    public var blocks: [CommandBlock] = []
    public var activeBlockID: UUID?

    public init() {}

    public func startBlock(input: String, directory: String, type: CommandBlock.BlockType = .standard) -> UUID {
        let block = CommandBlock(
            input: input,
            workingDirectory: directory,
            blockType: type
        )
        blocks.append(block)
        activeBlockID = block.id
        return block.id
    }

    public func appendOutput(_ text: String, to blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].output += text
    }

    public func finishBlock(_ blockID: UUID, exitCode: Int32) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].exitCode = exitCode
        blocks[index].finishedAt = Date()
        if blockID == activeBlockID {
            activeBlockID = nil
        }
    }

    public func addAIBlock(input: String, explanation: String, commands: [GeneratedCommand], directory: String) -> UUID {
        let block = CommandBlock(
            input: input,
            output: explanation,
            workingDirectory: directory,
            blockType: .aiGenerated
        )
        blocks.append(block)
        return block.id
    }

    public func toggleCollapse(_ blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].isCollapsed.toggle()
    }

    public func removeBlock(_ blockID: UUID) {
        blocks.removeAll { $0.id == blockID }
    }

    public func clearAll() {
        blocks.removeAll()
        activeBlockID = nil
    }

    public var recentBlocks: [CommandBlock] {
        Array(blocks.suffix(100))
    }
}

// MARK: - Command Block View

public struct CommandBlockView: View {
    let block: CommandBlock
    let theme: TerminusTheme
    let onRerun: () -> Void
    let onCopy: () -> Void
    let onToggleCollapse: () -> Void

    @State private var isHovering = false

    public init(
        block: CommandBlock,
        theme: TerminusTheme,
        onRerun: @escaping () -> Void = {},
        onCopy: @escaping () -> Void = {},
        onToggleCollapse: @escaping () -> Void = {}
    ) {
        self.block = block
        self.theme = theme
        self.onRerun = onRerun
        self.onCopy = onCopy
        self.onToggleCollapse = onToggleCollapse
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            blockHeader

            // Content
            if !block.isCollapsed {
                if !block.output.isEmpty {
                    blockOutput
                }
            }
        }
        .background(blockBackground)
        .clipShape(RoundedRectangle(cornerRadius: TerminusDesign.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .stroke(blockBorderColor, lineWidth: 0.5)
        )
        .onHover { isHovering = $0 }
    }

    // MARK: - Header

    private var blockHeader: some View {
        HStack(spacing: TerminusDesign.spacingSM) {
            // Status indicator
            statusIndicator

            // Command text
            Text(block.input)
                .font(.terminusMono(size: 13, weight: .medium))
                .foregroundStyle(theme.chromeText)
                .lineLimit(block.isCollapsed ? 1 : 3)

            Spacer()

            // Duration
            if let duration = block.duration {
                Text(formatDuration(duration))
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)
            }

            // Action buttons (show on hover)
            if isHovering {
                HStack(spacing: 4) {
                    blockActionButton(icon: "doc.on.doc", action: onCopy, tooltip: "Copy")
                    blockActionButton(icon: "arrow.clockwise", action: onRerun, tooltip: "Re-run")
                    blockActionButton(
                        icon: block.isCollapsed ? "chevron.down" : "chevron.up",
                        action: onToggleCollapse,
                        tooltip: block.isCollapsed ? "Expand" : "Collapse"
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, TerminusDesign.spacingSM)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onToggleCollapse() }
    }

    // MARK: - Output

    private var blockOutput: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .background(theme.chromeDivider)

            ScrollView(.vertical, showsIndicators: false) {
                Text(block.output)
                    .font(.terminusMono(size: 12))
                    .foregroundStyle(
                        block.blockType == .error
                            ? TerminusAccent.error
                            : theme.chromeTextSecondary
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TerminusDesign.spacingMD)
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Visual Helpers

    private var statusIndicator: some View {
        Group {
            if block.isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else if let exitCode = block.exitCode {
                Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(exitCode == 0 ? TerminusAccent.success : TerminusAccent.error)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.chromeTextTertiary)
            }
        }
    }

    private var blockBackground: some View {
        RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
            .fill(
                block.blockType == .aiGenerated
                    ? TerminusAccent.primary.opacity(0.05)
                    : (isHovering ? theme.chromeHover : Color.clear)
            )
    }

    private var blockBorderColor: Color {
        switch block.blockType {
        case .aiGenerated:
            return TerminusAccent.primary.opacity(0.3)
        case .error:
            return TerminusAccent.error.opacity(0.3)
        default:
            return isHovering ? theme.chromeBorder : theme.chromeDivider.opacity(0.5)
        }
    }

    private func blockActionButton(icon: String, action: @escaping () -> Void, tooltip: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(theme.chromeTextSecondary)
                .frame(width: 22, height: 22)
                .background(theme.chromeHover)
                .clipShape(RoundedRectangle(cornerRadius: TerminusDesign.radiusSM))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "\(Int(interval * 1000))ms"
        } else if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - AI Command Block View

public struct AICommandBlockView: View {
    let response: NLCommandResponse
    let theme: TerminusTheme
    let onRun: (String) -> Void
    let onEdit: (String) -> Void
    let onCopy: (String) -> Void
    let onReject: () -> Void

    @State private var editingCommand: String?
    @State private var editText: String = ""
    @State private var showAlternatives: Bool = false

    public init(
        response: NLCommandResponse,
        theme: TerminusTheme,
        onRun: @escaping (String) -> Void = { _ in },
        onEdit: @escaping (String) -> Void = { _ in },
        onCopy: @escaping (String) -> Void = { _ in },
        onReject: @escaping () -> Void = {}
    ) {
        self.response = response
        self.theme = theme
        self.onRun = onRun
        self.onEdit = onEdit
        self.onCopy = onCopy
        self.onReject = onReject
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // AI Label header
            aiHeader

            Divider().background(TerminusAccent.primary.opacity(0.2))

            // Explanation
            Text(response.explanation)
                .font(.terminusUI(size: 12))
                .foregroundStyle(theme.chromeTextSecondary)
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, TerminusDesign.spacingSM)

            // Commands
            ForEach(response.commands) { cmd in
                commandRow(cmd)
            }

            // Alternatives toggle
            if !response.alternatives.isEmpty {
                alternativesSection
            }

            // Reject button
            HStack {
                Spacer()
                Button(action: onReject) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                        Text("Dismiss")
                            .font(.terminusUI(size: 11))
                    }
                    .foregroundStyle(theme.chromeTextTertiary)
                    .padding(.horizontal, TerminusDesign.spacingSM)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.bottom, TerminusDesign.spacingSM)
        }
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .fill(TerminusAccent.primary.opacity(theme.isDark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusMD)
                .stroke(
                    LinearGradient(
                        colors: [
                            TerminusAccent.primary.opacity(0.4),
                            TerminusAccent.primary.opacity(0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - AI Header

    private var aiHeader: some View {
        HStack(spacing: TerminusDesign.spacingSM) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(TerminusAccent.primary)

            Text("AI Suggestion")
                .font(.terminusUI(size: 12, weight: .semibold))
                .foregroundStyle(TerminusAccent.primary)

            if response.isMultiStep {
                Text("\(response.commands.count) steps")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(TerminusAccent.primary.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(TerminusAccent.primary.opacity(0.15))
                    )
            }

            Spacer()

            if !response.model.isEmpty {
                Text(response.model.split(separator: "/").last.map(String.init) ?? response.model)
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, TerminusDesign.spacingSM)
    }

    // MARK: - Command Row

    private func commandRow(_ cmd: GeneratedCommand) -> some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
            // Step indicator
            if let step = cmd.stepNumber {
                Text("Step \(step)")
                    .font(.terminusUI(size: 10, weight: .medium))
                    .foregroundStyle(theme.chromeTextTertiary)
                    .padding(.horizontal, TerminusDesign.spacingMD)
            }

            // Command
            HStack(spacing: 0) {
                if editingCommand == cmd.id.uuidString {
                    TextField("Edit command...", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.terminusMono(size: 13))
                        .foregroundStyle(theme.chromeText)
                        .onSubmit {
                            onRun(editText)
                            editingCommand = nil
                        }
                } else {
                    Text("$ ")
                        .font(.terminusMono(size: 13, weight: .bold))
                        .foregroundStyle(TerminusAccent.primary)

                    Text(cmd.command)
                        .font(.terminusMono(size: 13))
                        .foregroundStyle(theme.chromeText)
                        .textSelection(.enabled)
                }

                Spacer()

                // Safety badge
                safetyBadge(cmd.safetyLevel)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)
            .background(theme.isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.03))

            // Warnings
            ForEach(cmd.warnings) { warning in
                warningRow(warning)
            }

            // Explanation
            if let explanation = cmd.explanation {
                Text(explanation)
                    .font(.terminusUI(size: 11))
                    .foregroundStyle(theme.chromeTextTertiary)
                    .padding(.horizontal, TerminusDesign.spacingMD)
            }

            // Action buttons
            HStack(spacing: TerminusDesign.spacingSM) {
                // Run button
                Button {
                    if cmd.safetyLevel >= .dangerous {
                        // For dangerous commands, we still allow but the UI has shown warnings
                    }
                    onRun(cmd.command)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Run")
                            .font(.terminusUI(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, TerminusDesign.spacingMD)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            cmd.safetyLevel >= .dangerous
                                ? TerminusAccent.warning
                                : TerminusAccent.primary
                        )
                    )
                }
                .buttonStyle(.plain)

                // Edit button
                Button {
                    editText = cmd.command
                    editingCommand = cmd.id.uuidString
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                        Text("Edit")
                            .font(.terminusUI(size: 11))
                    }
                    .foregroundStyle(theme.chromeTextSecondary)
                    .padding(.horizontal, TerminusDesign.spacingSM)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().stroke(theme.chromeBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                // Copy button
                Button {
                    onCopy(cmd.command)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(.terminusUI(size: 11))
                    }
                    .foregroundStyle(theme.chromeTextSecondary)
                    .padding(.horizontal, TerminusDesign.spacingSM)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().stroke(theme.chromeBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.bottom, TerminusDesign.spacingSM)
        }
    }

    // MARK: - Safety Badge

    private func safetyBadge(_ level: CommandSafetyLevel) -> some View {
        Group {
            switch level {
            case .safe:
                EmptyView()
            case .moderate:
                Label("Modifies files", systemImage: "pencil.circle")
                    .font(.terminusUI(size: 9))
                    .foregroundStyle(TerminusAccent.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.warning.opacity(0.15)))
            case .dangerous:
                Label("Destructive", systemImage: "exclamationmark.triangle.fill")
                    .font(.terminusUI(size: 9, weight: .medium))
                    .foregroundStyle(TerminusAccent.error)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.error.opacity(0.15)))
            case .critical:
                Label("CRITICAL", systemImage: "exclamationmark.octagon.fill")
                    .font(.terminusUI(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TerminusAccent.error))
            }
        }
    }

    // MARK: - Warning Row

    private func warningRow(_ warning: SafetyWarning) -> some View {
        HStack(alignment: .top, spacing: TerminusDesign.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(
                    warning.level >= .dangerous ? TerminusAccent.error : TerminusAccent.warning
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.message)
                    .font(.terminusUI(size: 11, weight: .medium))
                    .foregroundStyle(
                        warning.level >= .dangerous ? TerminusAccent.error : TerminusAccent.warning
                    )

                if let detail = warning.detail {
                    Text(detail)
                        .font(.terminusUI(size: 10))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, TerminusDesign.spacingXS)
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                .fill(
                    warning.level >= .dangerous
                        ? TerminusAccent.error.opacity(0.08)
                        : TerminusAccent.warning.opacity(0.08)
                )
        )
        .padding(.horizontal, TerminusDesign.spacingSM)
    }

    // MARK: - Alternatives

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(TerminusDesign.springSnappy) {
                    showAlternatives.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showAlternatives ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("\(response.alternatives.count) alternative\(response.alternatives.count == 1 ? "" : "s")")
                        .font(.terminusUI(size: 11))
                }
                .foregroundStyle(theme.chromeTextTertiary)
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, TerminusDesign.spacingXS)
            }
            .buttonStyle(.plain)

            if showAlternatives {
                ForEach(response.alternatives) { alt in
                    commandRow(alt)
                }
            }
        }
    }
}
