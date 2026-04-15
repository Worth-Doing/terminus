import SwiftUI
import SharedModels
import SharedUI
import TerminalEmulator
import TerminalCore

// MARK: - Terminal Canvas View

public struct TerminalCanvasView: View {
    let buffer: TerminalBuffer
    let theme: TerminusTheme

    private let cellWidth: CGFloat
    private let cellHeight: CGFloat

    public init(buffer: TerminalBuffer, theme: TerminusTheme = .defaultLight) {
        self.buffer = buffer
        self.theme = theme
        // Calculate cell metrics from monospaced font
        let font = NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        self.cellWidth = font.advancement(forGlyph: font.glyph(withName: "M")).width
        self.cellHeight = font.ascender - font.descender + font.leading
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
            Canvas { context, size in
                let snapshot = buffer.snapshot()
                drawBackground(context: context, lines: snapshot.lines)
                drawText(context: context, lines: snapshot.lines)
                drawCursor(
                    context: context,
                    row: snapshot.cursorRow,
                    column: snapshot.cursorColumn
                )
            }
            .frame(
                width: CGFloat(buffer.size.columns) * cellWidth,
                height: CGFloat(buffer.size.rows) * cellHeight
            )
        }
        .background(theme.backgroundColor)
    }

    // MARK: - Drawing

    private func drawBackground(
        context: GraphicsContext,
        lines: [TerminalLine]
    ) {
        for (rowIndex, line) in lines.enumerated() {
            var runStart = 0
            var runBg = line.cells.first?.attributes.background ?? .default

            for (colIndex, cell) in line.cells.enumerated() {
                let bg = cell.attributes.inverse
                    ? cell.attributes.foreground
                    : cell.attributes.background

                if bg != runBg {
                    // Draw previous run
                    if runBg != .default {
                        drawBackgroundRect(
                            context: context,
                            row: rowIndex,
                            startCol: runStart,
                            endCol: colIndex,
                            color: runBg
                        )
                    }
                    runStart = colIndex
                    runBg = bg
                }
            }
            // Final run
            if runBg != .default {
                drawBackgroundRect(
                    context: context,
                    row: rowIndex,
                    startCol: runStart,
                    endCol: line.cells.count,
                    color: runBg
                )
            }
        }
    }

    private func drawBackgroundRect(
        context: GraphicsContext,
        row: Int,
        startCol: Int,
        endCol: Int,
        color: TerminalColor
    ) {
        let rect = CGRect(
            x: CGFloat(startCol) * cellWidth,
            y: CGFloat(row) * cellHeight,
            width: CGFloat(endCol - startCol) * cellWidth,
            height: cellHeight
        )
        context.fill(
            Path(rect),
            with: .color(theme.resolveColor(color, isBackground: true))
        )
    }

    private func drawText(
        context: GraphicsContext,
        lines: [TerminalLine]
    ) {
        for (rowIndex, line) in lines.enumerated() {
            var col = 0
            while col < line.cells.count {
                let cell = line.cells[col]
                let char = cell.character
                guard char != " " || cell.attributes != .default else {
                    col += 1
                    continue
                }

                // Build attributed run
                var runEnd = col + 1
                while runEnd < line.cells.count
                    && line.cells[runEnd].attributes == cell.attributes
                    && line.cells[runEnd].character != " " {
                    runEnd += 1
                }

                let attrs = cell.attributes
                let fg = attrs.inverse ? attrs.background : attrs.foreground
                let resolvedColor = theme.resolveColor(fg)

                // Build the string for the run
                var runChars = ""
                for i in col..<runEnd {
                    runChars.append(line.cells[i].character)
                }

                var attrString = AttributedString(runChars)
                let swiftUIFont: Font = attrs.bold
                    ? .system(size: theme.fontSize, design: .monospaced).bold()
                    : .system(size: theme.fontSize, design: .monospaced)
                attrString.font = attrs.italic ? swiftUIFont.italic() : swiftUIFont
                attrString.foregroundColor = resolvedColor

                if attrs.underline != .none {
                    attrString.underlineStyle = .single
                }

                if attrs.strikethrough {
                    attrString.strikethroughStyle = .single
                }

                if attrs.faint {
                    attrString.foregroundColor = resolvedColor.opacity(0.5)
                }

                let text = Text(attrString)
                let resolvedText = context.resolve(text)

                let point = CGPoint(
                    x: CGFloat(col) * cellWidth,
                    y: CGFloat(rowIndex) * cellHeight
                )
                context.draw(resolvedText, at: point, anchor: .topLeading)

                col = runEnd
            }
        }
    }

    private func drawCursor(
        context: GraphicsContext,
        row: Int,
        column: Int
    ) {
        let rect = CGRect(
            x: CGFloat(column) * cellWidth,
            y: CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        context.fill(
            Path(rect),
            with: .color(theme.cursorColor.opacity(0.7))
        )
    }
}
