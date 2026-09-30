import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TgWsProxyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ProxyLiveActivity()
    }
}

struct ProxyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProxyActivityAttributes.self) { context in
            let style = context.attributes.style
            LockScreenView(context: context)
                .activityBackgroundTint(
                    style.tintedLockScreen
                        ? Color(islandHex: style.themeHex).opacity(0.35)
                        : Color.black.opacity(0.65)
                )
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let style = context.attributes.style
            let ru = context.attributes.isRussian
            let stale = isStale(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RateBlock(title: ru ? "Скачивание" : "Download", systemImage: "arrow.down",
                              value: stale ? "—" : TrafficFormat.rate(state.downRate, russian: ru),
                              tint: style.downColor.color(themeHex: style.themeHex))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RateBlock(title: ru ? "Выгрузка" : "Upload", systemImage: "arrow.up",
                              value: stale ? "—" : TrafficFormat.rate(state.upRate, russian: ru),
                              tint: style.upColor.color(themeHex: style.themeHex))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    if style.showMode {
                        ModeBadge(state: state, style: style, ru: ru, stale: stale)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SummaryLine(state: state, style: style, ru: ru, stale: stale)
                        .padding(.top, 2)
                }
            } compactLeading: {
                IslandSlotView(slot: style.leading, state: state, style: style, stale: stale)
            } compactTrailing: {
                IslandSlotView(slot: style.trailing, state: state, style: style, stale: stale)
            } minimal: {
                IslandSlotView(slot: style.minimal == .none ? .icon : style.minimal,
                               state: state, style: style, stale: stale)
            }
        }
    }
}

/// The app pushes an update every few seconds and sets a stale date just past
/// that; if iOS suspends the app the numbers would freeze, so show that
/// instead of a speed that's no longer true.
private func isStale(_ context: ActivityViewContext<ProxyActivityAttributes>) -> Bool {
    if #available(iOS 16.2, *) {
        return context.isStale
    }
    return false
}

private struct ModeBadge: View {
    let state: ProxyActivityAttributes.ContentState
    let style: IslandStyle
    let ru: Bool
    let stale: Bool

    var body: some View {
        let color = style.modeColor.color(themeHex: style.themeHex)
        HStack(spacing: 4) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption2)
            Text(stale ? (ru ? "пауза" : "paused") : islandModeLabel(state))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(stale ? .gray : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((stale ? Color.gray : color).opacity(0.18)))
    }
}

private struct RateBlock: View {
    let title: String
    let systemImage: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct SummaryLine: View {
    let state: ProxyActivityAttributes.ContentState
    let style: IslandStyle
    let ru: Bool
    let stale: Bool

    var body: some View {
        HStack(spacing: 10) {
            if style.showTraffic {
                Label(TrafficFormat.bytes(state.totalDown, russian: ru), systemImage: "arrow.down")
                Label(TrafficFormat.bytes(state.totalUp, russian: ru), systemImage: "arrow.up")
            }
            Spacer(minLength: 0)
            if style.showConnections {
                Label(stale ? "—" : "\(state.connections)", systemImage: "link")
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ProxyActivityAttributes>

    var body: some View {
        let state = context.state
        let style = context.attributes.style
        let ru = context.attributes.isRussian
        let stale = isStale(context)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("TG WS Proxy", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if style.showMode {
                    ModeBadge(state: state, style: style, ru: ru, stale: stale)
                }
            }
            HStack(alignment: .top) {
                RateBlock(title: ru ? "Скачивание" : "Download", systemImage: "arrow.down",
                          value: stale ? "—" : TrafficFormat.rate(state.downRate, russian: ru),
                          tint: style.downColor.color(themeHex: style.themeHex))
                Spacer()
                RateBlock(title: ru ? "Выгрузка" : "Upload", systemImage: "arrow.up",
                          value: stale ? "—" : TrafficFormat.rate(state.upRate, russian: ru),
                          tint: style.upColor.color(themeHex: style.themeHex))
            }
            SummaryLine(state: state, style: style, ru: ru, stale: stale)
        }
        .padding(16)
    }
}
