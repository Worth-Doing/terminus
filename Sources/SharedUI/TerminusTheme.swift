import SwiftUI
import SharedModels

// MARK: - ANSI Color Palette

public struct AnsiColorPalette: Sendable {
    public var black: Color
    public var red: Color
    public var green: Color
    public var yellow: Color
    public var blue: Color
    public var magenta: Color
    public var cyan: Color
    public var white: Color
    public var brightBlack: Color
    public var brightRed: Color
    public var brightGreen: Color
    public var brightYellow: Color
    public var brightBlue: Color
    public var brightMagenta: Color
    public var brightCyan: Color
    public var brightWhite: Color

    public init(
        black: Color, red: Color, green: Color, yellow: Color,
        blue: Color, magenta: Color, cyan: Color, white: Color,
        brightBlack: Color, brightRed: Color, brightGreen: Color, brightYellow: Color,
        brightBlue: Color, brightMagenta: Color, brightCyan: Color, brightWhite: Color
    ) {
        self.black = black
        self.red = red
        self.green = green
        self.yellow = yellow
        self.blue = blue
        self.magenta = magenta
        self.cyan = cyan
        self.white = white
        self.brightBlack = brightBlack
        self.brightRed = brightRed
        self.brightGreen = brightGreen
        self.brightYellow = brightYellow
        self.brightBlue = brightBlue
        self.brightMagenta = brightMagenta
        self.brightCyan = brightCyan
        self.brightWhite = brightWhite
    }

    public func color(forIndex index: UInt8) -> Color {
        switch index {
        case 0: black
        case 1: red
        case 2: green
        case 3: yellow
        case 4: blue
        case 5: magenta
        case 6: cyan
        case 7: white
        case 8: brightBlack
        case 9: brightRed
        case 10: brightGreen
        case 11: brightYellow
        case 12: brightBlue
        case 13: brightMagenta
        case 14: brightCyan
        case 15: brightWhite
        default: color256(index)
        }
    }

    private func color256(_ index: UInt8) -> Color {
        if index >= 16 && index <= 231 {
            // 6x6x6 color cube
            let adjusted = Int(index) - 16
            let r = Double((adjusted / 36) % 6) / 5.0
            let g = Double((adjusted / 6) % 6) / 5.0
            let b = Double(adjusted % 6) / 5.0
            return Color(red: r, green: g, blue: b)
        } else if index >= 232 {
            // Grayscale ramp
            let gray = Double(Int(index) - 232) * 10.0 / 255.0 + 8.0 / 255.0
            return Color(red: gray, green: gray, blue: gray)
        }
        return white
    }
}

// MARK: - Terminal Theme

public struct TerminusTheme: Sendable, Identifiable {
    public let id: String
    public let name: String
    public var backgroundColor: Color
    public var foregroundColor: Color
    public var selectionColor: Color
    public var cursorColor: Color
    public var ansiColors: AnsiColorPalette
    public var fontFamily: String
    public var fontSize: CGFloat
    public var vibrancy: Bool

    public init(
        id: String,
        name: String,
        backgroundColor: Color,
        foregroundColor: Color,
        selectionColor: Color,
        cursorColor: Color,
        ansiColors: AnsiColorPalette,
        fontFamily: String = "SF Mono",
        fontSize: CGFloat = 14,
        vibrancy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.selectionColor = selectionColor
        self.cursorColor = cursorColor
        self.ansiColors = ansiColors
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.vibrancy = vibrancy
    }

    /// Resolve a TerminalColor to a SwiftUI Color
    public func resolveColor(_ termColor: TerminalColor, isBackground: Bool = false) -> Color {
        switch termColor {
        case .default:
            isBackground ? backgroundColor : foregroundColor
        case .indexed(let index):
            ansiColors.color(forIndex: index)
        case .rgb(let r, let g, let b):
            Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}

// MARK: - Built-in Themes

extension TerminusTheme {
    public static let defaultDark = TerminusTheme(
        id: "defaultDark",
        name: "Terminus Dark",
        backgroundColor: Color(red: 0.08, green: 0.08, blue: 0.10),
        foregroundColor: Color(red: 0.90, green: 0.91, blue: 0.93),
        selectionColor: Color(red: 0.25, green: 0.35, blue: 0.55).opacity(0.6),
        cursorColor: Color(red: 0.55, green: 0.78, blue: 1.0),
        ansiColors: .terminusDark
    )

    public static let solarizedDark = TerminusTheme(
        id: "solarizedDark",
        name: "Solarized Dark",
        backgroundColor: Color(red: 0.0, green: 0.169, blue: 0.212),
        foregroundColor: Color(red: 0.514, green: 0.580, blue: 0.588),
        selectionColor: Color(red: 0.027, green: 0.212, blue: 0.259).opacity(0.6),
        cursorColor: Color(red: 0.514, green: 0.580, blue: 0.588),
        ansiColors: .solarized
    )

    public static let dracula = TerminusTheme(
        id: "dracula",
        name: "Dracula",
        backgroundColor: Color(red: 0.157, green: 0.165, blue: 0.212),
        foregroundColor: Color(red: 0.973, green: 0.973, blue: 0.949),
        selectionColor: Color(red: 0.263, green: 0.278, blue: 0.353).opacity(0.6),
        cursorColor: Color(red: 0.973, green: 0.973, blue: 0.949),
        ansiColors: .dracula
    )

    public static let allThemes: [TerminusTheme] = [
        .defaultDark, .solarizedDark, .dracula,
    ]

    public static func theme(withID id: String) -> TerminusTheme {
        allThemes.first { $0.id == id } ?? .defaultDark
    }
}

// MARK: - Built-in Color Palettes

extension AnsiColorPalette {
    public static let terminusDark = AnsiColorPalette(
        black:         Color(red: 0.15, green: 0.15, blue: 0.17),
        red:           Color(red: 0.91, green: 0.35, blue: 0.35),
        green:         Color(red: 0.35, green: 0.82, blue: 0.47),
        yellow:        Color(red: 0.95, green: 0.80, blue: 0.35),
        blue:          Color(red: 0.40, green: 0.60, blue: 0.95),
        magenta:       Color(red: 0.78, green: 0.45, blue: 0.90),
        cyan:          Color(red: 0.35, green: 0.82, blue: 0.85),
        white:         Color(red: 0.85, green: 0.86, blue: 0.88),
        brightBlack:   Color(red: 0.40, green: 0.40, blue: 0.43),
        brightRed:     Color(red: 1.00, green: 0.45, blue: 0.45),
        brightGreen:   Color(red: 0.45, green: 0.92, blue: 0.57),
        brightYellow:  Color(red: 1.00, green: 0.90, blue: 0.45),
        brightBlue:    Color(red: 0.55, green: 0.73, blue: 1.00),
        brightMagenta: Color(red: 0.88, green: 0.55, blue: 1.00),
        brightCyan:    Color(red: 0.45, green: 0.92, blue: 0.95),
        brightWhite:   Color(red: 0.95, green: 0.96, blue: 0.97)
    )

    public static let solarized = AnsiColorPalette(
        black:         Color(red: 0.027, green: 0.212, blue: 0.259),
        red:           Color(red: 0.863, green: 0.196, blue: 0.184),
        green:         Color(red: 0.522, green: 0.600, blue: 0.000),
        yellow:        Color(red: 0.710, green: 0.537, blue: 0.000),
        blue:          Color(red: 0.149, green: 0.545, blue: 0.824),
        magenta:       Color(red: 0.827, green: 0.212, blue: 0.510),
        cyan:          Color(red: 0.165, green: 0.631, blue: 0.596),
        white:         Color(red: 0.933, green: 0.910, blue: 0.835),
        brightBlack:   Color(red: 0.000, green: 0.169, blue: 0.212),
        brightRed:     Color(red: 0.796, green: 0.294, blue: 0.086),
        brightGreen:   Color(red: 0.345, green: 0.431, blue: 0.459),
        brightYellow:  Color(red: 0.396, green: 0.482, blue: 0.514),
        brightBlue:    Color(red: 0.514, green: 0.580, blue: 0.588),
        brightMagenta: Color(red: 0.424, green: 0.443, blue: 0.769),
        brightCyan:    Color(red: 0.576, green: 0.631, blue: 0.631),
        brightWhite:   Color(red: 0.992, green: 0.965, blue: 0.890)
    )

    public static let dracula = AnsiColorPalette(
        black:         Color(red: 0.263, green: 0.278, blue: 0.353),
        red:           Color(red: 1.000, green: 0.333, blue: 0.333),
        green:         Color(red: 0.314, green: 0.980, blue: 0.482),
        yellow:        Color(red: 0.945, green: 0.980, blue: 0.549),
        blue:          Color(red: 0.741, green: 0.576, blue: 0.976),
        magenta:       Color(red: 1.000, green: 0.475, blue: 0.776),
        cyan:          Color(red: 0.545, green: 0.914, blue: 0.992),
        white:         Color(red: 0.973, green: 0.973, blue: 0.949),
        brightBlack:   Color(red: 0.384, green: 0.447, blue: 0.643),
        brightRed:     Color(red: 1.000, green: 0.474, blue: 0.474),
        brightGreen:   Color(red: 0.455, green: 1.000, blue: 0.592),
        brightYellow:  Color(red: 0.945, green: 1.000, blue: 0.651),
        brightBlue:    Color(red: 0.827, green: 0.694, blue: 1.000),
        brightMagenta: Color(red: 1.000, green: 0.600, blue: 0.850),
        brightCyan:    Color(red: 0.651, green: 0.953, blue: 1.000),
        brightWhite:   Color(red: 1.000, green: 1.000, blue: 1.000)
    )
}
