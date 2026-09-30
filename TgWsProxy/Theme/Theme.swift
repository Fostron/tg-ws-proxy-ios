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

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    /// A color that follows the light/dark appearance by itself, so every
    /// `palette.accent` in the app adapts without checking the color scheme.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

/// Selectable palettes. Each is a hand-picked pair — an accent and a
/// companion hue that sit well next to it — in a light-mode and a (lighter)
/// dark-mode variant. The companion only appears in the background gradient
/// and the palette swatch, so buttons stay a single calm color.
enum AppPalette: String, CaseIterable, Identifiable {
    // indigo/espresso keep their raw values so saved choices survive.
    case telegram, indigo, ocean, aurora, sunset, sakura, amber, espresso, graphite

    init(from raw: String) {
        self = AppPalette(rawValue: raw) ?? .telegram
    }

    var id: String { rawValue }

    /// (accent light, accent dark, companion light, companion dark)
    private var hexes: (UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .telegram: return (0x229ED9, 0x54BCF5, 0x6C5CE7, 0xA29BFE)
        case .indigo:   return (0x5856D6, 0x9E9CFF, 0xC026D3, 0xF0ABFC)
        case .ocean:    return (0x0F9D9A, 0x3ED1C8, 0x2563EB, 0x7AA7FF)
        case .aurora:   return (0x12B76A, 0x5EE3A1, 0x7C3AED, 0xB79CFF)
        case .sunset:   return (0xEA6A1B, 0xFF9F5A, 0xE6397B, 0xFF7EB0)
        case .sakura:   return (0xDB3F76, 0xFF8DB4, 0x8B5CF6, 0xC8B2FF)
        case .amber:    return (0xC27803, 0xFFC247, 0x0E9F8E, 0x52D6C4)
        case .espresso: return (0x7B4A32, 0xD9B08C, 0xB7791F, 0xF6C177)
        case .graphite: return (0x475569, 0xAAB6C8, 0x0EA5E9, 0x7DD3FC)
        }
    }

    var accent: Color { Color.adaptive(light: hexes.0, dark: hexes.1) }
    var companion: Color { Color.adaptive(light: hexes.2, dark: hexes.3) }

    /// The dark-mode accent as a plain value, for places that are always
    /// dark (the Dynamic Island) and can't resolve an adaptive color.
    var accentOnDarkHex: UInt32 { hexes.1 }

    func displayName(_ lang: AppLanguage) -> String {
        let ru = lang == .ru
        switch self {
        case .telegram: return "Telegram"
        case .indigo: return ru ? "Индиго" : "Indigo"
        case .ocean: return ru ? "Океан" : "Ocean"
        case .aurora: return ru ? "Аврора" : "Aurora"
        case .sunset: return ru ? "Закат" : "Sunset"
        case .sakura: return ru ? "Сакура" : "Sakura"
        case .amber: return ru ? "Янтарь" : "Amber"
        case .espresso: return ru ? "Эспрессо" : "Espresso"
        case .graphite: return ru ? "Графит" : "Graphite"
        }
    }
}

/// How much of the palette shows through behind the cards.
enum AppBackdrop: String, CaseIterable, Identifiable {
    case plain, soft, vivid

    init(from raw: String) {
        self = AppBackdrop(rawValue: raw) ?? .soft
    }

    var id: String { rawValue }

    /// (accent, companion) gradient opacity for (light, dark) appearance.
    func strengths(dark: Bool) -> (Double, Double) {
        switch self {
        case .plain: return (0, 0)
        case .soft: return dark ? (0.30, 0.22) : (0.20, 0.14)
        case .vivid: return dark ? (0.55, 0.42) : (0.38, 0.28)
        }
    }
}

/// Full-screen background for every tab and sheet: the system grouped
/// background with the palette's two colors washed across it.
struct AppBackground: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = AppPalette(from: settings.themePalette)
        let strengths = AppBackdrop(from: settings.themeBackdrop).strengths(dark: scheme == .dark)
        let a = strengths.0
        let c = strengths.1
        ZStack {
            Color(UIColor.systemGroupedBackground)
            if a > 0 {
                LinearGradient(
                    colors: [palette.accent.opacity(a), palette.companion.opacity(c * 0.6), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [palette.companion.opacity(c), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: settings.themePalette)
        .animation(.easeInOut(duration: 0.35), value: settings.themeBackdrop)
    }
}

extension View {
    /// Themed background behind a tab or sheet. Lists and Forms also need
    /// their own opaque background hidden to let it through.
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

/// Semantic status colors — ported from Android's AppColors object so
/// "connected", "warning", and log-level colors mean the same thing on both
/// platforms.
enum AppColors {
    static let connected = Color(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)
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
