import SwiftUI
import SharedModels
import SharedUI

// MARK: - History Filter

public enum HistoryFilter: String, CaseIterable, Sendable {
    case all = "All"
    case successful = "Successful"
    case failed = "Failed"
    case favorites = "Favorites"
}

// MARK: - History Panel View

public struct HistoryPanelView: View {
    let entries: [CommandEntry]
    let favorites: Set<String>
    let theme: TerminusTheme
    let onSelect: (String) -> Void
    let onRerun: (String) -> Void
    let onToggleFavorite: (String) -> Void
    let onSearch: (String) -> Void

    @State private var searchText: String = ""
    @State private var filter: HistoryFilter = .all
    @State private var groupBySession: Bool = false
    @State private var selectedEntryID: String?
    @State private var editingCommand: String?
    @State private var editText: String = ""

    public init(
        entries: [CommandEntry],
        favorites: Set<String> = [],
        theme: TerminusTheme,
        onSelect: @escaping (String) -> Void = { _ in },
        onRerun: @escaping (String) -> Void = { _ in },
        onToggleFavorite: @escaping (String) -> Void = { _ in },
        onSearch: @escaping (String) -> Void = { _ in }
    ) {
        self.entries = entries
        self.favorites = favorites
        self.theme = theme
        self.onSelect = onSelect
        self.onRerun = onRerun
        self.onToggleFavorite = onToggleFavorite
        self.onSearch = onSearch
    }

    private var filteredEntries: [CommandEntry] {
        var result = entries

        // Apply text filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(query) ||
                $0.workingDirectory.lowercased().contains(query)
            }
        }

        // Apply status filter
        switch filter {
        case .all: break
        case .successful:
            result = result.filter { $0.exitCode == 0 }
        case .failed:
            result = result.filter { ($0.exitCode ?? 0) != 0 }
        case .favorites:
            result = result.filter { favorites.contains($0.command) }
        }

        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(TerminusAccent.primary)
                Text("History")
                    .font(.terminusUI(size: 13, weight: .semibold))
                    .foregroundStyle(theme.chromeText)
                Spacer()

                // Group toggle
                Button {
                    groupBySession.toggle()
                } label: {
                    Image(systemName: groupBySession ? "rectangle.stack.fill" : "rectangle.stack")
                        .font(.system(size: 11))
                        .foregroundStyle(groupBySession ? TerminusAccent.primary : theme.chromeTextTertiary)
                }
                .buttonStyle(.plain)
                .help("Group by session")
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)

            // Search bar
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.chromeTextTertiary)

                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.terminusUI(size: 12))
                    .foregroundStyle(theme.chromeText)
                    .onChange(of: searchText) { _, newValue in
                        onSearch(newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.chromeTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 6)
            .background(theme.isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.03))

            // Filter pills
            HStack(spacing: 4) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    filterPill(f)
                }
                Spacer()
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 6)

            Divider().background(theme.chromeDivider)

            // History list
            if filteredEntries.isEmpty {
                VStack(spacing: TerminusDesign.spacingSM) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Text(searchText.isEmpty ? "No commands yet" : "No matching commands")
                        .font(.terminusUI(size: 12))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredEntries, id: \.id) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.vertical, TerminusDesign.spacingXS)
                }
            }

            // Stats footer
            Divider().background(theme.chromeDivider)
            HStack {
                Text("\(filteredEntries.count) commands")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)
                Spacer()
                Text("\(favorites.count) favorites")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 4)
        }
        .frame(width: TerminusDesign.sidebarWidth + 20)
    }

    // MARK: - History Row

    private func historyRow(_ entry: CommandEntry) -> some View {
        let isSelected = selectedEntryID == entry.id
        let isFav = favorites.contains(entry.command)

        return HStack(alignment: .top, spacing: TerminusDesign.spacingSM) {
            // Status icon
            Group {
                if let code = entry.exitCode {
                    Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(code == 0 ? TerminusAccent.success : TerminusAccent.error)
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
            }
            .frame(width: 14)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                // Command text
                if editingCommand == entry.id {
                    TextField("Edit command...", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.terminusMono(size: 11))
                        .foregroundStyle(theme.chromeText)
                        .onSubmit {
                            onRerun(editText)
                            editingCommand = nil
                        }
                } else {
                    Text(entry.command)
                        .font(.terminusMono(size: 11))
                        .foregroundStyle(theme.chromeText)
                        .lineLimit(isSelected ? 5 : 2)
                }

                // Metadata
                HStack(spacing: TerminusDesign.spacingSM) {
                    Text(shortenPath(entry.workingDirectory))
                        .font(.terminusUI(size: 9))
                        .foregroundStyle(theme.chromeTextTertiary)
                        .lineLimit(1)

                    if let duration = entry.durationMs {
                        Text("\(duration)ms")
                            .font(.terminusUI(size: 9))
                            .foregroundStyle(theme.chromeTextTertiary)
                    }

                    Text(timeAgo(entry.startedAt))
                        .font(.terminusUI(size: 9))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
            }

            Spacer(minLength: 4)

            // Actions
            if isSelected {
                VStack(spacing: 2) {
                    // Favorite toggle
                    Button {
                        onToggleFavorite(entry.command)
                    } label: {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(isFav ? TerminusAccent.warning : theme.chromeTextTertiary)
                    }
                    .buttonStyle(.plain)

                    // Re-run
                    Button {
                        onRerun(entry.command)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(TerminusAccent.primary)
                    }
                    .buttonStyle(.plain)

                    // Edit & run
                    Button {
                        editText = entry.command
                        editingCommand = entry.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.chromeTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, 5)
        .background(isSelected ? TerminusAccent.primary.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(TerminusDesign.springSnappy) {
                selectedEntryID = isSelected ? nil : entry.id
            }
        }
        .onTapGesture(count: 2) {
            onSelect(entry.command)
        }
    }

    // MARK: - Filter Pill

    private func filterPill(_ f: HistoryFilter) -> some View {
        Button {
            withAnimation(TerminusDesign.springSnappy) {
                filter = f
            }
        } label: {
            Text(f.rawValue)
                .font(.terminusUI(size: 10, weight: filter == f ? .semibold : .regular))
                .foregroundStyle(filter == f ? .white : theme.chromeTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        filter == f ? TerminusAccent.primary : theme.chromeHover
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}
