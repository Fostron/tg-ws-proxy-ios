import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var settings: SettingsStore
    @State private var showIpSetup = false
    @State private var showIslandSettings = false
    /// Numeric keypads have no return key, so without an explicit Done button
    /// the keyboard can't be dismissed by tapping anywhere obvious.
    @FocusState private var focusedField: NumericField?

    private enum NumericField: Hashable { case ip, port }

    private var accent: Color { AppPalette(from: settings.themePalette).accent }

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassGroup(spacing: 16) {
                    VStack(spacing: 16) {
                        connectionCard
                        poolCard
                        secretCard
                        routeCard
                        cdnCard
                        workerCard
                        autoStartCard

                        // FakeTLS/nginx, TLS fingerprint, SNI spoofing,
                        // fragmentation and DoH tuning break more than they
                        // fix for most people; they only ship in the test
                        // build (Fostron/test).
                        if SettingsStore.experimentalBuild {
                            experimentalCard

                            if settings.experimentalFeaturesEnabled {
                                Group {
                                    fakeTlsCard
                                    nginxCard
                                    tlsFingerprintCard
                                    fakeSniCard
                                    fragmentCard
                                    dohCard
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top)
                                            .combined(with: .opacity)
                                            .combined(with: .scale(scale: 0.96, anchor: .top)),
                                        removal: .opacity
                                            .combined(with: .scale(scale: 0.96, anchor: .top))
                                    )
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.42, dampingFraction: 0.82),
                           value: settings.experimentalFeaturesEnabled)
            }
            .appBackground()
            .navigationTitle(settings.t("settings.title"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(settings.t("ip_sheet.done")) { focusedField = nil }
                }
            }
            .sheet(isPresented: $showIpSetup) {
                IpSetupSheet()
            }
            .sheet(isPresented: $showIslandSettings) {
                IslandSettingsView()
            }
        }
    }

    // MARK: - Cards

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("network", settings.t("settings.connection"))

            HStack {
                Text("IP")
                Spacer()
                ipQuickMenu
                TextField("127.0.0.1", text: $settings.bindIp)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 130)
                    .disabled(proxyManager.isRunning)
                    .focused($focusedField, equals: .ip)
                    // decimalPad has no letters, but paste can still bring
                    // them in — strip anything that isn't a digit or a dot.
                    .onChange(of: settings.bindIp) { newValue in
                        let cleaned = newValue.filter { $0.isNumber || $0 == "." }
                        if cleaned != newValue { settings.bindIp = cleaned }
                    }
            }

            if !settings.isBindIpValid {
                Text("Неверный IPv4-адрес")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Text(settings.t("settings.port"))
                Spacer()
                TextField("1443", text: $settings.port)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(proxyManager.isRunning)
                    .focused($focusedField, equals: .port)
                    .onChange(of: settings.port) { newValue in
                        let cleaned = String(newValue.filter { $0.isNumber }.prefix(5))
                        if cleaned != newValue { settings.port = cleaned }
                    }
            }

            // Direct DC addresses apply regardless of the CDN toggle now: CDN
            // is a fallback tier (or the first one, per the route setting),
            // not a mode that replaces Direct.
            Button(action: { showIpSetup = true }) {
                HStack {
                    Image(systemName: "gearshape")
                        .foregroundColor(accent)
                    Text(settings.t("settings.configure_dc"))
                        .fontWeight(.semibold)
                }
            }
            .disabled(proxyManager.isRunning)
        }
        .padding(18)
        .glassCard()
    }

    /// One tap between "only this iPhone" and "this iPhone's address in the
    /// current Wi-Fi / hotspot", instead of typing IPs. The list is read
    /// fresh every time the menu opens.
    private var ipQuickMenu: some View {
        Menu {
            Button {
                settings.bindIp = SettingsStore.defaultBindIp
            } label: {
                Label("127.0.0.1 — \(settings.t("settings.ip.local"))", systemImage: "iphone")
            }

            let addresses = NetworkInfo.localIPv4()
            if addresses.isEmpty {
                Text(settings.t("settings.ip.no_wifi"))
            }
            ForEach(addresses, id: \.self) { address in
                Button {
                    settings.bindIp = address.ip
                } label: {
                    Label("\(address.ip) — \(settings.t(address.kind == .wifi ? "settings.ip.wifi" : "settings.ip.hotspot"))",
                          systemImage: address.kind == .wifi ? "wifi" : "personalhotspot")
                }
            }

            Button {
                settings.bindIp = "0.0.0.0"
            } label: {
                Label("0.0.0.0 — \(settings.t("settings.ip.all"))", systemImage: "network")
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title3)
                .foregroundColor(accent)
        }
        .disabled(proxyManager.isRunning)
        .accessibilityLabel(settings.t("settings.ip.pick"))
    }

    private var poolCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("layers", settings.t("settings.ws_pool"))

            Picker(settings.t("settings.pool_size"), selection: $settings.poolSize) {
                Text("2").tag(2)
                Text("4").tag(4)
                Text("6").tag(6)
            }
            .pickerStyle(.segmented)
            .disabled(proxyManager.isRunning)
        }
        .padding(18)
        .glassCard()
    }

    private var secretCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("key", settings.t("settings.secret_key"))

            HStack {
                Text(settings.secretKey)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: { settings.generateNewSecret() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(accent)
                }
                .disabled(proxyManager.isRunning)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("arrow.triangle.branch", settings.t("settings.route"))

            Picker("", selection: $settings.routeMode) {
                Text(settings.t("settings.route.auto")).tag(RouteMode.auto)
                Text("CDN").tag(RouteMode.cdnFirst)
                Text("Worker").tag(RouteMode.workerFirst)
            }
            .pickerStyle(.segmented)
            .disabled(proxyManager.isRunning)

            Text(routeHint)
                .font(.caption)
                .foregroundColor(routeHintIsWarning ? .orange : .secondary)
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.routeMode)
    }

    private var routeHintIsWarning: Bool {
        switch settings.routeMode {
        case .auto: return false
        case .cdnFirst: return !settings.cfproxyEnabled
        case .workerFirst: return !(settings.effectiveCfWorkerEnabled && !settings.cfWorkerURL.isEmpty)
        }
    }

    private var routeHint: String {
        if routeHintIsWarning { return settings.t("settings.route.not_configured") }
        switch settings.routeMode {
        case .auto: return settings.t("settings.route.auto_desc")
        case .cdnFirst: return settings.t("settings.route.cdn_desc")
        case .workerFirst: return settings.t("settings.route.worker_desc")
        }
    }

    private var cdnCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.cfproxyEnabled) {
                header("cloud", settings.t("settings.cf_cdn"))
            }
            .disabled(proxyManager.isRunning)

            // Own domain is the most reliable CDN setup (the shared public
            // list hits Cloudflare's limits), so it's a regular option.
            if settings.cfproxyEnabled {
                Toggle(settings.t("settings.custom_domain"), isOn: $settings.customCfDomainEnabled)
                    .disabled(proxyManager.isRunning)

                if settings.customCfDomainEnabled {
                    TextField("mydomain.com (можно несколько через запятую)", text: $settings.customCfDomain)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(proxyManager.isRunning)

                    hint(
                        valid: settings.isCustomCfDomainValid,
                        invalidText: settings.t("settings.custom_domain_invalid"),
                        validText: settings.t("settings.custom_domain_valid")
                    )
                }
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.cfproxyEnabled)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.customCfDomainEnabled)
    }

    private var experimentalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $settings.experimentalFeaturesEnabled) {
                header("flask", settings.t("settings.experimental.title"))
            }
            .disabled(proxyManager.isRunning)

            Text(settings.experimentalFeaturesEnabled
                 ? settings.t("settings.experimental.desc_on")
                 : settings.t("settings.experimental.desc_off"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .glassCard()
    }

    private var workerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.cfWorkerEnabled) {
                header("bolt.horizontal.circle", settings.t("settings.cf_worker"))
            }
            .disabled(proxyManager.isRunning)

            if settings.cfWorkerEnabled {
                TextField("name-1234.user.workers.dev (можно несколько через запятую)", text: $settings.cfWorkerURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(proxyManager.isRunning)

                hint(
                    valid: settings.isCfWorkerURLValid,
                    invalidText: settings.t("settings.cf_worker_invalid"),
                    validText: settings.t("settings.cf_worker_valid")
                )
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.cfWorkerEnabled)
    }

    private var fakeTlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.fakeTlsEnabled) {
                header("lock.shield", settings.t("settings.faketls"))
            }
            .disabled(proxyManager.isRunning)

            if settings.fakeTlsEnabled {
                TextField("proxy.example.com", text: $settings.fakeTlsDomain)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(proxyManager.isRunning)

                hint(
                    valid: settings.isFakeTlsDomainValid,
                    invalidText: settings.t("settings.faketls_invalid"),
                    validText: settings.t("settings.faketls_valid")
                )

                TextField(settings.t("settings.faketls_mask_placeholder"), text: $settings.fakeTlsMaskHost)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(proxyManager.isRunning)

                hint(
                    valid: settings.isFakeTlsMaskHostValid,
                    invalidText: settings.t("settings.faketls_mask_invalid"),
                    validText: settings.t("settings.faketls_mask_hint")
                )
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.fakeTlsEnabled)
    }

    private var nginxCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.proxyProtocolEnabled) {
                header("server.rack", settings.t("settings.nginx"))
            }
            .disabled(proxyManager.isRunning)

            Text(settings.t("settings.nginx_desc"))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text(settings.t("settings.link_host"))
                Spacer()
                TextField("proxy.example.com", text: $settings.linkHost)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .disabled(proxyManager.isRunning)
            }

            HStack {
                Text(settings.t("settings.link_port"))
                Spacer()
                TextField("443", text: $settings.linkPort)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(proxyManager.isRunning)
                    .onChange(of: settings.linkPort) { newValue in
                        let cleaned = String(newValue.filter { $0.isNumber }.prefix(5))
                        if cleaned != newValue { settings.linkPort = cleaned }
                    }
            }

            hint(
                valid: settings.isLinkHostValid && settings.isLinkPortValid,
                invalidText: settings.t("settings.link_invalid"),
                validText: settings.t("settings.link_hint")
            )

            if settings.proxyProtocolEnabled && !settings.bindIpIsExposed {
                Text(settings.t("settings.nginx_loopback_warning"))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var fakeSniCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.fakeSniEnabled) {
                header("eye.slash", "Подмена SNI")
            }
            .disabled(proxyManager.isRunning)

            if settings.fakeSniEnabled {
                TextField("discord.com", text: $settings.fakeSniValue)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(proxyManager.isRunning)

                if !settings.isFakeSniValid {
                    Text("Только домен, без https:// и пути")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Приманка обязана сама быть за Cloudflare. Иначе edge оборвёт рукопожатие (tls: handshake failure) и весь CDN-тир ляжет — yandex.ru и microsoft.com не подойдут")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.fakeSniEnabled)
    }

    private var tlsFingerprintCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("signature", "TLS-отпечаток")

            Picker("", selection: $settings.tlsFingerprint) {
                Text("Стандартный").tag(0)
                Text("Firefox").tag(1)
                Text("Chrome").tag(2)
                Text("Safari").tag(3)
            }
            .pickerStyle(.segmented)
            .disabled(proxyManager.isRunning)

            Text(settings.tlsFingerprint == 0
                 ? "Стандартный стек Go — узнаваем по JA3/JA4, но максимально совместим"
                 : "Маскирует рукопожатие под браузер. Если соединение обрывается сразу (EOF), вернитесь на стандартный")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.tlsFingerprint)
    }

    private var fragmentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.fragmentEnabled) {
                header("scissors", "Фрагментация ClientHello")
            }
            .disabled(proxyManager.isRunning)

            if settings.fragmentEnabled {
                Stepper("Первый сегмент: \(settings.fragmentFirstSize) Б",
                        value: $settings.fragmentFirstSize, in: 1...16)
                    .disabled(proxyManager.isRunning)

                Stepper("Пауза: \(settings.fragmentDelayMs) мс",
                        value: $settings.fragmentDelayMs, in: 0...100, step: 5)
                    .disabled(proxyManager.isRunning)

                Text("Разбивает TLS-рукопожатие на части, чтобы имя домена не попало целиком в первый пакет — аналог split2 из zapret")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.fragmentEnabled)
    }

    private var dohCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("network", settings.t("settings.doh"))

            Toggle("Cloudflare", isOn: $settings.dohUseCloudflare)
                .disabled(proxyManager.isRunning)
            Toggle("Google", isOn: $settings.dohUseGoogle)
                .disabled(proxyManager.isRunning)
            Toggle("Quad9", isOn: $settings.dohUseQuad9)
                .disabled(proxyManager.isRunning)
            Toggle("AdGuard", isOn: $settings.dohUseAdguard)
                .disabled(proxyManager.isRunning)

            TextField(settings.t("settings.doh_custom_placeholder"), text: $settings.dohCustomURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(proxyManager.isRunning)

            hint(
                valid: settings.isDohCustomURLValid,
                invalidText: settings.t("settings.doh_invalid"),
                validText: settings.t("settings.doh_valid")
            )
        }
        .padding(18)
        .glassCard()
    }

    private var autoStartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.autoStartOnBoot) {
                header("power", settings.t("settings.autostart"))
            }

            Divider()

            Toggle(isOn: $settings.showLiveActivity) {
                header("arrow.up.arrow.down", settings.t("settings.live_activity"))
            }
            .onChange(of: settings.showLiveActivity) { show in
                // Takes effect immediately; the Settings tab is on screen, so
                // the app is in the foreground as ActivityKit requires.
                guard proxyManager.isRunning else { return }
                if show {
                    LiveActivityManager.shared.start(route: settings.effectiveRouteLabel,
                                                     language: settings.language.rawValue,
                                                     style: settings.resolvedIslandStyle)
                } else {
                    LiveActivityManager.shared.end()
                }
            }

            Text(settings.t("settings.live_activity_desc"))
                .font(.caption)
                .foregroundColor(.secondary)

            if settings.showLiveActivity {
                Button {
                    showIslandSettings = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(accent)
                        Text(settings.t("settings.live_activity_customize"))
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.showLiveActivity)
    }

    // MARK: - Helpers

    private func header(_ icon: String, _ title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(accent)
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(accent)
        }
    }

    private func hint(valid: Bool, invalidText: String, validText: String) -> some View {
        Text(valid ? validText : invalidText)
            .font(.caption)
            .foregroundColor(valid ? .secondary : .red)
    }
}

struct IpSetupSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if settings.isExperimentalMode {
                    Section(settings.t("ip_sheet.main_dc")) {
                        DcInput(label: "DC1", value: $settings.dc1)
                        DcInput(label: "DC2", value: $settings.dc2)
                        DcInput(label: "DC3", value: $settings.dc3)
                        DcInput(label: "DC4", value: $settings.dc4)
                        DcInput(label: "DC5", value: $settings.dc5)
                        DcInput(label: "DC203", value: $settings.dc203)
                    }

                    Section(settings.t("ip_sheet.media_dc")) {
                        DcInput(label: "DC1m", value: $settings.dc1m)
                        DcInput(label: "DC2m", value: $settings.dc2m)
                        DcInput(label: "DC3m", value: $settings.dc3m)
                        DcInput(label: "DC4m", value: $settings.dc4m)
                        DcInput(label: "DC5m", value: $settings.dc5m)
                        DcInput(label: "DC203m", value: $settings.dc203m)
                    }
                } else {
                    Section(settings.t("ip_sheet.dc_addresses")) {
                        DcInput(label: "DC2", value: $settings.dc2)
                        DcInput(label: "DC4", value: $settings.dc4)
                    }
                }

                Section {
                    Toggle(settings.t("ip_sheet.experimental_mode"), isOn: $settings.isExperimentalMode)
                }
            }
            .appBackground()
            .navigationTitle(settings.t("ip_sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(settings.t("ip_sheet.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DcInput: View {
    let label: String
    @Binding var value: String
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.blue)
                .frame(width: 60, alignment: .leading)
            TextField(settings.t("ip_sheet.ip_placeholder"), text: $value)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}
