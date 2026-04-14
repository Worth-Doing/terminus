import XCTest
@testable import TerminalEmulator
import SharedModels

final class TerminalBufferTests: XCTestCase {

    func testInitializeWithSize() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        let snapshot = buffer.snapshot()
        XCTAssertEqual(buffer.size.columns, 80)
        XCTAssertEqual(buffer.size.rows, 24)
        XCTAssertEqual(snapshot.lines.count, 24)
        XCTAssertEqual(snapshot.cursorRow, 0)
        XCTAssertEqual(snapshot.cursorColumn, 0)
    }

    func testWriteCharacterAdvancesCursor() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.writeCharacter("A")
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.cursorColumn, 1)
        XCTAssertEqual(snapshot.lines[0].cells[0].character, "A")
    }

    func testLineFeedMovesCursorDown() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.lineFeed()
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.cursorRow, 1)
    }

    func testCarriageReturnResetsColumn() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.writeCharacter("A")
        buffer.writeCharacter("B")
        buffer.carriageReturn()
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.cursorColumn, 0)
    }

    func testEraseInDisplayClearsAll() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.writeCharacter("X")
        buffer.eraseInDisplay(mode: 2)
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.lines[0].cells[0].character, " ")
    }

    func testCursorPositioning() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.setCursorPosition(row: 5, column: 10)
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.cursorRow, 5)
        XCTAssertEqual(snapshot.cursorColumn, 10)
    }

    func testResizeAdjustsBuffer() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.resize(TerminalSize(columns: 120, rows: 40))
        let snapshot = buffer.snapshot()
        XCTAssertEqual(buffer.size.columns, 120)
        XCTAssertEqual(buffer.size.rows, 40)
        XCTAssertEqual(snapshot.lines.count, 40)
    }

    func testAlternateScreenBuffer() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 80, rows: 24))
        buffer.writeCharacter("X")
        buffer.enableAlternateScreen()
        let snap1 = buffer.snapshot()
        XCTAssertEqual(snap1.lines[0].cells[0].character, " ") // Alternate is blank
        XCTAssertTrue(buffer.alternateScreenActive)

        buffer.disableAlternateScreen()
        let snap2 = buffer.snapshot()
        XCTAssertEqual(snap2.lines[0].cells[0].character, "X") // Restored
        XCTAssertFalse(buffer.alternateScreenActive)
    }

    func testScrollbackOnLineFeed() {
        let buffer = TerminalBuffer(size: TerminalSize(columns: 10, rows: 3), scrollbackLimit: 100)
        // Fill all 3 rows
        for char in ["A", "B", "C"] as [Character] {
            buffer.writeCharacter(char)
            buffer.carriageReturn()
            buffer.lineFeed()
        }
        // One more LF should scroll
        buffer.writeCharacter("D")
        buffer.carriageReturn()
        buffer.lineFeed()

        XCTAssertFalse(buffer.scrollbackLines.isEmpty)
    }
}
