import Foundation

class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    static let defaultPort = "1443"
    static let defaultPoolSize = 4
    static let defaultDc2Ip = "149.154.167.220"
    static let defaultDc4Ip = "149.154.167.220"

    private enum Keys {
        static let port = "port"
        static let poolSize = "pool_size"
        static let secretKey = "secret_key"
        static let cfproxyEnabled = "cfproxy_enabled"
        static let customCfDomainEnabled = "custom_cf_domain_enabled"
        static let customCfDomain = "custom_cf_domain"
        static let cfWorkerEnabled = "cf_worker_enabled"
        static let cfWorkerURL = "cf_worker_url"
        static let fakeTlsEnabled = "fake_tls_enabled"
        static let fakeTlsDomain = "fake_tls_domain"
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
    @Published var logShowNull: Bool {
        didSet { defaults.set(logShowNull, forKey: Keys.logShowNull) }
    }

    init() {
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
    var isCfWorkerURLValid: Bool {
        guard experimentalFeaturesEnabled, cfWorkerEnabled else { return true }
        let trimmed = cfWorkerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }

    /// True when the custom CF domain field is usable: a bare hostname, no
    /// scheme/path (this gets templated into kws{dc}.<domain>/apiws internally).
    var isCustomCfDomainValid: Bool {
        guard experimentalFeaturesEnabled, customCfDomainEnabled else { return true }
        let trimmed = customCfDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("://"),
              !trimmed.contains("/"),
              trimmed.contains(".") else {
            return false
        }
        return true
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

    var effectiveDohUseCloudflare: Bool { experimentalFeaturesEnabled && dohUseCloudflare }
    var effectiveDohUseGoogle: Bool { experimentalFeaturesEnabled && dohUseGoogle }
    var effectiveDohUseQuad9: Bool { experimentalFeaturesEnabled && dohUseQuad9 }
    var effectiveDohUseAdguard: Bool { experimentalFeaturesEnabled && dohUseAdguard }

    var effectiveDohCustomURL: String {
        experimentalFeaturesEnabled ? dohCustomURL.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    func proxyUrl() -> String {
        let p = Int(port) ?? 1443
        let secret = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeSecret = secret.isEmpty ? "00000000000000000000000000000000" : secret
        return "https://t.me/proxy?server=127.0.0.1&port=\(p)&secret=dd\(safeSecret)"
    }

    /// Native Telegram app deep link — opens Telegram directly instead of
    /// going through Safari/Universal Links, which can land on the t.me web
    /// preview instead of the app depending on how iOS resolves the link.
    func tgProxyUrl() -> String {
        let p = Int(port) ?? 1443
        let secret = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeSecret = secret.isEmpty ? "00000000000000000000000000000000" : secret
        return "tg://proxy?server=127.0.0.1&port=\(p)&secret=dd\(safeSecret)"
    }
}
