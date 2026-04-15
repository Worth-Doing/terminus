import SwiftUI
import SharedModels
import SharedUI
import Foundation

// MARK: - File Node

public struct FileNode: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modifiedDate: Date?
    public var children: [FileNode]?
    public var isExpanded: Bool

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modifiedDate: Date? = nil,
        children: [FileNode]? = nil,
        isExpanded: Bool = false
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
        self.children = children
        self.isExpanded = isExpanded
    }
}

// MARK: - File Explorer State

@MainActor
@Observable
public final class FileExplorerState {
    public var rootPath: String = NSHomeDirectory()
    public var nodes: [FileNode] = []
    public var selectedPath: String?
    public var isLoading: Bool = false
    public var filePreview: String?
    public var previewPath: String?
    public var breadcrumbs: [String] = []

    public init() {}

    public func loadDirectory(_ path: String) {
        rootPath = path
        isLoading = true
        updateBreadcrumbs()

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            nodes = []
            isLoading = false
            return
        }

        nodes = contents
            .filter { !$0.hasPrefix(".") }
            .sorted { lhs, rhs in
                let lhsDir = isDir(path + "/" + lhs)
                let rhsDir = isDir(path + "/" + rhs)
                if lhsDir != rhsDir { return lhsDir }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { name in
                let fullPath = path + "/" + name
                let isDir = isDir(fullPath)
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                return FileNode(
                    name: name,
                    path: fullPath,
                    isDirectory: isDir,
                    size: attrs?[.size] as? Int64,
                    modifiedDate: attrs?[.modificationDate] as? Date
                )
            }

        isLoading = false
    }

    public func toggleExpand(_ node: FileNode) {
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { return }

        if nodes[index].isExpanded {
            nodes[index].isExpanded = false
            nodes[index].children = nil
        } else {
            nodes[index].isExpanded = true
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: node.path) {
                nodes[index].children = contents
                    .filter { !$0.hasPrefix(".") }
                    .sorted { lhs, rhs in
                        let lhsDir = isDir(node.path + "/" + lhs)
                        let rhsDir = isDir(node.path + "/" + rhs)
                        if lhsDir != rhsDir { return lhsDir }
                        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                    }
                    .prefix(50)
                    .map { name in
                        let fullPath = node.path + "/" + name
                        return FileNode(
                            name: name,
                            path: fullPath,
                            isDirectory: isDir(fullPath)
                        )
                    }
            }
        }
    }

    public func previewFile(_ path: String) {
        previewPath = path
        selectedPath = path

        guard !isDir(path) else {
            filePreview = nil
            return
        }

        let maxBytes = 10_000
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: maxBytes),
              let content = String(data: data, encoding: .utf8) else {
            filePreview = nil
            return
        }

        filePreview = content
    }

    public func navigateUp() {
        let parent = (rootPath as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            loadDirectory(parent)
        }
    }

    private func updateBreadcrumbs() {
        let home = NSHomeDirectory()
        var path = rootPath
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        breadcrumbs = path.split(separator: "/").map(String.init)
        if path.hasPrefix("~") {
            breadcrumbs[0] = "~"
        }
    }

    private func isDir(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}

// MARK: - File Explorer Panel

public struct FileExplorerPanel: View {
    @State var state: FileExplorerState
    let theme: TerminusTheme
    let onInsertPath: (String) -> Void
    let onCdTo: (String) -> Void

    public init(
        state: FileExplorerState,
        theme: TerminusTheme,
        onInsertPath: @escaping (String) -> Void = { _ in },
        onCdTo: @escaping (String) -> Void = { _ in }
    ) {
        self.state = state
        self.theme = theme
        self.onInsertPath = onInsertPath
        self.onCdTo = onCdTo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(TerminusAccent.primary)
                Text("Files")
                    .font(.terminusUI(size: 13, weight: .semibold))
                    .foregroundStyle(theme.chromeText)
                Spacer()

                Button { state.navigateUp() } label: {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Go up")

                Button {
                    state.loadDirectory(state.rootPath)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, TerminusDesign.spacingMD)
            .padding(.vertical, TerminusDesign.spacingSM)

            // Breadcrumbs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(state.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7))
                                .foregroundStyle(theme.chromeTextTertiary)
                        }
                        Button {
                            navigateToBreadcrumb(index)
                        } label: {
                            Text(crumb)
                                .font(.terminusMono(size: 10))
                                .foregroundStyle(
                                    index == state.breadcrumbs.count - 1
                                        ? theme.chromeText
                                        : theme.chromeTextSecondary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TerminusDesign.spacingMD)
                .padding(.vertical, 4)
            }
            .background(theme.isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.03))

            Divider().background(theme.chromeDivider)

            // File list
            if state.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.nodes) { node in
                            fileRow(node, depth: 0)

                            if node.isExpanded, let children = node.children {
                                ForEach(children) { child in
                                    fileRow(child, depth: 1)
                                }
                            }
                        }
                    }
                }
            }

            // File preview
            if let preview = state.filePreview, let path = state.previewPath {
                Divider().background(theme.chromeDivider)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text((path as NSString).lastPathComponent)
                            .font(.terminusUI(size: 10, weight: .medium))
                            .foregroundStyle(theme.chromeText)
                        Spacer()
                        Button { state.filePreview = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.chromeTextTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, TerminusDesign.spacingSM)
                    .padding(.vertical, 4)

                    ScrollView {
                        Text(preview)
                            .font(.terminusMono(size: 10))
                            .foregroundStyle(theme.chromeTextSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TerminusDesign.spacingSM)
                    }
                    .frame(maxHeight: 150)
                }
                .background(theme.isDark ? Color.black.opacity(0.15) : Color.black.opacity(0.02))
            }
        }
        .frame(width: TerminusDesign.sidebarWidth)
        .onAppear {
            state.loadDirectory(state.rootPath)
        }
    }

    // MARK: - File Row

    private func fileRow(_ node: FileNode, depth: Int) -> some View {
        let isSelected = state.selectedPath == node.path

        return HStack(spacing: TerminusDesign.spacingSM) {
            // Expand chevron for directories
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.chromeTextTertiary)
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }

            // File icon
            Image(systemName: iconForFile(node))
                .font(.system(size: 11))
                .foregroundStyle(colorForFile(node))
                .frame(width: 14)

            // Name
            Text(node.name)
                .font(.terminusUI(size: 11))
                .foregroundStyle(theme.chromeText)
                .lineLimit(1)

            Spacer()

            // Size
            if let size = node.size, !node.isDirectory {
                Text(formatSize(size))
                    .font(.terminusUI(size: 9))
                    .foregroundStyle(theme.chromeTextTertiary)
            }
        }
        .padding(.leading, CGFloat(depth) * 16 + TerminusDesign.spacingSM)
        .padding(.trailing, TerminusDesign.spacingSM)
        .padding(.vertical, 3)
        .background(isSelected ? TerminusAccent.primary.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                state.toggleExpand(node)
            } else {
                state.previewFile(node.path)
            }
        }
        .onTapGesture(count: 2) {
            if node.isDirectory {
                onCdTo(node.path)
                state.loadDirectory(node.path)
            } else {
                onInsertPath(node.path)
            }
        }
    }

    // MARK: - Helpers

    private func navigateToBreadcrumb(_ index: Int) {
        let home = NSHomeDirectory()
        var parts: [String]

        if state.breadcrumbs.first == "~" {
            parts = [home]
            parts.append(contentsOf: state.breadcrumbs.dropFirst().prefix(index))
        } else {
            parts = Array(state.breadcrumbs.prefix(index + 1))
        }

        let path = parts.joined(separator: "/")
        state.loadDirectory(path)
    }

    private func iconForFile(_ node: FileNode) -> String {
        if node.isDirectory { return "folder.fill" }

        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "rs", "go", "py", "js", "ts", "rb", "java", "c", "cpp", "h":
            return "doc.text"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "doc.badge.gearshape"
        case "md", "txt", "readme":
            return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "ico":
            return "photo"
        case "sh", "bash", "zsh", "fish":
            return "terminal"
        case "lock":
            return "lock.doc"
        case "log":
            return "doc.text.magnifyingglass"
        default:
            return "doc"
        }
    }

    private func colorForFile(_ node: FileNode) -> Color {
        if node.isDirectory { return TerminusAccent.primary }

        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 0.95, green: 0.45, blue: 0.25)
        case "py": return Color(red: 0.25, green: 0.55, blue: 0.85)
        case "js", "ts": return Color(red: 0.95, green: 0.80, blue: 0.25)
        case "rs": return Color(red: 0.85, green: 0.45, blue: 0.25)
        case "go": return Color(red: 0.25, green: 0.75, blue: 0.85)
        case "json", "yaml", "yml": return TerminusAccent.success
        case "md", "txt": return theme.chromeTextSecondary
        default: return theme.chromeTextTertiary
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)K" }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fM", Double(bytes) / 1_048_576) }
        return String(format: "%.1fG", Double(bytes) / 1_073_741_824)
    }
}
