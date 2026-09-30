import Foundation

/// Which route new connections try first — mirrors routeAuto/routeCdnFirst/
/// routeWorkerFirst in the Go core (SetRouteMode).
enum RouteMode: Int, CaseIterable, Identifiable {
    /// Upstream's behaviour: Direct WS for DCs with an address, then
    /// Worker -> CDN -> TCP. Routes that go dead are skipped for a while.
    case auto = 0
    case cdnFirst = 1
    case workerFirst = 2

    var id: Int { rawValue }
}

/// Everything the Go core needs for one start, snapshotted from the settings
/// so both start paths (power button and tgwsproxy:// URL) configure it the
/// same way.
struct ProxyLaunchConfig {
    var bindIp: String
    var port: Int
    var dcIps: String
    var poolSize: Int
    var routeMode: RouteMode
    var cfEnabled: Bool
    var cfDomain: String
    var cfWorkerEnabled: Bool
    var cfWorkerURL: String
    var fakeTlsEnabled: Bool
    var fakeTlsDomain: String
    var fakeTlsMaskHost: String
    var proxyProtocol: Bool
    var fragmentEnabled: Bool
    var fragmentFirstSize: Int
    var fragmentDelayMs: Int
    var tlsFingerprint: Int
    var fakeSniEnabled: Bool
    var fakeSniValue: String
    var dohUseCloudflare: Bool
    var dohUseGoogle: Bool
    var dohUseQuad9: Bool
    var dohUseAdguard: Bool
    var dohCustomURL: String
    var secretKey: String
    /// Live Activity (Dynamic Island) with download/upload speed.
    var showLiveActivity: Bool
    var islandStyle: IslandStyle
    var routeLabel: String
    var language: String
}

class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Loopback keeps the proxy reachable only from this device — the safe
    /// default. 0.0.0.0 exposes it to the whole local network.
    static let defaultBindIp = "127.0.0.1"
    static let defaultPort = "1443"
    static let defaultPoolSize = 4
    static let defaultDc2Ip = "149.154.167.220"
    static let defaultDc4Ip = "149.154.167.220"

    private enum Keys {
        static let port = "port"
        static let bindIp = "bind_ip"
        static let poolSize = "pool_size"
        static let secretKey = "secret_key"
        static let cfproxyEnabled = "cfproxy_enabled"
        static let customCfDomainEnabled = "custom_cf_domain_enabled"
        static let customCfDomain = "custom_cf_domain"
        static let cfWorkerEnabled = "cf_worker_enabled"
        static let cfWorkerURL = "cf_worker_url"
        static let fakeTlsEnabled = "fake_tls_enabled"
        static let fakeTlsDomain = "fake_tls_domain"
        static let fakeTlsMaskHost = "fake_tls_mask_host"
        static let proxyProtocolEnabled = "proxy_protocol_enabled"
        static let linkHost = "link_host"
        static let linkPort = "link_port"
        static let routeMode = "route_mode"
        static let showLiveActivity = "show_live_activity"
        static let islandStyle = "island_style"
        static let themeBackdrop = "theme_backdrop"
        static let tlsFingerprint = "tls_fingerprint"
        static let fakeSniEnabled = "fake_sni_enabled"
        static let fakeSniValue = "fake_sni_value"
        static let fragmentEnabled = "fragment_enabled"
        static let fragmentFirstSize = "fragment_first_size"
        static let fragmentDelayMs = "fragment_delay_ms"
        static let dohUseCloudflare = "doh_use_cloudflare"
        static let dohUseGoogle = "doh_use_google"
        static let dohUseQuad9 = "doh_use_quad9"
        static let dohUseAdguard = "doh_use_adguard"
        static let dohCustomURL = "doh_custom_url"
        static let themeMode = "theme_mode"
        static let themePalette = "theme_palette"
        static let language = "app_language"
        static let autoStartOnBoot = "auto_start_on_boot"
        static let dc1 = "dc1"
        static let dc2 = "dc2"
        static let dc3 = "dc3"
        static let dc4 = "dc4"
        static let dc5 = "dc5"
        static let dc203 = "dc203"
        static let dc1m = "dc1m"
        static let dc2m = "dc2m"
        static let dc3m = "dc3m"
        static let dc4m = "dc4m"
        static let dc5m = "dc5m"
        static let dc203m = "dc203m"
        static let isExperimentalMode = "is_experimental_mode"
        static let experimentalFeaturesEnabled = "experimental_features_enabled"
        static let logShowInfo = "log_show_info"
        static let logShowError = "log_show_error"
        static let logShowNull = "log_show_null"
        static let logShowDebug = "log_show_debug"
    }

    @Published var bindIp: String {
        didSet { defaults.set(bindIp, forKey: Keys.bindIp) }
    }
    @Published var port: String {
        didSet { defaults.set(port, forKey: Keys.port) }
    }
    @Published var poolSize: Int {
        didSet { defaults.set(poolSize, forKey: Keys.poolSize) }
    }
    @Published var secretKey: String {
        didSet { defaults.set(secretKey, forKey: Keys.secretKey) }
    }
    @Published var cfproxyEnabled: Bool {
        didSet { defaults.set(cfproxyEnabled, forKey: Keys.cfproxyEnabled) }
    }
    @Published var customCfDomainEnabled: Bool {
        didSet { defaults.set(customCfDomainEnabled, forKey: Keys.customCfDomainEnabled) }
    }
    @Published var customCfDomain: String {
        didSet { defaults.set(customCfDomain, forKey: Keys.customCfDomain) }
    }
    @Published var cfWorkerEnabled: Bool {
        didSet { defaults.set(cfWorkerEnabled, forKey: Keys.cfWorkerEnabled) }
    }
    @Published var cfWorkerURL: String {
        didSet { defaults.set(cfWorkerURL, forKey: Keys.cfWorkerURL) }
    }
    @Published var fakeTlsEnabled: Bool {
        didSet { defaults.set(fakeTlsEnabled, forKey: Keys.fakeTlsEnabled) }
    }
    @Published var fakeTlsDomain: String {
        didSet { defaults.set(fakeTlsDomain, forKey: Keys.fakeTlsDomain) }
    }
    /// host[:port] of a real website that connections failing the FakeTLS
    /// check are forwarded to. Empty = just close them.
    @Published var fakeTlsMaskHost: String {
        didSet { defaults.set(fakeTlsMaskHost, forKey: Keys.fakeTlsMaskHost) }
    }
    /// Running behind nginx with `proxy_protocol on;`.
    @Published var proxyProtocolEnabled: Bool {
        didSet { defaults.set(proxyProtocolEnabled, forKey: Keys.proxyProtocolEnabled) }
    }
    /// Address and port other people connect to (your domain / nginx), used
    /// in the shared link instead of this device's bind address.
    @Published var linkHost: String {
        didSet { defaults.set(linkHost, forKey: Keys.linkHost) }
    }
    @Published var linkPort: String {
        didSet { defaults.set(linkPort, forKey: Keys.linkPort) }
    }
    @Published var routeMode: RouteMode {
        didSet { defaults.set(routeMode.rawValue, forKey: Keys.routeMode) }
    }
    /// Download/upload speed in the Dynamic Island and on the Lock Screen.
    @Published var showLiveActivity: Bool {
        didSet { defaults.set(showLiveActivity, forKey: Keys.showLiveActivity) }
    }
    /// Look of the Dynamic Island / Lock Screen activity, stored as JSON.
    @Published var islandStyle: IslandStyle {
        didSet {
            if let data = try? JSONEncoder().encode(islandStyle) {
                defaults.set(data, forKey: Keys.islandStyle)
            }
        }
    }
    /// AppBackdrop raw value: how strongly the palette tints the background.
    @Published var themeBackdrop: String {
        didSet { defaults.set(themeBackdrop, forKey: Keys.themeBackdrop) }
    }
    /// 0 = Go stdlib, 1 = Firefox, 2 = Chrome, 3 = Safari, 4 = randomized.
    @Published var fakeSniEnabled: Bool {
        didSet { defaults.set(fakeSniEnabled, forKey: Keys.fakeSniEnabled) }
    }
    @Published var fakeSniValue: String {
        didSet { defaults.set(fakeSniValue, forKey: Keys.fakeSniValue) }
    }
    @Published var tlsFingerprint: Int {
        didSet { defaults.set(tlsFingerprint, forKey: Keys.tlsFingerprint) }
    }
    @Published var fragmentEnabled: Bool {
        didSet { defaults.set(fragmentEnabled, forKey: Keys.fragmentEnabled) }
    }
    @Published var fragmentFirstSize: Int {
        didSet { defaults.set(fragmentFirstSize, forKey: Keys.fragmentFirstSize) }
    }
    @Published var fragmentDelayMs: Int {
        didSet { defaults.set(fragmentDelayMs, forKey: Keys.fragmentDelayMs) }
    }
    @Published var dohUseCloudflare: Bool {
        didSet { defaults.set(dohUseCloudflare, forKey: Keys.dohUseCloudflare) }
    }
    @Published var dohUseGoogle: Bool {
        didSet { defaults.set(dohUseGoogle, forKey: Keys.dohUseGoogle) }
    }
    @Published var dohUseQuad9: Bool {
        didSet { defaults.set(dohUseQuad9, forKey: Keys.dohUseQuad9) }
    }
    @Published var dohUseAdguard: Bool {
        didSet { defaults.set(dohUseAdguard, forKey: Keys.dohUseAdguard) }
    }
    @Published var dohCustomURL: String {
        didSet { defaults.set(dohCustomURL, forKey: Keys.dohCustomURL) }
    }
    @Published var themeMode: String {
        didSet { defaults.set(themeMode, forKey: Keys.themeMode) }
    }
    @Published var themePalette: String {
        didSet { defaults.set(themePalette, forKey: Keys.themePalette) }
    }
    /// UI language — independent of theme/palette, but lives in the same
    /// "appearance" popover on the main tab since that's where people expect
    /// to find it.
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published var autoStartOnBoot: Bool {
        didSet { defaults.set(autoStartOnBoot, forKey: Keys.autoStartOnBoot) }
    }
    @Published var isExperimentalMode: Bool {
        didSet { defaults.set(isExperimentalMode, forKey: Keys.isExperimentalMode) }
    }
    /// Gate for the advanced networking cards (Cloudflare Worker, FakeTLS,
    /// DoH resolvers, custom CF domain). Off by default: those cards are
    /// hidden from Settings AND their stored values are ignored when
    /// starting the proxy — see the `effective*` accessors below. This is
    /// deliberately separate from `isExperimentalMode`, which only reveals
    /// the extra DC/media-DC address fields inside DC setup.
    @Published var experimentalFeaturesEnabled: Bool {
        didSet { defaults.set(experimentalFeaturesEnabled, forKey: Keys.experimentalFeaturesEnabled) }
    }

    /// Experimental features (FakeTLS/nginx, TLS fingerprint, SNI spoofing,
    /// fragmentation, DoH tuning) only exist in the test build: CI compiles
    /// the Fostron/test repo with EXPERIMENTAL. The public release hides them
    /// and ignores any values left over from a test build.
    static let experimentalBuild: Bool = {
        #if EXPERIMENTAL
        return true
        #else
        return false
        #endif
    }()

    /// Whether experimental settings actually apply right now.
    var experimentalOn: Bool { SettingsStore.experimentalBuild && experimentalFeaturesEnabled }
    @Published var dc1: String { didSet { defaults.set(dc1, forKey: Keys.dc1) } }
    @Published var dc2: String { didSet { defaults.set(dc2, forKey: Keys.dc2) } }
    @Published var dc3: String { didSet { defaults.set(dc3, forKey: Keys.dc3) } }
    @Published var dc4: String { didSet { defaults.set(dc4, forKey: Keys.dc4) } }
    @Published var dc5: String { didSet { defaults.set(dc5, forKey: Keys.dc5) } }
    @Published var dc203: String { didSet { defaults.set(dc203, forKey: Keys.dc203) } }
    @Published var dc1m: String { didSet { defaults.set(dc1m, forKey: Keys.dc1m) } }
    @Published var dc2m: String { didSet { defaults.set(dc2m, forKey: Keys.dc2m) } }
    @Published var dc3m: String { didSet { defaults.set(dc3m, forKey: Keys.dc3m) } }
    @Published var dc4m: String { didSet { defaults.set(dc4m, forKey: Keys.dc4m) } }
    @Published var dc5m: String { didSet { defaults.set(dc5m, forKey: Keys.dc5m) } }
    @Published var dc203m: String { didSet { defaults.set(dc203m, forKey: Keys.dc203m) } }
    @Published var logShowInfo: Bool {
        didSet { defaults.set(logShowInfo, forKey: Keys.logShowInfo) }
    }
    @Published var logShowError: Bool {
        didSet { defaults.set(logShowError, forKey: Keys.logShowError) }
    }
    @Published var logShowDebug: Bool {
        didSet { defaults.set(logShowDebug, forKey: Keys.logShowDebug) }
    }
    @Published var logShowNull: Bool {
        didSet { defaults.set(logShowNull, forKey: Keys.logShowNull) }
    }

    init() {
        bindIp = defaults.string(forKey: Keys.bindIp) ?? SettingsStore.defaultBindIp
        port = defaults.string(forKey: Keys.port) ?? SettingsStore.defaultPort
        poolSize = defaults.object(forKey: Keys.poolSize) as? Int ?? SettingsStore.defaultPoolSize
        secretKey = defaults.string(forKey: Keys.secretKey) ?? ""
        cfproxyEnabled = defaults.object(forKey: Keys.cfproxyEnabled) as? Bool ?? true
        customCfDomainEnabled = defaults.object(forKey: Keys.customCfDomainEnabled) as? Bool ?? false
        customCfDomain = defaults.string(forKey: Keys.customCfDomain) ?? ""
        cfWorkerEnabled = defaults.object(forKey: Keys.cfWorkerEnabled) as? Bool ?? false
        cfWorkerURL = defaults.string(forKey: Keys.cfWorkerURL) ?? ""
        fakeTlsEnabled = defaults.object(forKey: Keys.fakeTlsEnabled) as? Bool ?? false
        fakeTlsDomain = defaults.string(forKey: Keys.fakeTlsDomain) ?? ""
        fakeTlsMaskHost = defaults.string(forKey: Keys.fakeTlsMaskHost) ?? ""
        proxyProtocolEnabled = defaults.object(forKey: Keys.proxyProtocolEnabled) as? Bool ?? false
        linkHost = defaults.string(forKey: Keys.linkHost) ?? ""
        linkPort = defaults.string(forKey: Keys.linkPort) ?? ""
        routeMode = RouteMode(rawValue: defaults.integer(forKey: Keys.routeMode)) ?? .auto
        showLiveActivity = defaults.object(forKey: Keys.showLiveActivity) as? Bool ?? true
        islandStyle = defaults.data(forKey: Keys.islandStyle)
            .flatMap { try? JSONDecoder().decode(IslandStyle.self, from: $0) } ?? .default
        themeBackdrop = defaults.string(forKey: Keys.themeBackdrop) ?? AppBackdrop.soft.rawValue
        fakeSniEnabled = defaults.object(forKey: Keys.fakeSniEnabled) as? Bool ?? false
        fakeSniValue = defaults.string(forKey: Keys.fakeSniValue) ?? "discord.com"
        tlsFingerprint = defaults.object(forKey: Keys.tlsFingerprint) as? Int ?? 0
        fragmentEnabled = defaults.object(forKey: Keys.fragmentEnabled) as? Bool ?? false
        fragmentFirstSize = defaults.object(forKey: Keys.fragmentFirstSize) as? Int ?? 2
        fragmentDelayMs = defaults.object(forKey: Keys.fragmentDelayMs) as? Int ?? 10
        dohUseCloudflare = defaults.object(forKey: Keys.dohUseCloudflare) as? Bool ?? true
        dohUseGoogle = defaults.object(forKey: Keys.dohUseGoogle) as? Bool ?? true
        dohUseQuad9 = defaults.object(forKey: Keys.dohUseQuad9) as? Bool ?? true
        dohUseAdguard = defaults.object(forKey: Keys.dohUseAdguard) as? Bool ?? true
        dohCustomURL = defaults.string(forKey: Keys.dohCustomURL) ?? ""
        themeMode = defaults.string(forKey: Keys.themeMode) ?? "system"
        themePalette = defaults.string(forKey: Keys.themePalette) ?? AppPalette.telegram.rawValue
        language = AppLanguage(from: defaults.string(forKey: Keys.language) ?? AppLanguage.systemDefault.rawValue)
        autoStartOnBoot = defaults.object(forKey: Keys.autoStartOnBoot) as? Bool ?? false
        isExperimentalMode = defaults.object(forKey: Keys.isExperimentalMode) as? Bool ?? false
        experimentalFeaturesEnabled = defaults.object(forKey: Keys.experimentalFeaturesEnabled) as? Bool ?? false
        dc1 = defaults.string(forKey: Keys.dc1) ?? ""
        dc2 = defaults.string(forKey: Keys.dc2) ?? SettingsStore.defaultDc2Ip
        dc3 = defaults.string(forKey: Keys.dc3) ?? ""
        dc4 = defaults.string(forKey: Keys.dc4) ?? SettingsStore.defaultDc4Ip
        dc5 = defaults.string(forKey: Keys.dc5) ?? ""
        dc203 = defaults.string(forKey: Keys.dc203) ?? ""
        dc1m = defaults.string(forKey: Keys.dc1m) ?? ""
        dc2m = defaults.string(forKey: Keys.dc2m) ?? ""
        dc3m = defaults.string(forKey: Keys.dc3m) ?? ""
        dc4m = defaults.string(forKey: Keys.dc4m) ?? ""
        dc5m = defaults.string(forKey: Keys.dc5m) ?? ""
        dc203m = defaults.string(forKey: Keys.dc203m) ?? ""
        logShowInfo = defaults.object(forKey: Keys.logShowInfo) as? Bool ?? true
        logShowError = defaults.object(forKey: Keys.logShowError) as? Bool ?? true
        logShowNull = defaults.object(forKey: Keys.logShowNull) as? Bool ?? false
        logShowDebug = defaults.object(forKey: Keys.logShowDebug) as? Bool ?? false

        if secretKey.isEmpty {
            secretKey = SettingsStore.generateRandomSecret()
        }
    }

    /// Shorthand for looking up a localized string in the current language,
    /// e.g. `settings.t("settings.title")`.
    func t(_ key: String) -> String {
        L.t(key, language)
    }

    func generateNewSecret() {
        secretKey = SettingsStore.generateRandomSecret()
    }

    static func generateRandomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// DC->IP pairs for Direct WS. These are always used now: turning the CDN
    /// on used to blank them (the old "auto" mode), which silently disabled
    /// Direct altogether and pushed every connection through Cloudflare.
    /// Clearing the fields is how you opt out of Direct, as with upstream's
    /// empty --dc-ip.
    func buildDcIps() -> String {
        var pairs: [String] = []
        if !dc1.isEmpty { pairs.append("1:\(dc1)") }
        if !dc2.isEmpty { pairs.append("2:\(dc2)") }
        if !dc3.isEmpty { pairs.append("3:\(dc3)") }
        if !dc4.isEmpty { pairs.append("4:\(dc4)") }

        if isExperimentalMode {
            if !dc5.isEmpty { pairs.append("5:\(dc5)") }
            if !dc203.isEmpty { pairs.append("203:\(dc203)") }
            if !dc1m.isEmpty { pairs.append("-1:\(dc1m)") }
            if !dc2m.isEmpty { pairs.append("-2:\(dc2m)") }
            if !dc3m.isEmpty { pairs.append("-3:\(dc3m)") }
            if !dc4m.isEmpty { pairs.append("-4:\(dc4m)") }
            if !dc5m.isEmpty { pairs.append("-5:\(dc5m)") }
            if !dc203m.isEmpty { pairs.append("-203:\(dc203m)") }
        }

        return pairs.joined(separator: ",")
    }

    /// True when the Worker URL is well-formed enough to dial (https scheme + host).
    /// Returns true when the feature is off/locked, since an unused field isn't invalid.
    /// Several worker domains may be listed comma-separated; the core tries
    /// them in order so one dead worker doesn't take the tier down. A bare
    /// hostname ("name-1234.user.workers.dev") is accepted too, since that's
    /// exactly what the Cloudflare dashboard hands you.
    var isCfWorkerURLValid: Bool {
        guard cfWorkerEnabled else { return true }
        let entries = cfWorkerURL
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else { return false }

        return entries.allSatisfy { entry in
            let normalized = entry.contains("://") ? entry : "https://" + entry
            guard let url = URL(string: normalized),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https",
                  let host = url.host, !host.isEmpty, host.contains(".") else {
                return false
            }
            return true
        }
    }

    /// True when the custom CF domain field is usable: a bare hostname, no
    /// scheme/path (this gets templated into kws{dc}.<domain>/apiws internally).
    var isCustomCfDomainValid: Bool {
        guard cfproxyEnabled, customCfDomainEnabled else { return true }
        // Comma, semicolon or whitespace separated, matching upstream's
        // coerce_domain_list(). Any TLD is accepted — the domain just needs
        // kws1..kws5/kws203 A-records pointing at the Telegram DC IPs.
        let entries = customCfDomain
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else { return false }

        return entries.allSatisfy { d in
            !d.contains("://") && !d.contains("/") && d.contains(".")
                && !d.hasPrefix(".") && !d.hasSuffix(".")
        }
    }

    /// True when the FakeTLS decoy domain is a bare hostname (no scheme/path —
    /// it's used for TLS-handshake mimicry, not dialed as a URL).
    var isFakeTlsDomainValid: Bool {
        guard experimentalOn, fakeTlsEnabled else { return true }
        let trimmed = fakeTlsDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("://"),
              !trimmed.contains("/"),
              trimmed.contains(".") else {
            return false
        }
        return true
    }

    func effectiveFakeTlsDomain() -> String {
        (experimentalOn && fakeTlsEnabled) ? fakeTlsDomain.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// True when the custom DoH field is either empty (not used) or a valid
    /// https URL — unlike Worker/FakeTLS this isn't gated by its own toggle,
    /// it's just an optional extra endpoint added to whichever built-ins are on.
    var isDohCustomURLValid: Bool {
        guard experimentalOn else { return true }
        let trimmed = dohCustomURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }

    func effectiveCfWorkerURL() -> String {
        cfWorkerEnabled ? cfWorkerURL.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Whether the Worker fallback is actually active — used both to start
    /// the proxy and to reflect the "+W" mode badge on the Proxy tab.
    var effectiveCfWorkerEnabled: Bool {
        cfWorkerEnabled
    }

    var effectiveCustomCfDomain: String {
        customCfDomainEnabled ? customCfDomain : ""
    }

    var effectiveFakeTlsEnabled: Bool {
        experimentalOn && fakeTlsEnabled
    }

    /// Built-in DoH resolvers are NOT gated by the experimental toggle.
    /// Gating them meant that turning experimental features off left
    /// dohEndpoints empty in the core, so resolveDoH() skipped its DoH phase
    /// entirely and fell straight through to plaintext UDP:53 — a silent
    /// privacy downgrade for ordinary users. Encrypted DNS is baseline
    /// behaviour; only the custom endpoint below is experimental.
    /// Fragmentation is an experimental transport tweak like Worker/FakeTLS.
    var effectiveFragmentEnabled: Bool { experimentalOn && fragmentEnabled }

    var effectiveTlsFingerprint: Int { experimentalOn ? tlsFingerprint : 0 }

    var effectiveFakeSniEnabled: Bool { experimentalOn && fakeSniEnabled }

    var isFakeSniValid: Bool {
        guard effectiveFakeSniEnabled else { return true }
        let t = fakeSniValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.contains("://") && !t.contains("/") && t.contains(".")
    }

    func effectiveFakeSniValue() -> String {
        effectiveFakeSniEnabled ? fakeSniValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    var effectiveDohUseCloudflare: Bool { experimentalOn ? dohUseCloudflare : true }
    var effectiveDohUseGoogle: Bool { experimentalOn ? dohUseGoogle : true }
    var effectiveDohUseQuad9: Bool { experimentalOn ? dohUseQuad9 : true }
    var effectiveDohUseAdguard: Bool { experimentalOn ? dohUseAdguard : true }

    var effectiveDohCustomURL: String {
        experimentalOn ? dohCustomURL.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Builds the secret exactly as the Go core's GetSecretWithPrefix() does:
    /// FakeTLS mode requires an "ee" prefix plus the hex-encoded decoy domain,
    /// plain MTProto uses "dd". Hardcoding "dd" here would silently disable
    /// FakeTLS — the core would expect an ee handshake that Telegram never sends.
    private func secretWithPrefix() -> String {
        let secret = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeSecret = secret.isEmpty ? "00000000000000000000000000000000" : secret

        let domain = effectiveFakeTlsDomain()
        if fakeTlsEnabled, !domain.isEmpty, isFakeTlsDomainValid {
            let domHex = domain.utf8.map { String(format: "%02x", $0) }.joined()
            return "ee" + safeSecret + domHex
        }
        return "dd" + safeSecret
    }

    /// Accepts a bare IPv4 literal only. Hostnames are rejected because the
    /// core hands this straight to the listener, and a name that resolves
    /// elsewhere would silently bind nothing reachable.
    var isBindIpValid: Bool {
        let t = bindIp.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isNumber }),
                  let v = Int(p), v >= 0, v <= 255 else { return false }
            return true
        }
    }

    /// True when the proxy will be reachable from other devices on the LAN,
    /// i.e. anything other than loopback. Surfaced in the UI as a warning.
    var bindIpIsExposed: Bool {
        let t = effectiveBindIp()
        return t != "127.0.0.1" && !t.hasPrefix("127.")
    }

    func effectiveBindIp() -> String {
        let t = bindIp.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || !isBindIpValid) ? SettingsStore.defaultBindIp : t
    }

    // MARK: - nginx / external link

    var effectiveProxyProtocol: Bool { experimentalOn && proxyProtocolEnabled }

    func effectiveFakeTlsMaskHost() -> String {
        effectiveFakeTlsEnabled ? fakeTlsMaskHost.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// host or host:port, no scheme or path. Empty is fine (feature unused).
    var isFakeTlsMaskHostValid: Bool {
        guard effectiveFakeTlsEnabled else { return true }
        let t = fakeTlsMaskHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return !t.contains("://") && !t.contains("/") && !t.contains(" ") && t.contains(".")
    }

    var isLinkHostValid: Bool {
        guard experimentalOn else { return true }
        let t = linkHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return !t.contains("://") && !t.contains("/") && !t.contains(":") && !t.contains(" ") && t.contains(".")
    }

    var isLinkPortValid: Bool {
        guard experimentalOn else { return true }
        let t = linkPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        guard let p = Int(t) else { return false }
        return (1...65535).contains(p)
    }

    /// Where this device's own Telegram connects: the bind address, or
    /// loopback when listening on all interfaces.
    private func localLinkHost() -> String {
        let host = effectiveBindIp()
        return host == "0.0.0.0" ? SettingsStore.defaultBindIp : host
    }

    /// Where everyone else connects: the external address (your domain in
    /// front of nginx) when set, otherwise the same as the local one.
    private func sharedLinkHostPort() -> (String, Int) {
        let localPort = Int(port) ?? 1443
        guard experimentalOn else { return (localLinkHost(), localPort) }
        let host = linkHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let extPort = Int(linkPort.trimmingCharacters(in: .whitespacesAndNewlines))
        return (host.isEmpty ? localLinkHost() : host, extPort ?? localPort)
    }

    /// The link shown on the main tab and copied to the clipboard.
    func proxyUrl() -> String {
        let (host, p) = sharedLinkHostPort()
        return "https://t.me/proxy?server=\(host)&port=\(p)&secret=\(secretWithPrefix())"
    }

    /// Native Telegram app deep link for "Apply in Telegram" on this device —
    /// opens Telegram directly instead of going through Safari/Universal
    /// Links. Behind nginx the core only accepts connections carrying a PROXY
    /// header, so this device has to come in through nginx like everyone else.
    func tgProxyUrl() -> String {
        let (host, p) = effectiveProxyProtocol ? sharedLinkHostPort() : (localLinkHost(), Int(port) ?? 1443)
        return "tg://proxy?server=\(host)&port=\(p)&secret=\(secretWithPrefix())"
    }

    // MARK: - Launch

    /// Every field that would make the core reject or misread its config.
    var isLaunchConfigValid: Bool {
        isCfWorkerURLValid && isCustomCfDomainValid && isFakeTlsDomainValid && isFakeTlsMaskHostValid
            && isDohCustomURLValid && isBindIpValid && isFakeSniValid && isLinkHostValid && isLinkPortValid
    }

    /// Advanced networking only takes effect while Experimental Features is
    /// unlocked, even if the individual toggles were left on from before —
    /// that's what the effective* accessors enforce.
    func launchConfig() -> ProxyLaunchConfig {
        ProxyLaunchConfig(
            bindIp: effectiveBindIp(),
            port: Int(port) ?? 1443,
            dcIps: buildDcIps(),
            poolSize: poolSize,
            routeMode: routeMode,
            cfEnabled: cfproxyEnabled,
            cfDomain: effectiveCustomCfDomain,
            cfWorkerEnabled: effectiveCfWorkerEnabled,
            cfWorkerURL: effectiveCfWorkerURL(),
            fakeTlsEnabled: effectiveFakeTlsEnabled,
            fakeTlsDomain: effectiveFakeTlsDomain(),
            fakeTlsMaskHost: effectiveFakeTlsMaskHost(),
            proxyProtocol: effectiveProxyProtocol,
            fragmentEnabled: effectiveFragmentEnabled,
            fragmentFirstSize: fragmentFirstSize,
            fragmentDelayMs: fragmentDelayMs,
            tlsFingerprint: effectiveTlsFingerprint,
            fakeSniEnabled: effectiveFakeSniEnabled,
            fakeSniValue: effectiveFakeSniValue(),
            dohUseCloudflare: effectiveDohUseCloudflare,
            dohUseGoogle: effectiveDohUseGoogle,
            dohUseQuad9: effectiveDohUseQuad9,
            dohUseAdguard: effectiveDohUseAdguard,
            dohCustomURL: effectiveDohCustomURL,
            secretKey: secretKey,
            showLiveActivity: showLiveActivity,
            islandStyle: resolvedIslandStyle,
            routeLabel: effectiveRouteLabel,
            language: language.rawValue
        )
    }

    /// The island style with "theme" colors pinned to the current palette —
    /// the extension can't see the palette itself.
    var resolvedIslandStyle: IslandStyle {
        var style = islandStyle
        style.themeHex = AppPalette(from: themePalette).accentOnDarkHex
        return style
    }

    /// What the route setting actually does with the current config: a
    /// "first" route that isn't configured falls back to Auto in the core.
    var effectiveRouteLabel: String {
        let workerActive = effectiveCfWorkerEnabled && isCfWorkerURLValid && !cfWorkerURL.isEmpty
        switch routeMode {
        case .cdnFirst where cfproxyEnabled:
            return "CDN"
        case .workerFirst where workerActive:
            return "Worker"
        default:
            return "Auto"
        }
    }
}
