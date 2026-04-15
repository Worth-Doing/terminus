import SwiftUI

// MARK: - Terminus Design Tokens

public enum TerminusDesign {
    // MARK: Spacing
    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 12
    public static let spacingLG: CGFloat = 16
    public static let spacingXL: CGFloat = 24
    public static let spacingXXL: CGFloat = 32

    // MARK: Corner Radius
    public static let radiusSM: CGFloat = 4
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 12
    public static let radiusXL: CGFloat = 16
    public static let radiusXXL: CGFloat = 20

    // MARK: Divider
    public static let dividerWidth: CGFloat = 1
    public static let dividerHitArea: CGFloat = 6

    // MARK: Panel
    public static let panelMinWidth: CGFloat = 120
    public static let panelMinHeight: CGFloat = 80

    // MARK: Sidebar
    public static let sidebarWidth: CGFloat = 260

    // MARK: Animation — Timing
    public static let animationFast: Double = 0.15
    public static let animationNormal: Double = 0.25
    public static let animationSlow: Double = 0.4

    // MARK: Animation — Springs
    public static let springDefault = Animation.spring(response: 0.35, dampingFraction: 0.82)
    public static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.72)
    public static let springSnappy = Animation.spring(response: 0.25, dampingFraction: 0.88)
    public static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.85)

    // MARK: Shadows
    public enum Shadow {
        case soft, medium, strong, glow

        public var color: Color {
            switch self {
            case .soft: Color.black.opacity(0.12)
            case .medium: Color.black.opacity(0.20)
            case .strong: Color.black.opacity(0.35)
            case .glow: TerminusAccent.primary.opacity(0.25)
            }
        }

        public var radius: CGFloat {
            switch self {
            case .soft: 8
            case .medium: 16
            case .strong: 24
            case .glow: 12
            }
        }

        public var y: CGFloat {
            switch self {
            case .soft: 2
            case .medium: 4
            case .strong: 8
            case .glow: 0
            }
        }
    }
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

// MARK: - Accent Colors (theme-independent)

public enum TerminusAccent {
    public static let primary = Color(red: 0.25, green: 0.48, blue: 0.85)
    public static let success = Color(red: 0.25, green: 0.72, blue: 0.38)
    public static let warning = Color(red: 0.85, green: 0.65, blue: 0.15)
    public static let error = Color(red: 0.85, green: 0.25, blue: 0.25)
}

// MARK: - UI Colors (resolved from active theme)

public enum TerminusColors {
    public static let panelBorder = Color.white.opacity(0.08)
    public static let panelBorderFocused = Color.blue.opacity(0.5)
    public static let divider = Color.white.opacity(0.06)
    public static let sidebarBackground = Color(red: 0.10, green: 0.10, blue: 0.12)
    public static let toolbarBackground = Color(red: 0.12, green: 0.12, blue: 0.14)
    public static let overlayBackground = Color.black.opacity(0.6)
    public static let accentPrimary = TerminusAccent.primary
    public static let accentSuccess = TerminusAccent.success
    public static let accentWarning = TerminusAccent.warning
    public static let accentError = TerminusAccent.error
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

// MARK: - Glass Panel Modifier

public struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadowStyle: TerminusDesign.Shadow
    let isDark: Bool

    public init(
        cornerRadius: CGFloat = TerminusDesign.radiusLG,
        shadow: TerminusDesign.Shadow = .soft,
        isDark: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.shadowStyle = shadow
        self.isDark = isDark
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? .ultraThinMaterial : .regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.15 : 0.3),
                                Color.white.opacity(isDark ? 0.05 : 0.1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: shadowStyle.color,
                radius: shadowStyle.radius,
                y: shadowStyle.y
            )
    }
}

// MARK: - Glass Background Modifier (no corner radius, for full-width areas)

public struct GlassBackgroundModifier: ViewModifier {
    let isDark: Bool

    public init(isDark: Bool = true) {
        self.isDark = isDark
    }

    public func body(content: Content) -> some View {
        content
            .background(isDark ? .ultraThinMaterial : .regularMaterial)
    }
}

// MARK: - View Extensions

extension View {
    public func glassPanel(
        cornerRadius: CGFloat = TerminusDesign.radiusLG,
        shadow: TerminusDesign.Shadow = .soft,
        isDark: Bool = true
    ) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, shadow: shadow, isDark: isDark))
    }

    public func glassBackground(isDark: Bool = true) -> some View {
        modifier(GlassBackgroundModifier(isDark: isDark))
    }

    public func terminusShadow(_ style: TerminusDesign.Shadow) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }
}
