import SwiftUI

// MARK: - Command Palette Item

public struct CommandPaletteItem: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let category: Category
    public let action: () -> Void

    public enum Category: String, CaseIterable {
        case action = "Actions"
        case savedCommand = "Saved Commands"
        case history = "History"
        case setting = "Settings"
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        category: Category = .action,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.action = action
    }
}

// MARK: - Command Palette View

public struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let items: [CommandPaletteItem]
    let theme: TerminusTheme

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    public init(isPresented: Binding<Bool>, items: [CommandPaletteItem], theme: TerminusTheme) {
        self._isPresented = isPresented
        self.items = items
        self.theme = theme
    }

    private var filteredItems: [CommandPaletteItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter {
            $0.title.lowercased().contains(q) ||
            ($0.subtitle?.lowercased().contains(q) ?? false)
        }
    }

    private var groupedItems: [(CommandPaletteItem.Category, [CommandPaletteItem])] {
        let groups = Dictionary(grouping: filteredItems, by: \.category)
        return CommandPaletteItem.Category.allCases.compactMap { category in
            guard let items = groups[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.chromeTextTertiary)

                TextField("Type a command...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.terminusUI(size: 15))
                    .foregroundStyle(theme.chromeText)
                    .focused($isSearchFocused)
                    .onSubmit { executeSelected() }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.chromeTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingMD)

            Divider()
                .background(theme.chromeDivider)

            // Results
            if filteredItems.isEmpty {
                VStack(spacing: TerminusDesign.spacingSM) {
                    Spacer()
                    Text("No results")
                        .font(.terminusUI(size: 14))
                        .foregroundStyle(theme.chromeTextTertiary)
                    Spacer()
                }
                .frame(height: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            var globalIndex = 0
                            ForEach(groupedItems, id: \.0) { category, groupItems in
                                Text(category.rawValue)
                                    .font(.terminusUI(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.chromeTextTertiary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, TerminusDesign.spacingMD)
                                    .padding(.top, TerminusDesign.spacingSM)
                                    .padding(.bottom, 4)

                                ForEach(groupItems) { item in
                                    let currentIndex = globalIndex
                                    let _ = (globalIndex += 1)

                                    CommandPaletteRow(
                                        item: item,
                                        isSelected: currentIndex == selectedIndex,
                                        theme: theme
                                    )
                                    .id(item.id)
                                    .onTapGesture {
                                        item.action()
                                        isPresented = false
                                    }
                                }
                            }
                        }
                        .padding(.vertical, TerminusDesign.spacingXS)
                    }
                    .frame(maxHeight: 350)
                    .onChange(of: selectedIndex) { _, newValue in
                        let allItems = filteredItems
                        if newValue < allItems.count {
                            proxy.scrollTo(allItems[newValue].id, anchor: .center)
                        }
                    }
                }
            }

            // Footer hints
            Divider()
                .background(theme.chromeDivider)

            HStack(spacing: TerminusDesign.spacingMD) {
                keyHint("Return", label: "run")
                keyHint("Up/Down", label: "navigate")
                keyHint("Esc", label: "close")
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, 6)
        }
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusLG)
                .fill(theme.chromeBackground)
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.2), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TerminusDesign.radiusLG)
                .stroke(theme.chromeBorder, lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredItems.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func executeSelected() {
        let items = filteredItems
        guard selectedIndex < items.count else { return }
        items[selectedIndex].action()
        isPresented = false
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.terminusUI(size: 10, weight: .medium))
                .foregroundStyle(theme.chromeTextTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.chromeHover)
                )
            Text(label)
                .font(.terminusUI(size: 10))
                .foregroundStyle(theme.chromeTextTertiary)
        }
    }
}

// MARK: - Command Palette Row

struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    let theme: TerminusTheme

    var body: some View {
        HStack(spacing: TerminusDesign.spacingSM) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isSelected ? TerminusAccent.primary : theme.chromeTextSecondary
                    )
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.terminusUI(size: 13, weight: .medium))
                    .foregroundStyle(theme.chromeText)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.terminusMono(size: 11))
                        .foregroundStyle(theme.chromeTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? TerminusAccent.primary.opacity(0.15)
                : Color.clear
        )
        .contentShape(Rectangle())
    }
}
