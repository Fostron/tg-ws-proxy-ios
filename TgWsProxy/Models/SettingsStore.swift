import Foundation

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
        static let tlsFingerprint = "tls_fingerprint"
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
        static let isDcAuto = "is_dc_auto"
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
    /// 0 = Go stdlib, 1 = Firefox, 2 = Chrome, 3 = Safari, 4 = randomized.
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
    @Published var isDcAuto: Bool {
        didSet { defaults.set(isDcAuto, forKey: Keys.isDcAuto) }
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
        themePalette = defaults.string(forKey: Keys.themePalette) ?? "indigo"
        language = AppLanguage(from: defaults.string(forKey: Keys.language) ?? AppLanguage.systemDefault.rawValue)
        autoStartOnBoot = defaults.object(forKey: Keys.autoStartOnBoot) as? Bool ?? false
        isDcAuto = defaults.object(forKey: Keys.isDcAuto) as? Bool ?? true
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

    func buildDcIps() -> String {
        if isDcAuto { return "" }

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
        guard experimentalFeaturesEnabled, cfWorkerEnabled else { return true }
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
        guard experimentalFeaturesEnabled, customCfDomainEnabled else { return true }
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
        guard experimentalFeaturesEnabled, fakeTlsEnabled else { return true }
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
        (experimentalFeaturesEnabled && fakeTlsEnabled) ? fakeTlsDomain.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// True when the custom DoH field is either empty (not used) or a valid
    /// https URL — unlike Worker/FakeTLS this isn't gated by its own toggle,
    /// it's just an optional extra endpoint added to whichever built-ins are on.
    var isDohCustomURLValid: Bool {
        guard experimentalFeaturesEnabled else { return true }
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
        (experimentalFeaturesEnabled && cfWorkerEnabled) ? cfWorkerURL.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Whether the Worker fallback is actually active — used both to start
    /// the proxy and to reflect the "+W" mode badge on the Proxy tab.
    var effectiveCfWorkerEnabled: Bool {
        experimentalFeaturesEnabled && cfWorkerEnabled
    }

    var effectiveCustomCfDomain: String {
        (experimentalFeaturesEnabled && customCfDomainEnabled) ? customCfDomain : ""
    }

    var effectiveFakeTlsEnabled: Bool {
        experimentalFeaturesEnabled && fakeTlsEnabled
    }

    /// Built-in DoH resolvers are NOT gated by the experimental toggle.
    /// Gating them meant that turning experimental features off left
    /// dohEndpoints empty in the core, so resolveDoH() skipped its DoH phase
    /// entirely and fell straight through to plaintext UDP:53 — a silent
    /// privacy downgrade for ordinary users. Encrypted DNS is baseline
    /// behaviour; only the custom endpoint below is experimental.
    /// Fragmentation is an experimental transport tweak like Worker/FakeTLS.
    var effectiveFragmentEnabled: Bool { experimentalFeaturesEnabled && fragmentEnabled }

    var effectiveTlsFingerprint: Int { experimentalFeaturesEnabled ? tlsFingerprint : 0 }

    var effectiveDohUseCloudflare: Bool { dohUseCloudflare }
    var effectiveDohUseGoogle: Bool { dohUseGoogle }
    var effectiveDohUseQuad9: Bool { dohUseQuad9 }
    var effectiveDohUseAdguard: Bool { dohUseAdguard }

    var effectiveDohCustomURL: String {
        experimentalFeaturesEnabled ? dohCustomURL.trimmingCharacters(in: .whitespacesAndNewlines) : ""
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

    /// Host to put in the proxy link — mirrors the configured bind IP exactly,
    /// so what's typed in Settings is what shows up in the link and clipboard.
    private func linkHost() -> String {
        effectiveBindIp()
    }

    func proxyUrl() -> String {
        let p = Int(port) ?? 1443
        return "https://t.me/proxy?server=\(linkHost())&port=\(p)&secret=\(secretWithPrefix())"
    }

    /// Native Telegram app deep link — opens Telegram directly instead of
    /// going through Safari/Universal Links, which can land on the t.me web
    /// preview instead of the app depending on how iOS resolves the link.
    func tgProxyUrl() -> String {
        let p = Int(port) ?? 1443
        return "tg://proxy?server=\(linkHost())&port=\(p)&secret=\(secretWithPrefix())"
    }
}
