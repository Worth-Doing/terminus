import SwiftUI
import SharedModels
import SharedUI

// MARK: - Workflow Runner State

@MainActor
@Observable
public final class WorkflowRunner {
    public var workflow: WorkflowSequence?
    public var currentStepIndex: Int = 0
    public var isRunning: Bool = false
    public var stepResults: [UUID: StepResult] = [:]
    public var error: String?

    public struct StepResult: Sendable {
        public let exitCode: Int32
        public let completed: Bool
    }

    public init() {}

    public func start(_ workflow: WorkflowSequence) {
        self.workflow = workflow
        self.currentStepIndex = 0
        self.isRunning = true
        self.stepResults = [:]
        self.error = nil
    }

    public func recordStepResult(stepID: String, exitCode: Int32) {
        guard let workflow, currentStepIndex < workflow.steps.count else { return }
        let step = workflow.steps[currentStepIndex]
        stepResults[UUID(uuidString: step.id) ?? UUID()] = StepResult(exitCode: exitCode, completed: true)

        if exitCode != 0 && !step.continueOnError {
            isRunning = false
            error = "Step \(currentStepIndex + 1) failed with exit code \(exitCode)"
            return
        }

        currentStepIndex += 1
        if currentStepIndex >= workflow.steps.count {
            isRunning = false
        }
    }

    public func stop() {
        isRunning = false
    }

    public var progress: Double {
        guard let workflow, !workflow.steps.isEmpty else { return 0 }
        return Double(currentStepIndex) / Double(workflow.steps.count)
    }

    public var currentStep: WorkflowStep? {
        guard let workflow, currentStepIndex < workflow.steps.count else { return nil }
        return workflow.steps[currentStepIndex]
    }
}

// MARK: - Workflow List View

public struct WorkflowListView: View {
    let workflows: [WorkflowSequence]
    let theme: TerminusTheme
    let onRun: (WorkflowSequence) -> Void
    let onEdit: (WorkflowSequence) -> Void
    let onDelete: (WorkflowSequence) -> Void
    let onCreate: () -> Void

    public init(
        workflows: [WorkflowSequence],
        theme: TerminusTheme,
        onRun: @escaping (WorkflowSequence) -> Void = { _ in },
        onEdit: @escaping (WorkflowSequence) -> Void = { _ in },
        onDelete: @escaping (WorkflowSequence) -> Void = { _ in },
        onCreate: @escaping () -> Void = {}
    ) {
        self.workflows = workflows
        self.theme = theme
        self.onRun = onRun
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(TerminusAccent.primary)
                Text("Workflows")
                    .font(.terminusUI(size: 13, weight: .semibold))
                    .foregroundStyle(theme.chromeText)
                Spacer()
                Button(action: onCreate) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TerminusAccent.primary)
                }
                .buttonStyle(.plain)
                .help("Create workflow")
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)

            Divider().background(theme.chromeDivider)

            if workflows.isEmpty {
                VStack(spacing: TerminusDesign.spacingSM) {
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Text("No workflows yet")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Text("Create reusable command sequences")
                        .font(.terminusUI(size: 10))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(workflows) { workflow in
                            workflowRow(workflow)
                        }
                    }
                    .padding(.vertical, TerminusDesign.spacingXS)
                }
            }
        }
    }

    @State private var hoveredID: String?

    private func workflowRow(_ workflow: WorkflowSequence) -> some View {
        let isHovered = hoveredID == workflow.id

        return VStack(alignment: .leading, spacing: TerminusDesign.spacingXS) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.name)
                        .font(.terminusUI(size: 12, weight: .medium))
                        .foregroundStyle(theme.chromeText)

                    if let desc = workflow.description {
                        Text(desc)
                            .font(.terminusUI(size: 10))
                            .foregroundStyle(theme.chromeTextTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isHovered {
                    HStack(spacing: 4) {
                        Button { onRun(workflow) } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(TerminusAccent.success)
                        }
                        .buttonStyle(.plain)
                        .help("Run")

                        Button { onEdit(workflow) } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.chromeTextSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit")

                        Button { onDelete(workflow) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(TerminusAccent.error)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                }
            }

            // Step preview
            HStack(spacing: 4) {
                Text("\(workflow.steps.count) steps")
                    .font(.terminusUI(size: 9))
                    .foregroundStyle(theme.chromeTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.chromeHover))

                ForEach(workflow.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.terminusUI(size: 9))
                        .foregroundStyle(TerminusAccent.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(TerminusAccent.primary.opacity(0.1)))
                }
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, TerminusDesign.spacingSM)
        .background(isHovered ? theme.chromeHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? workflow.id : nil }
        .onTapGesture(count: 2) { onRun(workflow) }
    }
}

// MARK: - Workflow Editor Sheet

public struct WorkflowEditorSheet: View {
    @Binding var isPresented: Bool
    let theme: TerminusTheme
    let existingWorkflow: WorkflowSequence?
    let onSave: (WorkflowSequence) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var steps: [WorkflowStep] = []
    @State private var tags: String = ""

    public init(
        isPresented: Binding<Bool>,
        theme: TerminusTheme,
        existingWorkflow: WorkflowSequence? = nil,
        onSave: @escaping (WorkflowSequence) -> Void
    ) {
        self._isPresented = isPresented
        self.theme = theme
        self.existingWorkflow = existingWorkflow
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingWorkflow != nil ? "Edit Workflow" : "New Workflow")
                    .font(.terminusUI(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                Button("Save") { saveWorkflow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || steps.isEmpty)
            }
            .padding(TerminusDesign.spacingMD)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.terminusUI(size: 12, weight: .medium))
                        TextField("e.g., Deploy to production", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.terminusUI(size: 12, weight: .medium))
                        TextField("Optional description", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tags (comma separated)")
                            .font(.terminusUI(size: 12, weight: .medium))
                        TextField("e.g., deploy, git, docker", text: $tags)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Steps
                    HStack {
                        Text("Steps")
                            .font(.terminusUI(size: 13, weight: .semibold))
                        Spacer()
                        Button {
                            steps.append(WorkflowStep(command: ""))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10))
                                Text("Add Step")
                                    .font(.terminusUI(size: 11))
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepEditor(index: index, step: step)
                    }

                    if steps.isEmpty {
                        Text("Add at least one step to create a workflow")
                            .font(.terminusUI(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding(TerminusDesign.spacingMD)
            }
        }
        .frame(width: 520, height: 500)
        .onAppear {
            if let existing = existingWorkflow {
                name = existing.name
                description = existing.description ?? ""
                steps = existing.steps
                tags = existing.tags.joined(separator: ", ")
            }
        }
    }

    private func stepEditor(index: Int, step: WorkflowStep) -> some View {
        HStack(alignment: .top, spacing: TerminusDesign.spacingSM) {
            // Step number
            Text("\(index + 1)")
                .font(.terminusMono(size: 11, weight: .bold))
                .foregroundStyle(TerminusAccent.primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Command", text: Binding(
                    get: { steps[safe: index]?.command ?? "" },
                    set: { if steps.indices.contains(index) { steps[index] = WorkflowStep(id: step.id, command: $0, description: step.description, continueOnError: step.continueOnError, delayAfterMs: step.delayAfterMs) } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.terminusMono(size: 12))

                HStack {
                    Toggle("Continue on error", isOn: Binding(
                        get: { steps[safe: index]?.continueOnError ?? false },
                        set: { if steps.indices.contains(index) { steps[index] = WorkflowStep(id: step.id, command: step.command, description: step.description, continueOnError: $0, delayAfterMs: step.delayAfterMs) } }
                    ))
                    .font(.terminusUI(size: 10))
                    .toggleStyle(.checkbox)
                }
            }

            Button {
                steps.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TerminusAccent.error.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(TerminusDesign.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func saveWorkflow() {
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let workflow = WorkflowSequence(
            id: existingWorkflow?.id ?? UUID().uuidString,
            name: name,
            description: description.isEmpty ? nil : description,
            steps: steps.filter { !$0.command.isEmpty },
            tags: tagList,
            createdAt: existingWorkflow?.createdAt ?? Date()
        )
        onSave(workflow)
        isPresented = false
    }
}

// MARK: - Workflow Progress View

public struct WorkflowProgressView: View {
    let runner: WorkflowRunner
    let theme: TerminusTheme
    let onStop: () -> Void

    public init(runner: WorkflowRunner, theme: TerminusTheme, onStop: @escaping () -> Void = {}) {
        self.runner = runner
        self.theme = theme
        self.onStop = onStop
    }

    public var body: some View {
        if let workflow = runner.workflow, runner.isRunning {
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TerminusAccent.primary)

                Text(workflow.name)
                    .font(.terminusUI(size: 11, weight: .medium))
                    .foregroundStyle(theme.chromeText)

                ProgressView(value: runner.progress)
                    .frame(width: 80)
                    .tint(TerminusAccent.primary)

                Text("Step \(runner.currentStepIndex + 1)/\(workflow.steps.count)")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(TerminusAccent.error)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 4)
            .background(TerminusAccent.primary.opacity(0.06))
            .overlay(alignment: .bottom) {
                Divider().background(theme.chromeDivider)
            }
        }

        if let error = runner.error {
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TerminusAccent.error)
                Text(error)
                    .font(.terminusUI(size: 11))
                    .foregroundStyle(TerminusAccent.error)
                Spacer()
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 4)
            .background(TerminusAccent.error.opacity(0.08))
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
