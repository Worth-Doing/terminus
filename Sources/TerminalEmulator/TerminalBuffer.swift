import Foundation
import SharedModels

// MARK: - Terminal Buffer

public final class TerminalBuffer: @unchecked Sendable {
    public private(set) var size: TerminalSize
    public private(set) var cursorRow: Int = 0
    public private(set) var cursorColumn: Int = 0
    public private(set) var lines: [TerminalLine]
    public private(set) var scrollbackLines: [TerminalLine] = []
    public private(set) var isDirty: Bool = false

    private let scrollbackLimit: Int
    private var currentAttributes: CellAttributes = .default

    // Terminal modes
    public var applicationCursorKeys: Bool = false
    public var bracketedPasteMode: Bool = false
    public var alternateScreenActive: Bool = false

    // Alternate screen buffer
    private var savedPrimaryLines: [TerminalLine] = []
    private var savedPrimaryCursor: (row: Int, col: Int) = (0, 0)

    // Scroll region
    public private(set) var scrollTop: Int = 0
    public private(set) var scrollBottom: Int

    private let lock = NSLock()

    public init(size: TerminalSize = .default80x24, scrollbackLimit: Int = 10_000) {
        self.size = size
        self.scrollbackLimit = scrollbackLimit
        self.scrollBottom = size.rows - 1
        self.lines = (0..<size.rows).map { _ in TerminalLine(columns: size.columns) }
    }

    // MARK: - Dirty Tracking

    public func markClean() {
        lock.lock()
        isDirty = false
        lock.unlock()
    }

    private func markDirty() {
        isDirty = true
    }

    // MARK: - Resize

    public func resize(_ newSize: TerminalSize) {
        lock.lock()
        defer { lock.unlock() }

        let oldCols = size.columns
        let oldRows = size.rows
        size = newSize
        scrollBottom = newSize.rows - 1
        scrollTop = 0

        // Adjust existing lines to new column count
        for i in 0..<lines.count {
            if newSize.columns > oldCols {
                lines[i].cells.append(
                    contentsOf: Array(repeating: .blank, count: newSize.columns - oldCols)
                )
            } else if newSize.columns < oldCols {
                lines[i].cells = Array(lines[i].cells.prefix(newSize.columns))
            }
        }

        // Adjust row count
        if newSize.rows > oldRows {
            for _ in 0..<(newSize.rows - oldRows) {
                lines.append(TerminalLine(columns: newSize.columns))
            }
        } else if newSize.rows < oldRows {
            let excess = oldRows - newSize.rows
            let removed = Array(lines.prefix(excess))
            scrollbackLines.append(contentsOf: removed)
            lines.removeFirst(excess)
            trimScrollback()
        }

        cursorRow = min(cursorRow, newSize.rows - 1)
        cursorColumn = min(cursorColumn, newSize.columns - 1)
        markDirty()
    }

    // MARK: - Character Writing

    public func writeCharacter(_ char: Character, width: UInt8 = 1) {
        lock.lock()
        defer { lock.unlock() }

        if cursorColumn >= size.columns {
            carriageReturn()
            lineFeed()
        }

        guard cursorRow >= 0 && cursorRow < lines.count else { return }

        lines[cursorRow].cells[cursorColumn] = TerminalCell(
            character: char,
            width: width,
            attributes: currentAttributes
        )
        cursorColumn += Int(width)
        markDirty()
    }

    // MARK: - Cursor Movement

    public func setCursorPosition(row: Int, column: Int) {
        lock.lock()
        defer { lock.unlock() }
        cursorRow = max(0, min(row, size.rows - 1))
        cursorColumn = max(0, min(column, size.columns - 1))
        markDirty()
    }

    public func moveCursorUp(_ n: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        cursorRow = max(scrollTop, cursorRow - n)
        markDirty()
    }

    public func moveCursorDown(_ n: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        cursorRow = min(scrollBottom, cursorRow + n)
        markDirty()
    }

    public func moveCursorForward(_ n: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        cursorColumn = min(size.columns - 1, cursorColumn + n)
        markDirty()
    }

    public func moveCursorBackward(_ n: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        cursorColumn = max(0, cursorColumn - n)
        markDirty()
    }

    // MARK: - Line Operations

    public func carriageReturn() {
        cursorColumn = 0
    }

    public func lineFeed() {
        if cursorRow == scrollBottom {
            scrollUp()
        } else if cursorRow < size.rows - 1 {
            cursorRow += 1
        }
        markDirty()
    }

    public func reverseLineFeed() {
        lock.lock()
        defer { lock.unlock() }
        if cursorRow == scrollTop {
            scrollDown()
        } else if cursorRow > 0 {
            cursorRow -= 1
        }
        markDirty()
    }

    public func tab() {
        lock.lock()
        defer { lock.unlock() }
        let nextTab = ((cursorColumn / 8) + 1) * 8
        cursorColumn = min(nextTab, size.columns - 1)
        markDirty()
    }

    public func backspace() {
        lock.lock()
        defer { lock.unlock() }
        if cursorColumn > 0 {
            cursorColumn -= 1
        }
        markDirty()
    }

    // MARK: - Scrolling

    private func scrollUp() {
        guard scrollTop < scrollBottom else { return }

        let scrolledLine = lines[scrollTop]
        if !alternateScreenActive {
            scrollbackLines.append(scrolledLine)
            trimScrollback()
        }

        lines.remove(at: scrollTop)
        lines.insert(TerminalLine(columns: size.columns), at: scrollBottom)
    }

    private func scrollDown() {
        guard scrollTop < scrollBottom else { return }
        lines.remove(at: scrollBottom)
        lines.insert(TerminalLine(columns: size.columns), at: scrollTop)
    }

    private func trimScrollback() {
        if scrollbackLines.count > scrollbackLimit {
            scrollbackLines.removeFirst(scrollbackLines.count - scrollbackLimit)
        }
    }

    // MARK: - Erase Operations

    public func eraseInDisplay(mode: Int) {
        lock.lock()
        defer { lock.unlock() }

        switch mode {
        case 0: // From cursor to end
            eraseLine(from: cursorColumn, to: size.columns)
            for i in (cursorRow + 1)..<size.rows {
                lines[i] = TerminalLine(columns: size.columns)
            }
        case 1: // From beginning to cursor
            for i in 0..<cursorRow {
                lines[i] = TerminalLine(columns: size.columns)
            }
            eraseLine(from: 0, to: cursorColumn + 1)
        case 2: // Entire display
            for i in 0..<size.rows {
                lines[i] = TerminalLine(columns: size.columns)
            }
        case 3: // Entire display + scrollback
            scrollbackLines.removeAll()
            for i in 0..<size.rows {
                lines[i] = TerminalLine(columns: size.columns)
            }
        default:
            break
        }
        markDirty()
    }

    public func eraseInLine(mode: Int) {
        lock.lock()
        defer { lock.unlock() }

        switch mode {
        case 0: eraseLine(from: cursorColumn, to: size.columns)
        case 1: eraseLine(from: 0, to: cursorColumn + 1)
        case 2: eraseLine(from: 0, to: size.columns)
        default: break
        }
        markDirty()
    }

    private func eraseLine(from start: Int, to end: Int) {
        guard cursorRow >= 0 && cursorRow < lines.count else { return }
        let s = max(0, start)
        let e = min(end, size.columns)
        for i in s..<e {
            lines[cursorRow].cells[i] = .blank
        }
    }

    // MARK: - Attributes

    public func setAttributes(_ attrs: CellAttributes) {
        currentAttributes = attrs
    }

    public func resetAttributes() {
        currentAttributes = .default
    }

    public var attributes: CellAttributes {
        get { currentAttributes }
        set { currentAttributes = newValue }
    }

    // MARK: - Scroll Region

    public func setScrollRegion(top: Int, bottom: Int) {
        lock.lock()
        defer { lock.unlock() }
        scrollTop = max(0, top)
        scrollBottom = min(bottom, size.rows - 1)
        cursorRow = scrollTop
        cursorColumn = 0
        markDirty()
    }

    // MARK: - Alternate Screen

    public func enableAlternateScreen() {
        lock.lock()
        defer { lock.unlock() }
        guard !alternateScreenActive else { return }
        alternateScreenActive = true
        savedPrimaryLines = lines
        savedPrimaryCursor = (cursorRow, cursorColumn)
        lines = (0..<size.rows).map { _ in TerminalLine(columns: size.columns) }
        cursorRow = 0
        cursorColumn = 0
        markDirty()
    }

    public func disableAlternateScreen() {
        lock.lock()
        defer { lock.unlock() }
        guard alternateScreenActive else { return }
        alternateScreenActive = false
        lines = savedPrimaryLines
        cursorRow = savedPrimaryCursor.row
        cursorColumn = savedPrimaryCursor.col
        savedPrimaryLines = []
        markDirty()
    }

    // MARK: - Insert/Delete

    public func insertLines(_ n: Int) {
        lock.lock()
        defer { lock.unlock() }
        for _ in 0..<n {
            if cursorRow <= scrollBottom {
                lines.remove(at: scrollBottom)
                lines.insert(TerminalLine(columns: size.columns), at: cursorRow)
            }
        }
        markDirty()
    }

    public func deleteLines(_ n: Int) {
        lock.lock()
        defer { lock.unlock() }
        for _ in 0..<n {
            if cursorRow <= scrollBottom {
                lines.remove(at: cursorRow)
                lines.insert(TerminalLine(columns: size.columns), at: scrollBottom)
            }
        }
        markDirty()
    }

    public func deleteCharacters(_ n: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard cursorRow < lines.count else { return }
        let count = min(n, size.columns - cursorColumn)
        lines[cursorRow].cells.removeSubrange(cursorColumn..<(cursorColumn + count))
        lines[cursorRow].cells.append(
            contentsOf: Array(repeating: TerminalCell.blank, count: count)
        )
        markDirty()
    }

    public func insertCharacters(_ n: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard cursorRow < lines.count else { return }
        let count = min(n, size.columns - cursorColumn)
        let blanks = Array(repeating: TerminalCell.blank, count: count)
        lines[cursorRow].cells.insert(contentsOf: blanks, at: cursorColumn)
        lines[cursorRow].cells = Array(lines[cursorRow].cells.prefix(size.columns))
        markDirty()
    }

    // MARK: - Snapshot (for rendering)

    public func snapshot() -> (lines: [TerminalLine], cursorRow: Int, cursorColumn: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (lines, cursorRow, cursorColumn)
    }
}
