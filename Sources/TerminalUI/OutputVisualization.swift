import SwiftUI
import SharedModels
import SharedUI

// MARK: - Output Detector

public enum OutputFormat: Sendable {
    case plainText
    case json
    case table
    case errorLog
    case diff
}

public enum OutputDetector {
    public static func detect(_ output: String) -> OutputFormat {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON detection
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
                return .json
            }
        }

        // Diff detection
        if trimmed.contains("@@") && (trimmed.contains("---") || trimmed.contains("+++")) {
            return .diff
        }

        // Error log detection
        let lowered = trimmed.lowercased()
        let errorIndicators = ["error:", "fatal:", "exception:", "traceback", "panic:", "failed"]
        let errorCount = errorIndicators.filter { lowered.contains($0) }.count
        if errorCount >= 2 || (errorCount >= 1 && trimmed.count < 500) {
            return .errorLog
        }

        // Table detection (multiple lines with consistent column spacing)
        let lines = trimmed.split(separator: "\n")
        if lines.count >= 3 {
            let tabCount = lines.filter { $0.contains("\t") }.count
            if tabCount > lines.count / 2 {
                return .table
            }
            // Check for aligned columns (2+ spaces between words consistently)
            let spaceParts = lines.prefix(5).map {
                $0.split(whereSeparator: { $0 == " " }).count
            }
            if spaceParts.allSatisfy({ $0 > 3 }) {
                let variance = spaceParts.max()! - spaceParts.min()!
                if variance <= 2 {
                    return .table
                }
            }
        }

        return .plainText
    }
}

// MARK: - JSON Viewer

public struct JSONViewer: View {
    let jsonString: String
    let theme: TerminusTheme
    @State private var expandedPaths: Set<String> = ["$"]
    @State private var searchText: String = ""

    public init(jsonString: String, theme: TerminusTheme) {
        self.jsonString = jsonString
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 10))
                    .foregroundStyle(TerminusAccent.primary)
                Text("JSON")
                    .font(.terminusUI(size: 10, weight: .medium))
                    .foregroundStyle(TerminusAccent.primary)
                Spacer()

                // Search in output
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.chromeTextTertiary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.terminusUI(size: 10))
                        .frame(width: 100)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: TerminusDesign.radiusSM)
                        .fill(theme.chromeHover)
                )

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.chromeTextTertiary)
                }
                .buttonStyle(.plain)
                .help("Copy JSON")
            }
            .padding(.horizontal, TerminusDesign.spacingSM)
            .padding(.vertical, 4)
            .background(TerminusAccent.primary.opacity(0.06))

            // JSON tree
            ScrollView {
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    jsonNode(json, path: "$", depth: 0)
                        .padding(TerminusDesign.spacingSM)
                } else {
                    Text(jsonString)
                        .font(.terminusMono(size: 11))
                        .foregroundStyle(theme.chromeText)
                        .padding(TerminusDesign.spacingSM)
                }
            }
        }
    }

    private func jsonNode(_ value: Any, path: String, depth: Int) -> AnyView {
        let indent = CGFloat(depth) * 16

        if let dict = value as? [String: Any] {
            return AnyView(
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(dict.keys.sorted().enumerated()), id: \.offset) { _, key in
                        let childPath = "\(path).\(key)"
                        let childValue = dict[key]!
                        let isExpandable = childValue is [String: Any] || childValue is [Any]
                        let isExpanded = expandedPaths.contains(childPath)
                        let matchesSearch = !searchText.isEmpty && (
                            key.lowercased().contains(searchText.lowercased()) ||
                            String(describing: childValue).lowercased().contains(searchText.lowercased())
                        )

                        HStack(alignment: .top, spacing: 4) {
                            if isExpandable {
                                Button {
                                    if isExpanded {
                                        expandedPaths.remove(childPath)
                                    } else {
                                        expandedPaths.insert(childPath)
                                    }
                                } label: {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(theme.chromeTextTertiary)
                                        .frame(width: 10)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Spacer().frame(width: 10)
                            }

                            Text("\"\(key)\"")
                                .font(.terminusMono(size: 11))
                                .foregroundStyle(TerminusAccent.primary)

                            Text(":")
                                .font(.terminusMono(size: 11))
                                .foregroundStyle(theme.chromeTextTertiary)

                            if isExpandable {
                                if isExpanded {
                                    jsonNode(childValue, path: childPath, depth: depth + 1)
                                } else {
                                    Text(childValue is [String: Any] ? "{...}" : "[...]")
                                        .font(.terminusMono(size: 11))
                                        .foregroundStyle(theme.chromeTextTertiary)
                                }
                            } else {
                                jsonValueView(childValue)
                            }
                        }
                        .padding(.leading, indent)
                        .background(matchesSearch ? TerminusAccent.warning.opacity(0.15) : Color.clear)
                    }
                }
            )
        } else if let array = value as? [Any] {
            return AnyView(
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                        let childPath = "\(path)[\(index)]"
                        let isExpandable = item is [String: Any] || item is [Any]
                        let isExpanded = expandedPaths.contains(childPath)

                        HStack(alignment: .top, spacing: 4) {
                            if isExpandable {
                                Button {
                                    if isExpanded {
                                        expandedPaths.remove(childPath)
                                    } else {
                                        expandedPaths.insert(childPath)
                                    }
                                } label: {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(theme.chromeTextTertiary)
                                        .frame(width: 10)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Spacer().frame(width: 10)
                            }

                            Text("[\(index)]")
                                .font(.terminusMono(size: 11))
                                .foregroundStyle(theme.chromeTextTertiary)

                            if isExpandable && isExpanded {
                                jsonNode(item, path: childPath, depth: depth + 1)
                            } else if isExpandable {
                                Text(item is [String: Any] ? "{...}" : "[...]")
                                    .font(.terminusMono(size: 11))
                                    .foregroundStyle(theme.chromeTextTertiary)
                            } else {
                                jsonValueView(item)
                            }
                        }
                        .padding(.leading, indent)
                    }
                }
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    private func jsonValueView(_ value: Any) -> some View {
        Group {
            if let str = value as? String {
                Text("\"\(str)\"")
                    .font(.terminusMono(size: 11))
                    .foregroundStyle(TerminusAccent.success)
            } else if let num = value as? NSNumber {
                if num === kCFBooleanTrue || num === kCFBooleanFalse {
                    Text(num.boolValue ? "true" : "false")
                        .font(.terminusMono(size: 11, weight: .medium))
                        .foregroundStyle(TerminusAccent.warning)
                } else {
                    Text("\(num)")
                        .font(.terminusMono(size: 11))
                        .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 0.9))
                }
            } else if value is NSNull {
                Text("null")
                    .font(.terminusMono(size: 11, weight: .medium))
                    .foregroundStyle(TerminusAccent.error)
            } else {
                Text(String(describing: value))
                    .font(.terminusMono(size: 11))
                    .foregroundStyle(theme.chromeText)
            }
        }
    }
}

// MARK: - Diff Viewer

public struct DiffViewer: View {
    let diffText: String
    let theme: TerminusTheme

    public init(diffText: String, theme: TerminusTheme) {
        self.diffText = diffText
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 10))
                    .foregroundStyle(TerminusAccent.primary)
                Text("Diff")
                    .font(.terminusUI(size: 10, weight: .medium))
                    .foregroundStyle(TerminusAccent.primary)
                Spacer()
            }
            .padding(.horizontal, TerminusDesign.spacingSM)
            .padding(.vertical, 4)
            .background(TerminusAccent.primary.opacity(0.06))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffText.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        let lineStr = String(line)
                        HStack(spacing: 0) {
                            Text(lineStr)
                                .font(.terminusMono(size: 11))
                                .foregroundStyle(diffLineColor(lineStr))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, TerminusDesign.spacingSM)
                        .padding(.vertical, 0.5)
                        .background(diffLineBackground(lineStr))
                    }
                }
                .padding(.vertical, TerminusDesign.spacingXS)
            }
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return TerminusAccent.success
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return TerminusAccent.error
        } else if line.hasPrefix("@@") {
            return TerminusAccent.primary
        }
        return theme.chromeTextSecondary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return TerminusAccent.success.opacity(0.08)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return TerminusAccent.error.opacity(0.08)
        }
        return .clear
    }
}

// MARK: - Error Output View

public struct ErrorOutputView: View {
    let output: String
    let theme: TerminusTheme
    let onFixWithAI: (() -> Void)?

    public init(output: String, theme: TerminusTheme, onFixWithAI: (() -> Void)? = nil) {
        self.output = output
        self.theme = theme
        self.onFixWithAI = onFixWithAI
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TerminusDesign.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(TerminusAccent.error)
                Text("Error Output")
                    .font(.terminusUI(size: 10, weight: .medium))
                    .foregroundStyle(TerminusAccent.error)
                Spacer()

                if let fix = onFixWithAI {
                    Button {
                        fix()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                            Text("Fix with AI")
                                .font(.terminusUI(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(TerminusAccent.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TerminusDesign.spacingSM)
            .padding(.vertical, 4)
            .background(TerminusAccent.error.opacity(0.08))

            ScrollView {
                Text(highlightedErrors)
                    .font(.terminusMono(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TerminusDesign.spacingSM)
            }
        }
    }

    private var highlightedErrors: AttributedString {
        var result = AttributedString(output)
        let errorPatterns = ["error:", "Error:", "ERROR:", "fatal:", "Fatal:", "FATAL:",
                             "failed", "Failed", "FAILED", "panic:", "Panic:"]

        for pattern in errorPatterns {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: pattern) {
                result[range].foregroundColor = NSColor(TerminusAccent.error)
                result[range].font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                searchRange = range.upperBound..<result.endIndex
            }
        }

        return result
    }
}

// MARK: - Smart Output View

public struct SmartOutputView: View {
    let output: String
    let theme: TerminusTheme
    let onFixWithAI: (() -> Void)?

    public init(output: String, theme: TerminusTheme, onFixWithAI: (() -> Void)? = nil) {
        self.output = output
        self.theme = theme
        self.onFixWithAI = onFixWithAI
    }

    public var body: some View {
        let format = OutputDetector.detect(output)

        switch format {
        case .json:
            JSONViewer(jsonString: output.trimmingCharacters(in: .whitespacesAndNewlines), theme: theme)
        case .diff:
            DiffViewer(diffText: output, theme: theme)
        case .errorLog:
            ErrorOutputView(output: output, theme: theme, onFixWithAI: onFixWithAI)
        case .table, .plainText:
            ScrollView {
                Text(output)
                    .font(.terminusMono(size: 11))
                    .foregroundStyle(theme.chromeTextSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TerminusDesign.spacingSM)
            }
        }
    }
}

// MARK: - Output Search Bar

public struct OutputSearchBar: View {
    @Binding var searchText: String
    let matchCount: Int
    let currentMatch: Int
    let theme: TerminusTheme
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onDismiss: () -> Void

    public init(
        searchText: Binding<String>,
        matchCount: Int = 0,
        currentMatch: Int = 0,
        theme: TerminusTheme,
        onNext: @escaping () -> Void = {},
        onPrevious: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self._searchText = searchText
        self.matchCount = matchCount
        self.currentMatch = currentMatch
        self.theme = theme
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: TerminusDesign.spacingSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.chromeTextTertiary)

            TextField("Search output...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.terminusUI(size: 12))

            if !searchText.isEmpty {
                Text("\(currentMatch)/\(matchCount)")
                    .font(.terminusUI(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)

                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
                .buttonStyle(.plain)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.chromeTextSecondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.chromeTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TerminusDesign.spacingMD)
        .padding(.vertical, 5)
        .background(theme.chromeBackground)
        .overlay(alignment: .bottom) {
            Divider().background(theme.chromeDivider)
        }
    }
}
