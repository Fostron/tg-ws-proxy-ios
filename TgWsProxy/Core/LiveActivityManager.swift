import ActivityKit
import Foundation

/// Drives the Dynamic Island / Lock Screen Live Activity: download and upload
/// speed, totals, connection count and the route in use while the proxy runs.
///
/// Every method must be called on the main thread. Uses the iOS 16.2
/// ActivityContent API; on 16.1 the proxy simply runs without it.
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    /// Stats arrive every 3s; if nothing refreshes the activity for this long
    /// the app was suspended and the numbers on screen are no longer live.
    private let staleAfter: TimeInterval = 15

    private var activity: Activity<ProxyActivityAttributes>?
    private var lastSample: (up: Int64, down: Int64, at: Date)?
    private var lastRouteCounts: [String: Int64] = [:]
    private var via = ""
    private var route = "Auto"

    var isActive: Bool { activity != nil }

    /// Must be called while the app is in the foreground — iOS refuses to
    /// start a Live Activity from the background. Restarting is also how a
    /// new look or language takes effect: those are fixed per activity.
    func start(route: String, language: String, style: IslandStyle) {
        guard #available(iOS 16.2, *) else { return }
        endAll()
        self.route = route
        lastSample = nil
        lastRouteCounts = [:]
        via = ""

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.addLog("Live Activities выключены в настройках iOS — Dynamic Island не покажет скорость", level: .warn)
            return
        }

        let state = ProxyActivityAttributes.ContentState(
            downRate: 0, upRate: 0, totalDown: 0, totalUp: 0, connections: 0, route: route, via: ""
        )
        do {
            activity = try Activity.request(
                attributes: ProxyActivityAttributes(language: language, style: style),
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter)),
                pushType: nil
            )
        } catch {
            LogManager.shared.addLog("Не удалось показать скорость в Dynamic Island: \(error.localizedDescription)", level: .warn)
        }
    }

    /// Feeds cumulative counters from the core; speeds are the deltas between
    /// consecutive calls, and the route in use is whichever tier took the
    /// most new connections since the previous call.
    func update(stats: ProxyStats) {
        guard #available(iOS 16.2, *), let activity else { return }

        let now = Date()
        var upRate = 0.0
        var downRate = 0.0
        if let last = lastSample {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.5 {
                // Counters restart from zero when the core restarts.
                upRate = Double(max(0, stats.bytesUp - last.up)) / dt
                downRate = Double(max(0, stats.bytesDown - last.down)) / dt
            }
        }
        lastSample = (stats.bytesUp, stats.bytesDown, now)

        let counts: [String: Int64] = [
            "Direct": stats.ws, "CDN": stats.cfproxy, "Worker": stats.cfWorker, "TCP": stats.tcpFallback,
        ]
        let deltas = counts.map { ($0.key, $0.value - (lastRouteCounts[$0.key] ?? 0)) }
        if let busiest = deltas.max(by: { $0.1 < $1.1 }), busiest.1 > 0 {
            via = busiest.0
        }
        lastRouteCounts = counts

        let state = ProxyActivityAttributes.ContentState(
            downRate: downRate, upRate: upRate, totalDown: stats.bytesDown, totalUp: stats.bytesUp,
            connections: Int(stats.active), route: route, via: via
        )
        // Sent even when nothing changed: the stale date has to keep moving,
        // or an idle-but-running proxy would be shown as frozen.
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(staleAfter))
        Task { await activity.update(content) }
    }

    func end() {
        guard #available(iOS 16.2, *) else { return }
        let current = activity
        activity = nil
        lastSample = nil
        if let current {
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Activities outlive the app process. One left over from a run that was
    /// killed while the proxy was on would keep showing frozen numbers.
    func endAll() {
        guard #available(iOS 16.2, *) else { return }
        activity = nil
        for leftover in Activity<ProxyActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
