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

    // Dirty region tracking — which rows changed since last snapshot
    public private(set) var dirtyRows: Set<Int> = []
    private var fullRedrawNeeded: Bool = true

    private let scrollbackLimit: Int
    private var currentAttributes: CellAttributes = .default

    // Terminal modes
    public var applicationCursorKeys: Bool = false
    public var bracketedPasteMode: Bool = false
    public var alternateScreenActive: Bool = false

    // Mouse reporting mode
    public enum MouseReportingMode: Sendable {
        case none          // No mouse reporting
        case press         // Mode 1000: Report button press
        case pressRelease  // Mode 1002: Report press, release, and motion while pressed
        case motion        // Mode 1003: Report all motion events
    }
    public var mouseReportingMode: MouseReportingMode = .none

    // Alternate screen buffer
    private var savedPrimaryLines: [TerminalLine] = []
    private var savedPrimaryCursor: (row: Int, col: Int) = (0, 0)

    // Scroll region
    public private(set) var scrollTop: Int = 0
    public private(set) var scrollBottom: Int

    private var unfairLock = os_unfair_lock()

    public init(size: TerminalSize = .default80x24, scrollbackLimit: Int = 10_000) {
        self.size = size
        self.scrollbackLimit = scrollbackLimit
        self.scrollBottom = size.rows - 1
        self.lines = (0..<size.rows).map { _ in TerminalLine(columns: size.columns) }
    }

    // MARK: - Lock Helpers

    @inline(__always)
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        return try body()
    }

    // MARK: - Write Lock for Parser

    /// Call from EscapeSequenceParser.feed() to hold the lock for the entire
    /// byte processing loop, eliminating per-operation lock overhead.
    public func withWriteLock(_ body: () -> Void) {
        os_unfair_lock_lock(&unfairLock)
        body()
        os_unfair_lock_unlock(&unfairLock)
    }

    // MARK: - Dirty Tracking

    public func markClean() {
        withLock {
            isDirty = false
            dirtyRows.removeAll(keepingCapacity: true)
            fullRedrawNeeded = false
        }
    }

    private func markDirty() {
        isDirty = true
    }

    @inline(__always)
    private func markRowDirty(_ row: Int) {
        isDirty = true
        dirtyRows.insert(row)
    }

    @inline(__always)
    private func markAllRowsDirty() {
        isDirty = true
        fullRedrawNeeded = true
    }

    // MARK: - Resize

    public func resize(_ newSize: TerminalSize) {
        withLock {
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
            markAllRowsDirty()
        }
    }

    // MARK: - Character Writing

    public func writeCharacter(_ char: Character, width: UInt8 = 1) {
        withLock {
            if cursorColumn >= size.columns {
                carriageReturn()
                lineFeedInternal()
            }

            guard cursorRow >= 0 && cursorRow < lines.count else { return }

            lines[cursorRow].cells[cursorColumn] = TerminalCell(
                character: char,
                width: width,
                attributes: currentAttributes
            )
            cursorColumn += Int(width)
            markRowDirty(cursorRow)
        }
    }

    // MARK: - Cursor Movement

    public func setCursorPosition(row: Int, column: Int) {
        withLock {
            let oldRow = cursorRow
            cursorRow = max(0, min(row, size.rows - 1))
            cursorColumn = max(0, min(column, size.columns - 1))
            markRowDirty(oldRow)
            markRowDirty(cursorRow)
        }
    }

    public func moveCursorUp(_ n: Int = 1) {
        withLock {
            let oldRow = cursorRow
            cursorRow = max(scrollTop, cursorRow - n)
            markRowDirty(oldRow)
            markRowDirty(cursorRow)
        }
    }

    public func moveCursorDown(_ n: Int = 1) {
        withLock {
            let oldRow = cursorRow
            cursorRow = min(scrollBottom, cursorRow + n)
            markRowDirty(oldRow)
            markRowDirty(cursorRow)
        }
    }

    public func moveCursorForward(_ n: Int = 1) {
        withLock {
            cursorColumn = min(size.columns - 1, cursorColumn + n)
            markRowDirty(cursorRow)
        }
    }

    public func moveCursorBackward(_ n: Int = 1) {
        withLock {
            cursorColumn = max(0, cursorColumn - n)
            markRowDirty(cursorRow)
        }
    }

    // MARK: - Line Operations

    public func carriageReturn() {
        cursorColumn = 0
    }

    public func lineFeed() {
        withLock {
            lineFeedInternal()
        }
    }

    /// Internal lineFeed — must be called while lock is held
    private func lineFeedInternal() {
        if cursorRow == scrollBottom {
            scrollUp()
            // Scroll affects all rows in the scroll region
            for row in scrollTop...scrollBottom {
                markRowDirty(row)
            }
        } else if cursorRow < size.rows - 1 {
            markRowDirty(cursorRow)
            cursorRow += 1
            markRowDirty(cursorRow)
        }
        markDirty()
    }

    public func reverseLineFeed() {
        withLock {
            if cursorRow == scrollTop {
                scrollDown()
                for row in scrollTop...scrollBottom {
                    markRowDirty(row)
                }
            } else if cursorRow > 0 {
                markRowDirty(cursorRow)
                cursorRow -= 1
                markRowDirty(cursorRow)
            }
            markDirty()
        }
    }

    public func tab() {
        withLock {
            let nextTab = ((cursorColumn / 8) + 1) * 8
            cursorColumn = min(nextTab, size.columns - 1)
            markRowDirty(cursorRow)
        }
    }

    public func backspace() {
        withLock {
            if cursorColumn > 0 {
                cursorColumn -= 1
            }
            markRowDirty(cursorRow)
        }
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
        withLock {
            switch mode {
            case 0: // From cursor to end
                eraseLine(from: cursorColumn, to: size.columns)
                for i in (cursorRow + 1)..<size.rows {
                    lines[i] = TerminalLine(columns: size.columns)
                    markRowDirty(i)
                }
                markRowDirty(cursorRow)
            case 1: // From beginning to cursor
                for i in 0..<cursorRow {
                    lines[i] = TerminalLine(columns: size.columns)
                    markRowDirty(i)
                }
                eraseLine(from: 0, to: cursorColumn + 1)
                markRowDirty(cursorRow)
            case 2: // Entire display
                for i in 0..<size.rows {
                    lines[i] = TerminalLine(columns: size.columns)
                }
                markAllRowsDirty()
            case 3: // Entire display + scrollback
                scrollbackLines.removeAll()
                for i in 0..<size.rows {
                    lines[i] = TerminalLine(columns: size.columns)
                }
                markAllRowsDirty()
            default:
                break
            }
        }
    }

    public func eraseInLine(mode: Int) {
        withLock {
            switch mode {
            case 0: eraseLine(from: cursorColumn, to: size.columns)
            case 1: eraseLine(from: 0, to: cursorColumn + 1)
            case 2: eraseLine(from: 0, to: size.columns)
            default: break
            }
            markRowDirty(cursorRow)
        }
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
        withLock {
            scrollTop = max(0, top)
            scrollBottom = min(bottom, size.rows - 1)
            cursorRow = scrollTop
            cursorColumn = 0
            markAllRowsDirty()
        }
    }

    // MARK: - Alternate Screen

    public func enableAlternateScreen() {
        withLock {
            guard !alternateScreenActive else { return }
            alternateScreenActive = true
            savedPrimaryLines = lines
            savedPrimaryCursor = (cursorRow, cursorColumn)
            lines = (0..<size.rows).map { _ in TerminalLine(columns: size.columns) }
            cursorRow = 0
            cursorColumn = 0
            markAllRowsDirty()
        }
    }

    public func disableAlternateScreen() {
        withLock {
            guard alternateScreenActive else { return }
            alternateScreenActive = false
            lines = savedPrimaryLines
            cursorRow = savedPrimaryCursor.row
            cursorColumn = savedPrimaryCursor.col
            savedPrimaryLines = []
            markAllRowsDirty()
        }
    }

    // MARK: - Insert/Delete

    public func insertLines(_ n: Int) {
        withLock {
            for _ in 0..<n {
                if cursorRow <= scrollBottom {
                    lines.remove(at: scrollBottom)
                    lines.insert(TerminalLine(columns: size.columns), at: cursorRow)
                }
            }
            for row in cursorRow...scrollBottom {
                markRowDirty(row)
            }
        }
    }

    public func deleteLines(_ n: Int) {
        withLock {
            for _ in 0..<n {
                if cursorRow <= scrollBottom {
                    lines.remove(at: cursorRow)
                    lines.insert(TerminalLine(columns: size.columns), at: scrollBottom)
                }
            }
            for row in cursorRow...scrollBottom {
                markRowDirty(row)
            }
        }
    }

    public func deleteCharacters(_ n: Int) {
        withLock {
            guard cursorRow < lines.count else { return }
            let count = min(n, size.columns - cursorColumn)
            lines[cursorRow].cells.removeSubrange(cursorColumn..<(cursorColumn + count))
            lines[cursorRow].cells.append(
                contentsOf: Array(repeating: TerminalCell.blank, count: count)
            )
            markRowDirty(cursorRow)
        }
    }

    public func insertCharacters(_ n: Int) {
        withLock {
            guard cursorRow < lines.count else { return }
            let count = min(n, size.columns - cursorColumn)
            let blanks = Array(repeating: TerminalCell.blank, count: count)
            lines[cursorRow].cells.insert(contentsOf: blanks, at: cursorColumn)
            lines[cursorRow].cells = Array(lines[cursorRow].cells.prefix(size.columns))
            markRowDirty(cursorRow)
        }
    }

    // MARK: - Snapshot (for rendering)

    /// Standard snapshot — returns lines, cursor, and dirty region info.
    /// Compatible with callers that only destructure (lines, cursorRow, cursorColumn).
    public func snapshot() -> (lines: [TerminalLine], cursorRow: Int, cursorColumn: Int) {
        os_unfair_lock_lock(&unfairLock)
        let result = (lines, cursorRow, cursorColumn)
        os_unfair_lock_unlock(&unfairLock)
        return result
    }

    /// Extended snapshot with dirty region tracking for optimized rendering.
    public func dirtySnapshot() -> (lines: [TerminalLine], cursorRow: Int, cursorColumn: Int, dirtyRows: Set<Int>, fullRedraw: Bool) {
        os_unfair_lock_lock(&unfairLock)
        let result = (lines, cursorRow, cursorColumn, dirtyRows, fullRedrawNeeded)
        os_unfair_lock_unlock(&unfairLock)
        return result
    }
}
