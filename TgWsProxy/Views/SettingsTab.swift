import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var settings: SettingsStore
    @State private var showIpSetup = false
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
                        cdnCard
                        experimentalCard

                        if settings.experimentalFeaturesEnabled {
                            Group {
                                workerCard
                                fakeTlsCard
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

                        autoStartCard
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.42, dampingFraction: 0.82),
                           value: settings.experimentalFeaturesEnabled)
            }
            .navigationTitle(settings.t("settings.title"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showIpSetup) {
                IpSetupSheet()
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

            Button(action: { showIpSetup = true }) {
                HStack {
                    Image(systemName: "gearshape")
                        .foregroundColor(accent)
                    Text(settings.cfproxyEnabled ? settings.t("settings.cf_on") : settings.t("settings.configure_dc"))
                        .fontWeight(.semibold)
                }
            }
            .disabled(settings.cfproxyEnabled || proxyManager.isRunning)
        }
        .padding(18)
        .glassCard()
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

    private var cdnCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.cfproxyEnabled) {
                header("cloud", settings.t("settings.cf_cdn"))
            }
            .disabled(proxyManager.isRunning)
            .onChange(of: settings.cfproxyEnabled) { newValue in
                settings.isDcAuto = newValue
            }

            // "Свой домен" is an advanced networking option, so it stays
            // behind Experimental Features even though the base CDN toggle
            // above it is always visible.
            if settings.cfproxyEnabled && settings.experimentalFeaturesEnabled {
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
                TextField("www.microsoft.com", text: $settings.fakeTlsDomain)
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
            }
        }
        .padding(18)
        .glassCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: settings.fakeTlsEnabled)
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
        }
        .padding(18)
        .glassCard()
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
