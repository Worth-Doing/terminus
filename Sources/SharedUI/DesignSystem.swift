import SwiftUI

// MARK: - Terminus Design Tokens

public enum TerminusDesign {
    // MARK: Spacing
    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 12
    public static let spacingLG: CGFloat = 16
    public static let spacingXL: CGFloat = 24

    // MARK: Corner Radius
    public static let radiusSM: CGFloat = 4
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 12

    // MARK: Divider
    public static let dividerWidth: CGFloat = 1
    public static let dividerHitArea: CGFloat = 6

    // MARK: Panel
    public static let panelMinWidth: CGFloat = 120
    public static let panelMinHeight: CGFloat = 80

    // MARK: Sidebar
    public static let sidebarWidth: CGFloat = 260

    // MARK: Animation
    public static let animationFast: Double = 0.15
    public static let animationNormal: Double = 0.25
    public static let animationSlow: Double = 0.4
}

// MARK: - Fonts

extension Font {
    public static func terminusMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, design: .monospaced).weight(weight)
    }

    public static func terminusUI(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, design: .default).weight(weight)
    }
}

// MARK: - UI Colors (non-terminal)

public enum TerminusColors {
    public static let panelBorder = Color.white.opacity(0.08)
    public static let panelBorderFocused = Color.blue.opacity(0.5)
    public static let divider = Color.white.opacity(0.06)
    public static let sidebarBackground = Color(red: 0.10, green: 0.10, blue: 0.12)
    public static let toolbarBackground = Color(red: 0.12, green: 0.12, blue: 0.14)
    public static let overlayBackground = Color.black.opacity(0.6)
    public static let accentPrimary = Color(red: 0.40, green: 0.65, blue: 1.0)
    public static let accentSuccess = Color(red: 0.35, green: 0.82, blue: 0.47)
    public static let accentWarning = Color(red: 0.95, green: 0.80, blue: 0.35)
    public static let accentError = Color(red: 0.91, green: 0.35, blue: 0.35)
    public static let textPrimary = Color(red: 0.90, green: 0.91, blue: 0.93)
    public static let textSecondary = Color(red: 0.55, green: 0.56, blue: 0.60)
    public static let textTertiary = Color(red: 0.35, green: 0.36, blue: 0.40)
}

// MARK: - Keyboard Shortcuts

public enum TerminusKeys {
    public static let splitHorizontal = KeyboardShortcut("d", modifiers: .command)
    public static let splitVertical = KeyboardShortcut("d", modifiers: [.command, .shift])
    public static let closePanel = KeyboardShortcut("w", modifiers: .command)
    public static let newTab = KeyboardShortcut("t", modifiers: .command)
    public static let settings = KeyboardShortcut(",", modifiers: .command)
    public static let commandPalette = KeyboardShortcut("p", modifiers: [.command, .shift])
    public static let savedCommands = KeyboardShortcut("s", modifiers: [.command, .shift])
    public static let semanticSearch = KeyboardShortcut("f", modifiers: [.command, .shift])
}
