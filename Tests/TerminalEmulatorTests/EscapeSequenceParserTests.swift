import XCTest
@testable import TerminalEmulator
import SharedModels

final class EscapeSequenceParserTests: XCTestCase {

    private func makeParser(columns: Int = 80, rows: Int = 24) -> EscapeSequenceParser {
        let buffer = TerminalBuffer(size: TerminalSize(columns: columns, rows: rows))
        return EscapeSequenceParser(buffer: buffer)
    }

    // MARK: - Basic Text

    func testPlainTextWritesToBuffer() {
        let parser = makeParser()
        parser.feed(Data("Hello".utf8))
        let snapshot = parser.buffer.snapshot()
        let text = String(snapshot.lines[0].cells.prefix(5).map(\.character))
        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(snapshot.cursorColumn, 5)
    }

    func testNewlineMovesToNextLine() {
        let parser = makeParser()
        parser.feed(Data("A\r\nB".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.lines[0].cells[0].character, "A")
        XCTAssertEqual(snapshot.lines[1].cells[0].character, "B")
    }

    // MARK: - CSI Sequences

    func testCursorPositionCSI() {
        let parser = makeParser()
        // ESC [ 5 ; 10 H -> cursor to row 5, column 10 (1-based)
        parser.feed(Data([0x1B, 0x5B, 0x35, 0x3B, 0x31, 0x30, 0x48]))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.cursorRow, 4)   // 0-based
        XCTAssertEqual(snapshot.cursorColumn, 9)
    }

    func testCursorMoveUp() {
        let parser = makeParser()
        parser.buffer.setCursorPosition(row: 5, column: 0)
        // ESC [ 3 A -> cursor up 3
        parser.feed(Data([0x1B, 0x5B, 0x33, 0x41]))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.cursorRow, 2)
    }

    func testEraseDisplay() {
        let parser = makeParser()
        parser.feed(Data("test".utf8))
        // ESC [ 2 J -> clear entire display
        parser.feed(Data([0x1B, 0x5B, 0x32, 0x4A]))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.lines[0].cells[0].character, " ")
    }

    // MARK: - SGR (Colors and Attributes)

    func testBoldAttribute() {
        let parser = makeParser()
        // ESC [ 1 m -> bold on
        parser.feed(Data([0x1B, 0x5B, 0x31, 0x6D]))
        parser.feed(Data("X".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertTrue(snapshot.lines[0].cells[0].attributes.bold)
    }

    func testForegroundColor() {
        let parser = makeParser()
        // ESC [ 31 m -> red foreground
        parser.feed(Data([0x1B, 0x5B, 0x33, 0x31, 0x6D]))
        parser.feed(Data("R".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.lines[0].cells[0].attributes.foreground, .indexed(1))
    }

    func test256Color() {
        let parser = makeParser()
        // ESC [ 38;5;208 m -> 256-color orange foreground
        parser.feed(Data("\u{1B}[38;5;208m".utf8))
        parser.feed(Data("O".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.lines[0].cells[0].attributes.foreground, .indexed(208))
    }

    func testTrueColor() {
        let parser = makeParser()
        // ESC [ 38;2;255;128;0 m -> RGB foreground
        parser.feed(Data("\u{1B}[38;2;255;128;0m".utf8))
        parser.feed(Data("T".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.lines[0].cells[0].attributes.foreground, .rgb(255, 128, 0))
    }

    func testResetAttributes() {
        let parser = makeParser()
        parser.feed(Data("\u{1B}[1;31m".utf8))  // bold red
        parser.feed(Data("A".utf8))
        parser.feed(Data("\u{1B}[0m".utf8))      // reset
        parser.feed(Data("B".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertTrue(snapshot.lines[0].cells[0].attributes.bold)
        XCTAssertFalse(snapshot.lines[0].cells[1].attributes.bold)
        XCTAssertEqual(snapshot.lines[0].cells[1].attributes.foreground, .default)
    }

    // MARK: - Alternate Screen

    func testAlternateScreenMode() {
        let parser = makeParser()
        parser.feed(Data("visible".utf8))
        // ESC [ ? 1049 h -> enable alternate screen
        parser.feed(Data("\u{1B}[?1049h".utf8))
        let snap1 = parser.buffer.snapshot()
        XCTAssertEqual(snap1.lines[0].cells[0].character, " ") // alternate is blank

        // ESC [ ? 1049 l -> disable alternate screen
        parser.feed(Data("\u{1B}[?1049l".utf8))
        let snap2 = parser.buffer.snapshot()
        XCTAssertEqual(snap2.lines[0].cells[0].character, "v") // restored
    }

    // MARK: - UTF-8

    func testUTF8Characters() {
        let parser = makeParser()
        // Simple UTF-8 multibyte characters
        parser.feed(Data("Hi".utf8))
        let snapshot = parser.buffer.snapshot()
        XCTAssertEqual(snapshot.cursorColumn, 2)
        // Should not crash on multibyte sequences
        parser.feed(Data([0xC3, 0xA9])) // é (2-byte UTF-8)
        let snap2 = parser.buffer.snapshot()
        XCTAssertEqual(snap2.cursorColumn, 3)
    }

    // MARK: - Shell Integration (OSC 133)

    func testOSC133PromptStart() {
        let parser = makeParser()
        var receivedEvent: ShellIntegrationEvent?
        parser.shellIntegration.onEvent = { event in
            receivedEvent = event
        }

        // OSC 133;A BEL
        parser.feed(Data("\u{1B}]133;A\u{07}".utf8))

        if case .promptStart = receivedEvent {
            // Expected
        } else {
            XCTFail("Expected promptStart event, got \(String(describing: receivedEvent))")
        }
    }

    func testOSC133CommandFinished() {
        let parser = makeParser()
        var receivedEvent: ShellIntegrationEvent?
        parser.shellIntegration.onEvent = { event in
            receivedEvent = event
        }

        // OSC 133;D;0 BEL (exit code 0)
        parser.feed(Data("\u{1B}]133;D;0\u{07}".utf8))

        if case .commandFinished(let code) = receivedEvent {
            XCTAssertEqual(code, 0)
        } else {
            XCTFail("Expected commandFinished event")
        }
    }

    func testOSC7DirectoryChange() {
        let parser = makeParser()
        var receivedEvent: ShellIntegrationEvent?
        parser.shellIntegration.onEvent = { event in
            receivedEvent = event
        }

        // OSC 7;file://localhost/Users/test BEL
        parser.feed(Data("\u{1B}]7;file://localhost/Users/test\u{07}".utf8))

        if case .directoryChanged(let path) = receivedEvent {
            XCTAssertEqual(path, "/Users/test")
        } else {
            XCTFail("Expected directoryChanged event")
        }
    }

    // MARK: - Window Title

    func testOSC0WindowTitle() {
        let parser = makeParser()
        parser.feed(Data("\u{1B}]0;My Terminal\u{07}".utf8))
        XCTAssertEqual(parser.windowTitle, "My Terminal")
    }
}
