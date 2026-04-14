import Foundation
import SharedModels

// MARK: - Parser State

public enum ParserState: Sendable {
    case ground
    case escape
    case escapeIntermediate
    case csiEntry
    case csiParam
    case csiIntermediate
    case oscString
    case dcsEntry
    case dcsPassthrough
}

// MARK: - Escape Sequence Parser

public final class EscapeSequenceParser: @unchecked Sendable {
    public let buffer: TerminalBuffer

    private var state: ParserState = .ground
    private var csiParams: [Int] = []
    private var currentParam: String = ""
    private var intermediateChars: [UInt8] = []
    private var oscString: String = ""

    // UTF-8 decoding state
    private var utf8Buffer: [UInt8] = []
    private var utf8Remaining: Int = 0

    // Shell integration
    public let shellIntegration = ShellIntegrationState()

    public init(buffer: TerminalBuffer) {
        self.buffer = buffer
    }

    // MARK: - Feed Data

    public func feed(_ data: Data) {
        for byte in data {
            processByte(byte)
        }
    }

    // MARK: - Byte Processing

    private func processByte(_ byte: UInt8) {
        // Handle UTF-8 multi-byte sequences
        if utf8Remaining > 0 {
            if byte & 0xC0 == 0x80 {
                utf8Buffer.append(byte)
                utf8Remaining -= 1
                if utf8Remaining == 0 {
                    if let str = String(bytes: utf8Buffer, encoding: .utf8),
                       let char = str.first {
                        buffer.writeCharacter(char)
                    }
                    utf8Buffer.removeAll()
                }
                return
            } else {
                // Invalid continuation, reset
                utf8Buffer.removeAll()
                utf8Remaining = 0
            }
        }

        // Check for UTF-8 start byte
        if state == .ground && byte >= 0xC0 && byte < 0xFE {
            utf8Buffer = [byte]
            if byte & 0xE0 == 0xC0 { utf8Remaining = 1 }
            else if byte & 0xF0 == 0xE0 { utf8Remaining = 2 }
            else if byte & 0xF8 == 0xF0 { utf8Remaining = 3 }
            else { utf8Buffer.removeAll(); utf8Remaining = 0 }
            return
        }

        switch state {
        case .ground:
            processGround(byte)
        case .escape:
            processEscape(byte)
        case .escapeIntermediate:
            processEscapeIntermediate(byte)
        case .csiEntry:
            processCSIEntry(byte)
        case .csiParam:
            processCSIParam(byte)
        case .csiIntermediate:
            processCSIIntermediate(byte)
        case .oscString:
            processOSCString(byte)
        case .dcsEntry:
            processDCSEntry(byte)
        case .dcsPassthrough:
            processDCSPassthrough(byte)
        }
    }

    // MARK: - Ground State

    private func processGround(_ byte: UInt8) {
        switch byte {
        case 0x00...0x06, 0x0E...0x1A, 0x1C...0x1F:
            // Ignored control characters
            break
        case 0x07: // BEL
            // Bell (could trigger sound)
            break
        case 0x08: // BS
            buffer.backspace()
        case 0x09: // TAB
            buffer.tab()
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            buffer.lineFeed()
        case 0x0D: // CR
            buffer.carriageReturn()
        case 0x1B: // ESC
            state = .escape
        case 0x20...0x7E: // Printable ASCII
            buffer.writeCharacter(Character(UnicodeScalar(byte)))
        case 0x7F: // DEL
            break
        default:
            break
        }
    }

    // MARK: - Escape State

    private func processEscape(_ byte: UInt8) {
        switch byte {
        case 0x5B: // [  -> CSI
            state = .csiEntry
            csiParams = []
            currentParam = ""
            intermediateChars = []
        case 0x5D: // ]  -> OSC
            state = .oscString
            oscString = ""
        case 0x50: // P  -> DCS
            state = .dcsEntry
        case 0x4D: // M  -> Reverse line feed
            buffer.reverseLineFeed()
            state = .ground
        case 0x37: // 7  -> Save cursor (DECSC)
            // Save cursor position
            state = .ground
        case 0x38: // 8  -> Restore cursor (DECRC)
            // Restore cursor position
            state = .ground
        case 0x63: // c  -> Full reset (RIS)
            buffer.eraseInDisplay(mode: 2)
            buffer.setCursorPosition(row: 0, column: 0)
            buffer.resetAttributes()
            state = .ground
        case 0x44: // D  -> Index (IND) - line feed
            buffer.lineFeed()
            state = .ground
        case 0x45: // E  -> Next line (NEL)
            buffer.carriageReturn()
            buffer.lineFeed()
            state = .ground
        case 0x48: // H  -> Tab set (HTS)
            state = .ground
        case 0x28, 0x29, 0x2A, 0x2B: // ( ) * + -> Character set designation
            state = .escapeIntermediate
        case 0x20...0x2F: // Intermediate bytes
            intermediateChars = [byte]
            state = .escapeIntermediate
        default:
            state = .ground
        }
    }

    // MARK: - Escape Intermediate

    private func processEscapeIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x20...0x2F:
            intermediateChars.append(byte)
        case 0x30...0x7E:
            // Final character, ignore charset designation for now
            state = .ground
        default:
            state = .ground
        }
    }

    // MARK: - CSI Entry

    private func processCSIEntry(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39: // Digit
            currentParam = String(UnicodeScalar(byte))
            state = .csiParam
        case 0x3B: // ;  -> Parameter separator
            csiParams.append(0)
            state = .csiParam
        case 0x3C...0x3F: // < = > ?  -> Private mode prefix
            intermediateChars = [byte]
            state = .csiParam
        case 0x20...0x2F: // Intermediate
            intermediateChars.append(byte)
            state = .csiIntermediate
        case 0x40...0x7E: // Final byte -> execute with no params
            executeCSI(byte)
        default:
            state = .ground
        }
    }

    // MARK: - CSI Param

    private func processCSIParam(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39: // Digit
            currentParam.append(Character(UnicodeScalar(byte)))
        case 0x3B: // ;  -> Next parameter
            csiParams.append(Int(currentParam) ?? 0)
            currentParam = ""
        case 0x20...0x2F: // Intermediate
            if !currentParam.isEmpty {
                csiParams.append(Int(currentParam) ?? 0)
                currentParam = ""
            }
            intermediateChars.append(byte)
            state = .csiIntermediate
        case 0x40...0x7E: // Final byte
            if !currentParam.isEmpty {
                csiParams.append(Int(currentParam) ?? 0)
                currentParam = ""
            }
            executeCSI(byte)
        case 0x3A: // : -> Sub-parameter separator (used in SGR for underline colors etc.)
            currentParam.append(":")
        default:
            state = .ground
        }
    }

    // MARK: - CSI Intermediate

    private func processCSIIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x20...0x2F:
            intermediateChars.append(byte)
        case 0x40...0x7E:
            if !currentParam.isEmpty {
                csiParams.append(Int(currentParam) ?? 0)
                currentParam = ""
            }
            executeCSI(byte)
        default:
            state = .ground
        }
    }

    // MARK: - Execute CSI

    private func executeCSI(_ finalByte: UInt8) {
        let isPrivate = intermediateChars.first == 0x3F // ?

        let p = csiParams
        let n = p.first ?? 1

        switch finalByte {
        case 0x41: // A -> Cursor Up
            buffer.moveCursorUp(max(1, n))
        case 0x42: // B -> Cursor Down
            buffer.moveCursorDown(max(1, n))
        case 0x43: // C -> Cursor Forward
            buffer.moveCursorForward(max(1, n))
        case 0x44: // D -> Cursor Backward
            buffer.moveCursorBackward(max(1, n))
        case 0x45: // E -> Cursor Next Line
            buffer.moveCursorDown(max(1, n))
            buffer.carriageReturn()
        case 0x46: // F -> Cursor Previous Line
            buffer.moveCursorUp(max(1, n))
            buffer.carriageReturn()
        case 0x47: // G -> Cursor Horizontal Absolute
            buffer.setCursorPosition(row: buffer.cursorRow, column: max(0, n - 1))
        case 0x48, 0x66: // H, f -> Cursor Position
            let row = max(1, p.count > 0 ? (p[0] == 0 ? 1 : p[0]) : 1) - 1
            let col = max(1, p.count > 1 ? (p[1] == 0 ? 1 : p[1]) : 1) - 1
            buffer.setCursorPosition(row: row, column: col)
        case 0x4A: // J -> Erase in Display
            buffer.eraseInDisplay(mode: p.first ?? 0)
        case 0x4B: // K -> Erase in Line
            buffer.eraseInLine(mode: p.first ?? 0)
        case 0x4C: // L -> Insert Lines
            buffer.insertLines(max(1, n))
        case 0x4D: // M -> Delete Lines
            buffer.deleteLines(max(1, n))
        case 0x50: // P -> Delete Characters
            buffer.deleteCharacters(max(1, n))
        case 0x40: // @ -> Insert Characters
            buffer.insertCharacters(max(1, n))
        case 0x64: // d -> Cursor Vertical Absolute
            buffer.setCursorPosition(row: max(0, n - 1), column: buffer.cursorColumn)
        case 0x6D: // m -> SGR (Select Graphic Rendition)
            executeSGR(p.isEmpty ? [0] : p)
        case 0x72: // r -> DECSTBM (Set Scrolling Region)
            let top = max(1, p.count > 0 ? p[0] : 1) - 1
            let bottom = (p.count > 1 ? p[1] : buffer.size.rows) - 1
            buffer.setScrollRegion(top: top, bottom: bottom)
        case 0x68: // h -> Set Mode
            if isPrivate {
                setDecPrivateMode(p, enabled: true)
            }
        case 0x6C: // l -> Reset Mode
            if isPrivate {
                setDecPrivateMode(p, enabled: false)
            }
        case 0x6E: // n -> Device Status Report
            // Respond with cursor position if n == 6
            break
        case 0x74: // t -> Window manipulation
            break
        case 0x53: // S -> Scroll Up
            for _ in 0..<max(1, n) {
                buffer.lineFeed()
            }
        case 0x54: // T -> Scroll Down
            for _ in 0..<max(1, n) {
                buffer.reverseLineFeed()
            }
        default:
            break
        }

        state = .ground
    }

    // MARK: - SGR (Select Graphic Rendition)

    private func executeSGR(_ params: [Int]) {
        var attrs = buffer.attributes
        var i = 0

        while i < params.count {
            let p = params[i]

            switch p {
            case 0:
                attrs = .default
            case 1:
                attrs.bold = true
            case 2:
                attrs.faint = true
            case 3:
                attrs.italic = true
            case 4:
                attrs.underline = .single
            case 5, 6:
                attrs.blink = true
            case 7:
                attrs.inverse = true
            case 8:
                attrs.hidden = true
            case 9:
                attrs.strikethrough = true
            case 21:
                attrs.underline = .double
            case 22:
                attrs.bold = false
                attrs.faint = false
            case 23:
                attrs.italic = false
            case 24:
                attrs.underline = .none
            case 25:
                attrs.blink = false
            case 27:
                attrs.inverse = false
            case 28:
                attrs.hidden = false
            case 29:
                attrs.strikethrough = false
            case 30...37:
                attrs.foreground = .indexed(UInt8(p - 30))
            case 38:
                // Extended foreground color
                if let (color, advance) = parseExtendedColor(params, from: i + 1) {
                    attrs.foreground = color
                    i += advance
                }
            case 39:
                attrs.foreground = .default
            case 40...47:
                attrs.background = .indexed(UInt8(p - 40))
            case 48:
                // Extended background color
                if let (color, advance) = parseExtendedColor(params, from: i + 1) {
                    attrs.background = color
                    i += advance
                }
            case 49:
                attrs.background = .default
            case 90...97:
                attrs.foreground = .indexed(UInt8(p - 90 + 8))
            case 100...107:
                attrs.background = .indexed(UInt8(p - 100 + 8))
            default:
                break
            }

            i += 1
        }

        buffer.setAttributes(attrs)
    }

    private func parseExtendedColor(_ params: [Int], from index: Int) -> (TerminalColor, Int)? {
        guard index < params.count else { return nil }

        switch params[index] {
        case 5: // 256-color
            guard index + 1 < params.count else { return nil }
            return (.indexed(UInt8(clamping: params[index + 1])), 2)
        case 2: // 24-bit RGB
            guard index + 3 < params.count else { return nil }
            let r = UInt8(clamping: params[index + 1])
            let g = UInt8(clamping: params[index + 2])
            let b = UInt8(clamping: params[index + 3])
            return (.rgb(r, g, b), 4)
        default:
            return nil
        }
    }

    // MARK: - DEC Private Modes

    private func setDecPrivateMode(_ params: [Int], enabled: Bool) {
        for mode in params {
            switch mode {
            case 1: // DECCKM - Cursor keys mode
                buffer.applicationCursorKeys = enabled
            case 25: // DECTCEM - Text cursor enable
                // Show/hide cursor
                break
            case 47, 1047: // Alternate screen buffer
                if enabled { buffer.enableAlternateScreen() }
                else { buffer.disableAlternateScreen() }
            case 1049: // Alternate screen + save/restore cursor
                if enabled { buffer.enableAlternateScreen() }
                else { buffer.disableAlternateScreen() }
            case 2004: // Bracketed paste mode
                buffer.bracketedPasteMode = enabled
            default:
                break
            }
        }
    }

    // MARK: - OSC String

    private func processOSCString(_ byte: UInt8) {
        switch byte {
        case 0x07: // BEL -> Terminate OSC
            executeOSC()
            state = .ground
        case 0x1B: // ESC -> Could be ST (ESC \)
            // Check next byte for backslash
            state = .ground
            executeOSC()
        case 0x9C: // ST (8-bit)
            executeOSC()
            state = .ground
        default:
            oscString.append(Character(UnicodeScalar(byte)))
        }
    }

    private func executeOSC() {
        // Handle OSC without semicolons (e.g. plain sequences)
        guard let semicolonIndex = oscString.firstIndex(of: ";") else {
            // Could be a bare command like "133" without value
            if let code = Int(oscString) {
                handleOSCCode(code, value: "")
            }
            return
        }

        let codeStr = String(oscString[oscString.startIndex..<semicolonIndex])
        let value = String(oscString[oscString.index(after: semicolonIndex)...])

        if let code = Int(codeStr) {
            handleOSCCode(code, value: value)
        }
    }

    private func handleOSCCode(_ code: Int, value: String) {
        switch code {
        case 0, 2:
            // Window title
            windowTitle = value
        case 1:
            // Icon title (usually same as window title)
            break
        case 7:
            // Current working directory: file://hostname/path
            if let url = URL(string: value),
               url.scheme == "file" {
                shellIntegration.handleEvent(.directoryChanged(path: url.path))
            }
        case 133:
            // FinalTerm / Shell integration protocol
            parseOSC133(value)
        default:
            break
        }
    }

    private func parseOSC133(_ value: String) {
        // OSC 133 format: "X" or "X;param"
        guard let first = value.first else { return }

        switch first {
        case "A":
            // Prompt start
            shellIntegration.setPromptRow(buffer.cursorRow)
            shellIntegration.handleEvent(.promptStart)
        case "B":
            // Command start — the command text is between A and B
            // Extract command from the buffer between prompt start and current position
            let command = extractCurrentCommand()
            shellIntegration.handleEvent(.commandStart(command: command))
        case "C":
            // Command output start
            shellIntegration.handleEvent(.commandOutputStart)
        case "D":
            // Command finished — exit code follows semicolon
            let parts = value.split(separator: ";", maxSplits: 1)
            let exitCode: Int32
            if parts.count > 1, let code = Int32(parts[1]) {
                exitCode = code
            } else {
                exitCode = 0
            }
            shellIntegration.handleEvent(.commandFinished(exitCode: exitCode))
        default:
            break
        }
    }

    private func extractCurrentCommand() -> String? {
        // Try to extract the command text from the buffer
        // between the prompt row and the current cursor position
        guard let promptRow = shellIntegration.promptRow else { return nil }

        let snapshot = buffer.snapshot()
        var commandText = ""

        for row in promptRow...min(snapshot.cursorRow, snapshot.lines.count - 1) {
            let line = snapshot.lines[row]
            var lineText = ""
            for cell in line.cells {
                if cell.character != " " || !lineText.isEmpty {
                    lineText.append(cell.character)
                }
            }
            lineText = lineText.trimmingCharacters(in: .whitespaces)
            if !lineText.isEmpty {
                if !commandText.isEmpty { commandText += " " }
                commandText += lineText
            }
        }

        // The command is typically after the prompt symbol ($ % # >)
        // Try to find and strip the prompt prefix
        if let lastPrompt = commandText.lastIndex(where: { "$ % # >".contains($0) }) {
            let afterPrompt = commandText.index(after: lastPrompt)
            if afterPrompt < commandText.endIndex {
                let cmd = String(commandText[afterPrompt...]).trimmingCharacters(in: .whitespaces)
                return cmd.isEmpty ? nil : cmd
            }
        }

        return commandText.isEmpty ? nil : commandText
    }

    /// Window title set by OSC 0/2
    public private(set) var windowTitle: String?

    // MARK: - DCS

    private func processDCSEntry(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .ground
        default:
            state = .dcsPassthrough
        }
    }

    private func processDCSPassthrough(_ byte: UInt8) {
        switch byte {
        case 0x1B: // ESC -> End of DCS
            state = .ground
        case 0x9C: // ST
            state = .ground
        default:
            break
        }
    }
}
