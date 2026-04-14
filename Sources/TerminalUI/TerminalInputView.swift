import SwiftUI
import AppKit
import SharedModels
import TerminalEmulator

// MARK: - Terminal Input Handler Protocol

@MainActor
public protocol TerminalInputHandler: AnyObject {
    func sendInput(_ data: Data) async
}

// MARK: - Full Terminal View (NSViewRepresentable)
// This is the MAIN terminal view — it handles both rendering and input

public struct TerminalNSViewRepresentable: NSViewRepresentable {
    let buffer: TerminalBuffer
    let theme: TerminusTheme
    let isFocused: Bool
    weak var inputHandler: (any TerminalInputHandler)?
    let renderGeneration: UInt64

    public init(
        buffer: TerminalBuffer,
        theme: TerminusTheme,
        isFocused: Bool,
        inputHandler: (any TerminalInputHandler)?,
        renderGeneration: UInt64
    ) {
        self.buffer = buffer
        self.theme = theme
        self.isFocused = isFocused
        self.inputHandler = inputHandler
        self.renderGeneration = renderGeneration
    }

    public func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView()
        view.inputHandler = inputHandler
        view.terminalBuffer = buffer
        view.theme = theme
        return view
    }

    public func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.inputHandler = inputHandler
        nsView.terminalBuffer = buffer
        nsView.theme = theme
        nsView.renderGeneration = renderGeneration

        // Force redraw when render generation changes
        nsView.needsDisplay = true

        // Grab focus if this panel is focused
        if isFocused && nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

// MARK: - Terminal NS View

@MainActor
public class TerminalNSView: NSView, @preconcurrency NSTextInputClient {
    weak var inputHandler: (any TerminalInputHandler)?
    var terminalBuffer: TerminalBuffer?
    var theme: TerminusTheme = .defaultDark
    var renderGeneration: UInt64 = 0

    private var _markedText: NSMutableAttributedString = NSMutableAttributedString()
    private var _markedRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var _selectedRange: NSRange = NSRange(location: 0, length: 0)

    // Cell metrics (computed from theme font size)
    private var cellWidth: CGFloat = 8.4
    private var cellHeight: CGFloat = 17.0
    private var monoFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    private var monoBoldFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .bold)

    // Cursor blink
    private var cursorVisible: Bool = true
    private var cursorTimer: Timer?

    // MARK: - View Setup

    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        startCursorBlink()
        return true
    }

    public override func resignFirstResponder() -> Bool {
        stopCursorBlink()
        cursorVisible = true
        needsDisplay = true
        return true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMetrics()
        // Become first responder when added to window
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMetrics()

        // Resize the terminal buffer to match view size
        guard let buffer = terminalBuffer else { return }
        let cols = max(1, Int(newSize.width / cellWidth))
        let rows = max(1, Int(newSize.height / cellHeight))
        if cols != buffer.size.columns || rows != buffer.size.rows {
            Task { [weak self] in
                await (self?.inputHandler as? TerminalSessionController)?.resize(
                    TerminalSize(columns: cols, rows: rows)
                )
            }
        }
    }

    private func updateMetrics() {
        monoFont = .monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        monoBoldFont = .monospacedSystemFont(ofSize: theme.fontSize, weight: .bold)
        cellWidth = monoFont.advancement(forGlyph: monoFont.glyph(withName: "M")).width
        cellHeight = ceil(monoFont.ascender - monoFont.descender + monoFont.leading)
    }

    // MARK: - Cursor Blink

    private func startCursorBlink() {
        stopCursorBlink()
        cursorVisible = true
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cursorVisible.toggle()
                self?.needsDisplay = true
            }
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let buffer = terminalBuffer else { return }

        let snapshot = buffer.snapshot()

        // Background
        let bgColor = nsColor(theme.backgroundColor)
        ctx.setFillColor(bgColor)
        ctx.fill(bounds)

        // Draw each line
        for (rowIndex, line) in snapshot.lines.enumerated() {
            let y = CGFloat(rowIndex) * cellHeight

            // Draw backgrounds first
            drawLineBackgrounds(ctx: ctx, line: line, y: y)

            // Draw text
            drawLineText(ctx: ctx, line: line, y: y)
        }

        // Draw selection highlight
        drawSelection(ctx: ctx)

        // Draw cursor
        if cursorVisible {
            drawCursor(ctx: ctx, row: snapshot.cursorRow, col: snapshot.cursorColumn)
        }
    }

    private func drawSelection(ctx: CGContext) {
        guard let start = selectionStart, let end = selectionEnd else { return }

        let minRow = min(start.row, end.row)
        let maxRow = max(start.row, end.row)

        ctx.setFillColor(CGColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 0.4))

        for row in minRow...maxRow {
            let startCol: Int
            let endCol: Int

            if minRow == maxRow {
                startCol = min(start.col, end.col)
                endCol = max(start.col, end.col)
            } else if row == minRow {
                startCol = start.row < end.row ? start.col : end.col
                endCol = terminalBuffer?.size.columns ?? 80
            } else if row == maxRow {
                startCol = 0
                endCol = start.row < end.row ? end.col : start.col
            } else {
                startCol = 0
                endCol = terminalBuffer?.size.columns ?? 80
            }

            ctx.fill(CGRect(
                x: CGFloat(startCol) * cellWidth,
                y: CGFloat(row) * cellHeight,
                width: CGFloat(endCol - startCol) * cellWidth,
                height: cellHeight
            ))
        }
    }

    private func drawLineBackgrounds(ctx: CGContext, line: TerminalLine, y: CGFloat) {
        for (colIndex, cell) in line.cells.enumerated() {
            let bg = cell.attributes.inverse
                ? cell.attributes.foreground
                : cell.attributes.background

            guard bg != .default else { continue }

            let color = resolveTerminalColor(bg, isBackground: true)
            ctx.setFillColor(color)
            ctx.fill(CGRect(
                x: CGFloat(colIndex) * cellWidth,
                y: y,
                width: cellWidth,
                height: cellHeight
            ))
        }
    }

    private func drawLineText(ctx: CGContext, line: TerminalLine, y: CGFloat) {
        var col = 0
        while col < line.cells.count {
            let cell = line.cells[col]
            guard cell.character != " " else {
                col += 1
                continue
            }

            let attrs = cell.attributes
            let fg = attrs.inverse ? attrs.background : attrs.foreground
            let fgColor = resolveTerminalColor(fg, isBackground: false)

            let font = attrs.bold ? monoBoldFont : monoFont

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(cgColor: fgColor) ?? .white,
            ]

            let str = String(cell.character)
            let point = CGPoint(
                x: CGFloat(col) * cellWidth,
                y: y + monoFont.ascender
            )

            // Draw with CoreText for better perf
            str.draw(at: NSPoint(x: point.x, y: y), withAttributes: attributes)

            col += 1
        }
    }

    private func drawCursor(ctx: CGContext, row: Int, col: Int) {
        let x = CGFloat(col) * cellWidth
        let y = CGFloat(row) * cellHeight

        // Cursor color
        let cursorColor = nsColor(theme.cursorColor)

        if window?.firstResponder === self {
            // Focused: filled block
            ctx.setFillColor(cursorColor.copy(alpha: 0.7)!)
            ctx.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        } else {
            // Unfocused: outline
            ctx.setStrokeColor(cursorColor.copy(alpha: 0.5)!)
            ctx.setLineWidth(1.5)
            ctx.stroke(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }
    }

    // MARK: - Color Resolution

    private func resolveTerminalColor(_ color: TerminalColor, isBackground: Bool) -> CGColor {
        switch color {
        case .default:
            return isBackground
                ? nsColor(theme.backgroundColor)
                : nsColor(theme.foregroundColor)
        case .indexed(let index):
            return nsColorFromAnsi(index)
        case .rgb(let r, let g, let b):
            return CGColor(
                red: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: 1.0
            )
        }
    }

    private func nsColor(_ swiftUIColor: Color) -> CGColor {
        NSColor(swiftUIColor).cgColor
    }

    private func nsColorFromAnsi(_ index: UInt8) -> CGColor {
        // Standard 16 colors
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.15, 0.15, 0.17),  // 0 black
            (0.91, 0.35, 0.35),  // 1 red
            (0.35, 0.82, 0.47),  // 2 green
            (0.95, 0.80, 0.35),  // 3 yellow
            (0.40, 0.60, 0.95),  // 4 blue
            (0.78, 0.45, 0.90),  // 5 magenta
            (0.35, 0.82, 0.85),  // 6 cyan
            (0.85, 0.86, 0.88),  // 7 white
            (0.40, 0.40, 0.43),  // 8 bright black
            (1.00, 0.45, 0.45),  // 9 bright red
            (0.45, 0.92, 0.57),  // 10 bright green
            (1.00, 0.90, 0.45),  // 11 bright yellow
            (0.55, 0.73, 1.00),  // 12 bright blue
            (0.88, 0.55, 1.00),  // 13 bright magenta
            (0.45, 0.92, 0.95),  // 14 bright cyan
            (0.95, 0.96, 0.97),  // 15 bright white
        ]

        if index < 16 {
            let c = colors[Int(index)]
            return CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        } else if index >= 16 && index <= 231 {
            let adjusted = Int(index) - 16
            let r = CGFloat((adjusted / 36) % 6) / 5.0
            let g = CGFloat((adjusted / 6) % 6) / 5.0
            let b = CGFloat(adjusted % 6) / 5.0
            return CGColor(red: r, green: g, blue: b, alpha: 1)
        } else {
            let gray = (CGFloat(Int(index) - 232) * 10.0 + 8.0) / 255.0
            return CGColor(red: gray, green: gray, blue: gray, alpha: 1)
        }
    }

    // MARK: - Key Events

    public override func keyDown(with event: NSEvent) {
        // Reset cursor blink on keypress
        cursorVisible = true
        scrollbackOffset = 0  // Snap back to bottom on keypress
        selectionStart = nil  // Clear selection on type
        selectionEnd = nil
        needsDisplay = true

        // Handle Cmd+C/V/A/K shortcuts
        if handleCommandShortcut(event) { return }

        // Check for special key combinations first
        if let data = translateKeyEvent(event) {
            sendData(data)
            return
        }

        // Fall through to text input system for regular characters
        interpretKeyEvents([event])
    }

    // MARK: - NSTextInputClient

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }

        if let data = text.data(using: .utf8) {
            sendData(data)
        }

        _markedText = NSMutableAttributedString()
        _markedRange = NSRange(location: NSNotFound, length: 0)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let str = string as? String {
            _markedText = NSMutableAttributedString(string: str)
        } else if let attrStr = string as? NSAttributedString {
            _markedText = NSMutableAttributedString(attributedString: attrStr)
        }
        _markedRange = NSRange(location: 0, length: _markedText.length)
        _selectedRange = selectedRange
    }

    public func unmarkText() {
        _markedText = NSMutableAttributedString()
        _markedRange = NSRange(location: NSNotFound, length: 0)
    }

    public func selectedRange() -> NSRange { _selectedRange }
    public func markedRange() -> NSRange { _markedRange }
    public func hasMarkedText() -> Bool { _markedText.length > 0 }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let viewRect = convert(bounds, to: nil)
        return window.convertToScreen(viewRect)
    }

    public func characterIndex(for point: NSPoint) -> Int { 0 }

    // MARK: - Scrollback

    private var scrollbackOffset: Int = 0

    public override func scrollWheel(with event: NSEvent) {
        guard let buffer = terminalBuffer else { return }

        let delta = Int(event.scrollingDeltaY)
        if delta == 0 { return }

        let maxOffset = buffer.scrollbackLines.count
        scrollbackOffset = max(0, min(maxOffset, scrollbackOffset + delta))
        needsDisplay = true
    }

    // MARK: - Selection + Copy/Paste

    private var selectionStart: (row: Int, col: Int)?
    private var selectionEnd: (row: Int, col: Int)?

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        let col = max(0, Int(point.x / cellWidth))
        let row = max(0, Int(point.y / cellHeight))

        selectionStart = (row, col)
        selectionEnd = nil
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let col = max(0, Int(point.x / cellWidth))
        let row = max(0, Int(point.y / cellHeight))

        selectionEnd = (row, col)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        // Double-click selects word
        if event.clickCount == 2 {
            selectWord(at: event)
        }
    }

    private func selectWord(at event: NSEvent) {
        guard let buffer = terminalBuffer else { return }
        let point = convert(event.locationInWindow, from: nil)
        let col = max(0, min(Int(point.x / cellWidth), buffer.size.columns - 1))
        let row = max(0, min(Int(point.y / cellHeight), buffer.size.rows - 1))

        let snapshot = buffer.snapshot()
        guard row < snapshot.lines.count else { return }

        let line = snapshot.lines[row]
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-./"))

        // Find word boundaries
        var start = col
        var end = col

        while start > 0 {
            let char = line.cells[start - 1].character
            if char.unicodeScalars.allSatisfy({ wordChars.contains($0) }) {
                start -= 1
            } else { break }
        }

        while end < line.cells.count - 1 {
            let char = line.cells[end + 1].character
            if char.unicodeScalars.allSatisfy({ wordChars.contains($0) }) {
                end += 1
            } else { break }
        }

        selectionStart = (row, start)
        selectionEnd = (row, end + 1)
        needsDisplay = true
    }

    private func getSelectedText() -> String? {
        guard let start = selectionStart, let end = selectionEnd,
              let buffer = terminalBuffer else { return nil }

        let snapshot = buffer.snapshot()
        var text = ""

        let minRow = min(start.row, end.row)
        let maxRow = max(start.row, end.row)

        for row in minRow...maxRow {
            guard row < snapshot.lines.count else { continue }
            let line = snapshot.lines[row]

            let startCol: Int
            let endCol: Int

            if minRow == maxRow {
                startCol = min(start.col, end.col)
                endCol = max(start.col, end.col)
            } else if row == minRow {
                startCol = start.row < end.row ? start.col : end.col
                endCol = line.cells.count
            } else if row == maxRow {
                startCol = 0
                endCol = start.row < end.row ? end.col : start.col
            } else {
                startCol = 0
                endCol = line.cells.count
            }

            for col in startCol..<min(endCol, line.cells.count) {
                text.append(line.cells[col].character)
            }
            if row < maxRow {
                text.append("\n")
            }
        }

        return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
    }

    // Copy/paste via doCommandBySelector
    @objc func performCopy() {
        guard let text = getSelectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func performPaste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }

        let buffer = terminalBuffer
        if buffer?.bracketedPasteMode == true {
            let bracketedData = Data([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E])
                + Data(text.utf8)
                + Data([0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
            sendData(bracketedData)
        } else {
            if let data = text.data(using: .utf8) {
                sendData(data)
            }
        }
    }

    @objc func performSelectAll() {
        guard let buffer = terminalBuffer else { return }
        selectionStart = (0, 0)
        selectionEnd = (buffer.size.rows - 1, buffer.size.columns)
        needsDisplay = true
    }

    // Handle Cmd+C / Cmd+V via keyDown before interpretKeyEvents
    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        guard let chars = event.charactersIgnoringModifiers else { return false }

        switch chars {
        case "c":
            performCopy()
            return true
        case "v":
            performPaste()
            return true
        case "a":
            performSelectAll()
            return true
        case "k":
            // Clear terminal
            terminalBuffer?.eraseInDisplay(mode: 2)
            terminalBuffer?.setCursorPosition(row: 0, column: 0)
            needsDisplay = true
            return true
        default:
            return false
        }
    }

    // MARK: - Key Translation

    private func translateKeyEvent(_ event: NSEvent) -> Data? {
        let modifiers = event.modifierFlags
        let keyCode = event.keyCode

        // Control key combinations
        if modifiers.contains(.control) {
            if let chars = event.charactersIgnoringModifiers, let char = chars.first {
                let asciiValue = char.asciiValue ?? 0
                if asciiValue >= 0x61 && asciiValue <= 0x7A {
                    return Data([asciiValue - 0x60])
                }
                switch char {
                case "[": return Data([0x1B])
                case "\\": return Data([0x1C])
                case "]": return Data([0x1D])
                case "^": return Data([0x1E])
                case "_": return Data([0x1F])
                case " ": return Data([0x00])
                default: break
                }
            }
        }

        let applicationMode = terminalBuffer?.applicationCursorKeys ?? false

        switch keyCode {
        case 36: return Data([0x0D])   // Return
        case 48:                        // Tab
            return modifiers.contains(.shift) ? Data([0x1B, 0x5B, 0x5A]) : Data([0x09])
        case 51: return Data([0x7F])   // Backspace
        case 117: return Data([0x1B, 0x5B, 0x33, 0x7E])  // Forward Delete
        case 53: return Data([0x1B])   // Escape
        case 126: return arrowKey(0x41, modifiers: modifiers, applicationMode: applicationMode) // Up
        case 125: return arrowKey(0x42, modifiers: modifiers, applicationMode: applicationMode) // Down
        case 124: return arrowKey(0x43, modifiers: modifiers, applicationMode: applicationMode) // Right
        case 123: return arrowKey(0x44, modifiers: modifiers, applicationMode: applicationMode) // Left
        case 115: return Data([0x1B, 0x5B, 0x48])  // Home
        case 119: return Data([0x1B, 0x5B, 0x46])  // End
        case 116: return Data([0x1B, 0x5B, 0x35, 0x7E])  // Page Up
        case 121: return Data([0x1B, 0x5B, 0x36, 0x7E])  // Page Down
        case 122: return Data([0x1B, 0x4F, 0x50])  // F1
        case 120: return Data([0x1B, 0x4F, 0x51])  // F2
        case 99:  return Data([0x1B, 0x4F, 0x52])  // F3
        case 118: return Data([0x1B, 0x4F, 0x53])  // F4
        default:
            if modifiers.contains(.option) {
                if let chars = event.charactersIgnoringModifiers,
                   let data = chars.data(using: .utf8) {
                    return Data([0x1B]) + data
                }
            }
            return nil
        }
    }

    private func arrowKey(_ code: UInt8, modifiers: NSEvent.ModifierFlags, applicationMode: Bool) -> Data {
        var mod = 1
        if modifiers.contains(.shift) { mod += 1 }
        if modifiers.contains(.option) { mod += 2 }
        if modifiers.contains(.control) { mod += 4 }

        if mod > 1 {
            return Data([0x1B, 0x5B, 0x31, 0x3B]) + Data(String(mod).utf8) + Data([code])
        }
        return applicationMode ? Data([0x1B, 0x4F, code]) : Data([0x1B, 0x5B, code])
    }

    // MARK: - Send Data

    private func sendData(_ data: Data) {
        Task { [weak self] in
            await self?.inputHandler?.sendInput(data)
        }
    }
}

// MARK: - Import SharedUI for theme
import SharedUI
