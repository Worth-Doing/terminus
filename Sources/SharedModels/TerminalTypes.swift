import Foundation

// MARK: - Identifiers

public typealias SessionID = String
public typealias PanelID = String

// MARK: - Terminal Size

public struct TerminalSize: Sendable, Codable, Hashable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    public static let default80x24 = TerminalSize(columns: 80, rows: 24)
}

// MARK: - Cursor Style

public enum CursorStyle: String, Sendable, Codable, CaseIterable {
    case block
    case underline
    case bar
}

// MARK: - Terminal Color

public enum TerminalColor: Sendable, Equatable, Hashable, Codable {
    case `default`
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

// MARK: - Underline Style

public enum UnderlineStyle: Sendable, Equatable, Hashable, Codable {
    case none
    case single
    case double
    case curly
}

// MARK: - Cell Attributes

public struct CellAttributes: Sendable, Equatable, Hashable, Codable {
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var bold: Bool
    public var italic: Bool
    public var underline: UnderlineStyle
    public var strikethrough: Bool
    public var inverse: Bool
    public var hidden: Bool
    public var blink: Bool
    public var faint: Bool

    public init(
        foreground: TerminalColor = .default,
        background: TerminalColor = .default,
        bold: Bool = false,
        italic: Bool = false,
        underline: UnderlineStyle = .none,
        strikethrough: Bool = false,
        inverse: Bool = false,
        hidden: Bool = false,
        blink: Bool = false,
        faint: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverse = inverse
        self.hidden = hidden
        self.blink = blink
        self.faint = faint
    }

    public static let `default` = CellAttributes()
}

// MARK: - Terminal Cell

public struct TerminalCell: Sendable, Equatable, Codable {
    public var character: Character
    public var width: UInt8
    public var attributes: CellAttributes

    public init(
        character: Character = " ",
        width: UInt8 = 1,
        attributes: CellAttributes = .default
    ) {
        self.character = character
        self.width = width
        self.attributes = attributes
    }

    public static let blank = TerminalCell()
}

// Make Character Codable
extension Character: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let char = string.first, string.count == 1 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected single character"
            )
        }
        self = char
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(self))
    }
}

// MARK: - Terminal Line

public struct TerminalLine: Sendable, Equatable {
    public var cells: [TerminalCell]
    public var wrapped: Bool

    public init(cells: [TerminalCell], wrapped: Bool = false) {
        self.cells = cells
        self.wrapped = wrapped
    }

    public init(columns: Int) {
        self.cells = Array(repeating: .blank, count: columns)
        self.wrapped = false
    }
}
