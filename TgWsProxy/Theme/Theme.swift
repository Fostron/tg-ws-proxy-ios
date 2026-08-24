import SwiftUI

enum AppTheme {
    case system, light, dark

    init(from mode: String) {
        switch mode {
        case "light": self = .light
        case "dark": self = .dark
        default: self = .system
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Selectable accent palettes — ported from the Android app's theme system
/// (Theme.kt: indigo/espresso color schemes), adapted to a single accent
/// color per palette since iOS derives most system chrome automatically.
enum AppPalette: String, CaseIterable, Identifiable {
    case indigo, espresso

    init(from raw: String) {
        self = AppPalette(rawValue: raw) ?? .indigo
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .espresso: return "Espresso"
        }
    }

    /// Matches Android's primary color per palette (Theme.kt) so the two
    /// apps read as the same product even though the UI kits differ.
    var accent: Color {
        switch self {
        case .indigo: return Color(red: 0x5B / 255.0, green: 0x58 / 255.0, blue: 0x8D / 255.0)
        case .espresso: return Color(red: 0x6D / 255.0, green: 0x4C / 255.0, blue: 0x41 / 255.0)
        }
    }

    var accentDark: Color {
        switch self {
        case .indigo: return Color(red: 0xC4 / 255.0, green: 0xC0 / 255.0, blue: 0xFF / 255.0)
        case .espresso: return Color(red: 0xD7 / 255.0, green: 0xCC / 255.0, blue: 0xC8 / 255.0)
        }
    }

    var symbolName: String {
        switch self {
        case .indigo: return "circle.fill"
        case .espresso: return "circle.fill"
        }
    }
}

/// Semantic status colors — ported from Android's AppColors object so
/// "connected", "warning", and log-level colors mean the same thing on both
/// platforms.
enum AppColors {
    static let connected = Color(red: 0x4C / 255.0, green: 0xAF / 255.0, blue: 0x50 / 255.0)
    static let connectedContainer = connected.opacity(0.12)
    static let warning = Color(red: 0xFF / 255.0, green: 0xA7 / 255.0, blue: 0x26 / 255.0)

    static let terminalBg = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let terminalBgDark = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let terminalText = Color(red: 0.85, green: 0.85, blue: 0.87)
    static let terminalGreen = Color(red: 0.30, green: 0.85, blue: 0.40)
    static let terminalRed = Color(red: 0.95, green: 0.30, blue: 0.30)
    static let terminalOrange = Color(red: 1.0, green: 0.60, blue: 0.0)
    static let terminalBlue = Color(red: 0.40, green: 0.60, blue: 1.0)
    static let terminalCounter = Color(red: 0.30, green: 0.50, blue: 0.90)
}

// MARK: - Liquid Glass card

/// Rounded, tinted surface — the iOS equivalent of Android's AppSectionCard
/// (Surface + RoundedCornerShape(28.dp)). Uses real Liquid Glass on iOS 26+
/// (glassEffect), falls back to a Material-backed card on older OS versions
/// so the app still builds and looks reasonable below the 16.0 deployment
/// target.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .glassEffect(
                    tint.map { Glass.regular.tint($0.opacity(0.16)) } ?? .regular,
                    in: shape
                )
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(shape.fill(.regularMaterial))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    /// Wraps this view in a glass card surface — iOS 26 real Liquid Glass,
    /// Material fallback below that.
    func glassCard(cornerRadius: CGFloat = 28, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

/// Groups multiple glass surfaces into a single rendering pass.
///
/// Without this, every `.glassEffect()` sampled and refracted the backdrop on
/// its own; while scrolling, those independent layers update out of sync and
/// the cards visibly flicker — worst on screens with many stacked cards and
/// buttons. `GlassEffectContainer` merges them so they're computed together.
/// No-op below iOS 26, where the Material fallback doesn't have this issue.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
