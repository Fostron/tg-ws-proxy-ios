import ActivityKit
import SwiftUI

/// The Live Activity shown in the Dynamic Island and on the Lock Screen while
/// the proxy runs. Compiled into both the app (which starts and updates it)
/// and the TgWsProxyLiveActivity extension (which draws it).
struct ProxyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Bytes per second over the last stats interval.
        var downRate: Double
        var upRate: Double
        /// Totals since the proxy started.
        var totalDown: Int64
        var totalUp: Int64
        var connections: Int
        /// The route setting: "Auto", "CDN" or "Worker".
        var route: String
        /// The route that actually carried the latest connections: "Direct",
        /// "CDN", "Worker", "TCP", or "" before the first one.
        var via: String
    }

    /// The extension can't read the app's settings, so the UI language and
    /// the look are handed over when the activity starts (changing either
    /// restarts it).
    var language: String
    var style: IslandStyle

    var isRussian: Bool { language == "ru" }
}

/// What a Dynamic Island slot shows.
enum IslandSlot: String, Codable, CaseIterable, Identifiable {
    case download, upload, mode, connections, traffic, icon, none

    var id: String { rawValue }

    func title(russian ru: Bool) -> String {
        switch self {
        case .download: return ru ? "Скачивание" : "Download"
        case .upload: return ru ? "Выгрузка" : "Upload"
        case .mode: return ru ? "Режим" : "Mode"
        case .connections: return ru ? "Соединения" : "Connections"
        case .traffic: return ru ? "Трафик" : "Traffic"
        case .icon: return ru ? "Значок" : "Icon"
        case .none: return ru ? "Пусто" : "Empty"
        }
    }
}

/// Colors the island can use. `.theme` is the app palette's accent, resolved
/// when the activity starts and carried in `IslandStyle.themeHex`.
enum IslandColor: String, Codable, CaseIterable, Identifiable {
    case theme, green, mint, cyan, blue, purple, pink, orange, yellow, white

    var id: String { rawValue }

    func color(themeHex: UInt32) -> Color {
        switch self {
        case .theme: return Color(islandHex: themeHex)
        case .green: return Color(islandHex: 0x34C759)
        case .mint: return Color(islandHex: 0x63E6BE)
        case .cyan: return Color(islandHex: 0x5AC8FA)
        case .blue: return Color(islandHex: 0x4C8DFF)
        case .purple: return Color(islandHex: 0xB38BFF)
        case .pink: return Color(islandHex: 0xFF6FAE)
        case .orange: return Color(islandHex: 0xFF9F43)
        case .yellow: return Color(islandHex: 0xFFD60A)
        case .white: return .white
        }
    }
}

/// Everything the user can customise about the Live Activity.
struct IslandStyle: Codable, Hashable {
    var leading: IslandSlot = .download
    var trailing: IslandSlot = .upload
    var minimal: IslandSlot = .icon
    var downColor: IslandColor = .green
    var upColor: IslandColor = .cyan
    var modeColor: IslandColor = .theme
    /// Resolved palette accent for `.theme`.
    var themeHex: UInt32 = 0x54BCF5
    var showMode = true
    var showTraffic = true
    var showConnections = true
    /// Show "/s" after compact speeds ("1.2M/s" instead of "1.2M").
    var compactUnits = false
    /// Tint the Lock Screen card with the palette color instead of plain dark.
    var tintedLockScreen = true

    static let `default` = IslandStyle()
}

extension Color {
    /// Separate from the app's Color(hex:) so this file also compiles into
    /// the extension, which doesn't have the app's theme code.
    init(islandHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

enum TrafficFormat {
    private static let kb = 1024.0
    private static let mb = 1024.0 * 1024.0

    /// Short enough for the compact Dynamic Island slots: "0", "850", "12K",
    /// "1.4M". The "per second" is implied by the arrows next to it.
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < kb { return String(format: "%.0f", v) }
        if v < mb { return shortNumber(v / kb) + "K" }
        return shortNumber(v / mb) + "M"
    }

    /// "850 Б/с", "12 КБ/с", "1.4 МБ/с".
    static func rate(_ bytesPerSecond: Double, russian: Bool) -> String {
        let v = max(0, bytesPerSecond)
        let perSec = russian ? "/с" : "/s"
        if v < kb { return String(format: "%.0f ", v) + (russian ? "Б" : "B") + perSec }
        if v < mb { return shortNumber(v / kb) + (russian ? " КБ" : " KB") + perSec }
        return shortNumber(v / mb) + (russian ? " МБ" : " MB") + perSec
    }

    /// "850 Б", "12 КБ", "1.4 МБ", "2.1 ГБ".
    static func bytes(_ count: Int64, russian: Bool) -> String {
        let v = Double(max(0, count))
        if v < kb { return String(format: "%.0f ", v) + (russian ? "Б" : "B") }
        if v < mb { return shortNumber(v / kb) + (russian ? " КБ" : " KB") }
        if v < mb * 1024 { return shortNumber(v / mb) + (russian ? " МБ" : " MB") }
        return shortNumber(v / (mb * 1024)) + (russian ? " ГБ" : " GB")
    }

    /// "1.4M", "12K", "850B" — compact total for the Traffic slot.
    static func compactBytes(_ count: Int64) -> String {
        let v = Double(max(0, count))
        if v < kb { return String(format: "%.0fB", v) }
        if v < mb { return shortNumber(v / kb) + "K" }
        if v < mb * 1024 { return shortNumber(v / mb) + "M" }
        return shortNumber(v / (mb * 1024)) + "G"
    }

    /// One decimal below 10, none above: "1.4", "12", "512".
    private static func shortNumber(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}

// MARK: - Views shared by the extension and the in-app preview

/// One compact Dynamic Island slot. The Settings preview draws the exact
/// same view, so what you configure is what you get.
struct IslandSlotView: View {
    let slot: IslandSlot
    let state: ProxyActivityAttributes.ContentState
    let style: IslandStyle
    let stale: Bool

    var body: some View {
        switch slot {
        case .download:
            rate(systemImage: "arrow.down", value: state.downRate, color: style.downColor)
        case .upload:
            rate(systemImage: "arrow.up", value: state.upRate, color: style.upColor)
        case .mode:
            Text(stale ? "—" : islandModeLabel(state))
                .font(.caption.weight(.bold))
                .foregroundColor(stale ? .gray : style.modeColor.color(themeHex: style.themeHex))
                .lineLimit(1)
        case .connections:
            HStack(spacing: 2) {
                Image(systemName: "link")
                    .font(.caption2.weight(.bold))
                Text(stale ? "—" : "\(state.connections)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundColor(stale ? .gray : style.modeColor.color(themeHex: style.themeHex))
        case .traffic:
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2.weight(.bold))
                Text(stale ? "—" : TrafficFormat.compactBytes(state.totalDown + state.totalUp))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundColor(stale ? .gray : style.downColor.color(themeHex: style.themeHex))
        case .icon:
            Image(systemName: "bolt.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(stale ? .gray : style.modeColor.color(themeHex: style.themeHex))
        case .none:
            EmptyView()
        }
    }

    private func rate(systemImage: String, value: Double, color: IslandColor) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(stale ? "—" : TrafficFormat.compactRate(value) + (style.compactUnits ? "/s" : ""))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundColor(stale ? .gray : color.color(themeHex: style.themeHex))
    }
}

/// "CDN", or "Auto→CDN" when the setting and the route in use differ.
func islandModeLabel(_ state: ProxyActivityAttributes.ContentState) -> String {
    if state.via.isEmpty || state.via == state.route { return state.route }
    if state.route == "Auto" { return state.via }
    return "\(state.route)→\(state.via)"
}
