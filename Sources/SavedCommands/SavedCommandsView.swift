import SwiftUI
import SharedModels
import SharedUI

// MARK: - Saved Commands Sidebar

public struct SavedCommandsSidebar: View {
    let commands: [SavedCommand]
    let theme: TerminusTheme
    let onSelect: (SavedCommand) -> Void
    let onDelete: (SavedCommand) -> Void
    let onAdd: () -> Void

    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil

    public init(
        commands: [SavedCommand],
        theme: TerminusTheme,
        onSelect: @escaping (SavedCommand) -> Void,
        onDelete: @escaping (SavedCommand) -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.commands = commands
        self.theme = theme
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onAdd = onAdd
    }

    private var filteredCommands: [SavedCommand] {
        var result = commands

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.commandTemplate.lowercased().contains(query) ||
                ($0.description?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    private var allTags: [String] {
        Array(Set(commands.flatMap(\.tags))).sorted()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Saved Commands")
                    .font(.terminusUI(size: 13, weight: .semibold))
                    .foregroundStyle(theme.chromeText)

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)

            // Search
            HStack(spacing: TerminusDesign.spacingXS) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.chromeTextTertiary)

                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.terminusUI(size: 12))
            }
            .padding(.horizontal, TerminusDesign.spacingSM)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                    .fill(theme.chromeHover)
            )
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.bottom, TerminusDesign.spacingSM)

            // Tags
            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        TagChip(
                            label: "All",
                            isSelected: selectedTag == nil,
                            theme: theme,
                            action: { selectedTag = nil }
                        )

                        ForEach(allTags, id: \.self) { tag in
                            TagChip(
                                label: tag,
                                isSelected: selectedTag == tag,
                                theme: theme,
                                action: { selectedTag = selectedTag == tag ? nil : tag }
                            )
                        }
                    }
                    .padding(.horizontal, TerminusDesign.spacingMD)
                }
                .padding(.bottom, TerminusDesign.spacingSM)
            }

            Divider()
                .background(theme.chromeDivider)

            // Command list
            if filteredCommands.isEmpty {
                VStack(spacing: TerminusDesign.spacingSM) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Text(commands.isEmpty ? "No saved commands yet" : "No matches")
                        .font(.terminusUI(size: 13))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredCommands) { command in
                            SavedCommandRow(
                                command: command,
                                theme: theme,
                                onSelect: { onSelect(command) },
                                onDelete: { onDelete(command) }
                            )
                        }
                    }
                    .padding(.vertical, TerminusDesign.spacingXS)
                }
            }
        }
        .frame(width: TerminusDesign.sidebarWidth)
    }
}

// MARK: - Saved Command Row

struct SavedCommandRow: View {
    let command: SavedCommand
    let theme: TerminusTheme
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(command.name)
                    .font(.terminusUI(size: 13, weight: .medium))
                    .foregroundStyle(theme.chromeText)
                    .lineLimit(1)

                Spacer()

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.chromeTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(command.commandTemplate)
                .font(.terminusMono(size: 11))
                .foregroundStyle(TerminusAccent.primary.opacity(0.8))
                .lineLimit(2)

            if !command.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(command.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.terminusUI(size: 9, weight: .medium))
                            .foregroundStyle(theme.chromeTextTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(theme.chromeHover)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, TerminusDesign.spacingSM)
        .background(isHovering ? theme.chromeHover : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let label: String
    let isSelected: Bool
    let theme: TerminusTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.terminusUI(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected ? TerminusAccent.primary : theme.chromeTextSecondary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        isSelected
                            ? TerminusAccent.primary.opacity(0.15)
                            : theme.chromeHover
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save Command Sheet

public struct SaveCommandSheet: View {
    @Binding var isPresented: Bool
    let initialCommand: String
    let theme: TerminusTheme
    let onSave: (SavedCommand) -> Void

    @State private var name: String = ""
    @State private var commandTemplate: String
    @State private var description: String = ""
    @State private var tagsInput: String = ""

    public init(
        isPresented: Binding<Bool>,
        initialCommand: String,
        theme: TerminusTheme,
        onSave: @escaping (SavedCommand) -> Void
    ) {
        self._isPresented = isPresented
        self.initialCommand = initialCommand
        self.theme = theme
        self.onSave = onSave
        self._commandTemplate = State(initialValue: initialCommand)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingMD) {
            Text("Save Command")
                .font(.terminusUI(size: 18, weight: .semibold))
                .foregroundStyle(theme.chromeText)

            VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
                Text("Name")
                    .font(.terminusUI(size: 12, weight: .medium))
                    .foregroundStyle(theme.chromeTextSecondary)
                TextField("e.g., Deploy to staging", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
                Text("Command")
                    .font(.terminusUI(size: 12, weight: .medium))
                    .foregroundStyle(theme.chromeTextSecondary)
                TextField("Command template", text: $commandTemplate)
                    .font(.terminusMono(size: 13))
                    .textFieldStyle(.roundedBorder)

                Text("Use {{param}} for parameters")
                    .font(.terminusUI(size: 11))
                    .foregroundStyle(theme.chromeTextTertiary)
            }

            VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
                Text("Description (optional)")
                    .font(.terminusUI(size: 12, weight: .medium))
                    .foregroundStyle(theme.chromeTextSecondary)
                TextField("What does this command do?", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: TerminusDesign.spacingSM) {
                Text("Tags (comma-separated)")
                    .font(.terminusUI(size: 12, weight: .medium))
                    .foregroundStyle(theme.chromeTextSecondary)
                TextField("e.g., git, deploy, docker", text: $tagsInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(TerminusAccent.primary)
                .disabled(name.isEmpty || commandTemplate.isEmpty)
            }
        }
        .padding(TerminusDesign.spacingXL)
        .frame(width: 450)
        .background(theme.chromeBackground)
    }

    private func save() {
        let tags = tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let paramNames = parseParameters(from: commandTemplate)
        let params = paramNames.map { ParameterDefinition(name: $0) }

        let command = SavedCommand(
            name: name,
            commandTemplate: commandTemplate,
            description: description.isEmpty ? nil : description,
            tags: tags,
            parameters: params
        )

        onSave(command)
        isPresented = false
    }

    private func parseParameters(from template: String) -> [String] {
        var params: [String] = []
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsString = template as NSString
        let results = regex.matches(in: template, range: NSRange(location: 0, length: nsString.length))

        for result in results {
            if result.numberOfRanges > 1 {
                let paramName = nsString.substring(with: result.range(at: 1))
                if !params.contains(paramName) {
                    params.append(paramName)
                }
            }
        }

        return params
    }
}
