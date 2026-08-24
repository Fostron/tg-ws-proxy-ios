import SwiftUI
import CoreLocation

struct ConnectionTab: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var settings: SettingsStore

    @State private var isStarting = false
    @State private var showThemePicker = false
    @State private var locationManager = CLLocationManager()

    private var palette: AppPalette { AppPalette(from: settings.themePalette) }

    private var statusText: String {
        if isStarting { return settings.t("conn.status.connecting") }
        if proxyManager.isRunning { return settings.t("conn.status.connected") }
        return settings.t("conn.status.disconnected")
    }

    private var modeLabel: String {
        let base = settings.cfproxyEnabled ? "CF" : "Direct"
        let workerActive = settings.effectiveCfWorkerEnabled && settings.isCfWorkerURLValid && !settings.cfWorkerURL.isEmpty
        return workerActive ? "\(base)+W" : base
    }

    private var statusColor: Color {
        if proxyManager.isRunning { return AppColors.connected }
        if isStarting { return AppColors.warning }
        return .gray
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 16) {
                    Spacer()

                    powerButton

                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(statusColor)

                    applyButton

                    statsCard
                        .padding(.horizontal)

                    proxyUrlCard
                        .padding(.horizontal)

                    // Fixed-height slot: the line used to be inserted into the
                    // stack when the proxy started, which grew the content and
                    // made the surrounding Spacers shove everything upward.
                    // Reserving the space keeps the layout still and lets the
                    // text simply fade in.
                    Text(proxyManager.stats.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 4)
                        .frame(height: 20)
                        .opacity(proxyManager.isRunning ? 1 : 0)
                        .animation(.easeInOut(duration: 0.35), value: proxyManager.isRunning)
                        .animation(.easeInOut(duration: 0.25), value: proxyManager.stats.description)

                    Spacer()
                }

                themePickerButton
                    .padding(.top, 8)
                    .padding(.trailing, 16)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // MARK: - Components

    private var powerButton: some View {
        let button = Button(action: toggleProxy) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 56))
                .foregroundColor(proxyManager.isRunning ? AppColors.connected : .gray.opacity(0.6))
                .frame(width: 176, height: 176)
        }
        .scaleEffect(proxyManager.isRunning ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.4), value: proxyManager.isRunning)

        if #available(iOS 26.0, *) {
            return AnyView(
                button
                    .buttonStyle(.plain)
                    .glassEffect(
                        Glass.regular.tint(statusColor.opacity(0.18)).interactive(),
                        in: Circle()
                    )
            )
        } else {
            return AnyView(
                button
                    .buttonStyle(.plain)
                    .background(
                        Circle()
                            .fill(proxyManager.isRunning ? AppColors.connectedContainer : Color.gray.opacity(0.08))
                    )
            )
        }
    }

    private var applyButton: some View {
        let label = Text(settings.t("conn.apply"))
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)

        if #available(iOS 26.0, *) {
            return AnyView(
                Button(action: openTelegram) { label }
                    .buttonStyle(.glassProminent)
                    .tint(palette.accent)
                    .disabled(!proxyManager.isRunning)
                    .padding(.horizontal)
            )
        } else {
            return AnyView(
                Button(action: openTelegram) { label }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(!proxyManager.isRunning)
                    .padding(.horizontal)
            )
        }
    }

    private var statsCard: some View {
        HStack {
            StatusItem(title: modeLabel, subtitle: settings.t("conn.stat.mode"))
            Divider().frame(height: 30)
            StatusItem(title: "\(settings.poolSize)", subtitle: settings.t("conn.stat.pool"))
            Divider().frame(height: 30)
            StatusItem(title: settings.port, subtitle: settings.t("conn.stat.port"))
            Divider().frame(height: 30)
            StatusItem(
                title: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                subtitle: settings.t("conn.stat.ver")
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .glassCard(cornerRadius: 20)
    }

    private var proxyUrlCard: some View {
        HStack {
            Text(settings.proxyUrl())
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: copyProxyUrl) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(palette.accent)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    private var themePickerButton: some View {
        let button = Button {
            showThemePicker = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 16))
                .foregroundColor(palette.accent)
                .frame(width: 40, height: 40)
        }

        return Group {
            if #available(iOS 26.0, *) {
                button
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                button
                    .buttonStyle(.plain)
                    .background(Circle().fill(.regularMaterial))
            }
        }
        .popover(isPresented: $showThemePicker) {
            Group {
                if #available(iOS 16.4, *) {
                    ThemePaletteMenu(settings: settings)
                        .presentationCompactAdaptation(.popover)
                } else {
                    ThemePaletteMenu(settings: settings)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleProxy() {
        if proxyManager.isRunning {
            proxyManager.stop()
            isStarting = false
        } else {
            guard settings.isCfWorkerURLValid, settings.isCustomCfDomainValid,
                  settings.isFakeTlsDomainValid, settings.isDohCustomURLValid, settings.isBindIpValid else {
                isStarting = false
                return
            }

            requestBackgroundPermissions()
            isStarting = true
            let dcIps = settings.buildDcIps()
            let port = Int(settings.port) ?? 1443
            let bindIp = settings.effectiveBindIp()
            // Advanced networking (Worker/FakeTLS/DoH/custom domain) only
            // takes effect when Experimental Features is unlocked, even if
            // the individual toggles were left on from before.
            let cfDomain = settings.effectiveCustomCfDomain
            let workerEnabled = settings.effectiveCfWorkerEnabled
            let workerURL = settings.effectiveCfWorkerURL()
            let tlsEnabled = settings.effectiveFakeTlsEnabled
            let tlsDomain = settings.effectiveFakeTlsDomain()
            let fragOn = settings.effectiveFragmentEnabled
            let fragSize = settings.fragmentFirstSize
            let fragDelay = settings.fragmentDelayMs
            let tlsFp = settings.effectiveTlsFingerprint
            let dohCf = settings.effectiveDohUseCloudflare
            let dohGoogle = settings.effectiveDohUseGoogle
            let dohQuad9 = settings.effectiveDohUseQuad9
            let dohAdguard = settings.effectiveDohUseAdguard
            let dohCustom = settings.effectiveDohCustomURL

            DispatchQueue.global(qos: .userInitiated).async {
                let started = proxyManager.start(
                    bindIp: bindIp,
                    port: port,
                    dcIps: dcIps,
                    poolSize: settings.poolSize,
                    cfEnabled: settings.cfproxyEnabled,
                    cfPriority: true,
                    cfDomain: cfDomain,
                    cfWorkerEnabled: workerEnabled,
                    cfWorkerURL: workerURL,
                    fakeTlsEnabled: tlsEnabled,
                    fakeTlsDomain: tlsDomain,
                    fragmentEnabled: fragOn,
                    fragmentFirstSize: fragSize,
                    fragmentDelayMs: fragDelay,
                    tlsFingerprint: tlsFp,
                    dohUseCloudflare: dohCf,
                    dohUseGoogle: dohGoogle,
                    dohUseQuad9: dohQuad9,
                    dohUseAdguard: dohAdguard,
                    dohCustomURL: dohCustom,
                    secretKey: settings.secretKey
                )
                DispatchQueue.main.async {
                    isStarting = false
                    _ = started
                }
            }
        }
    }

    private func requestBackgroundPermissions() {
        locationManager.requestAlwaysAuthorization()
        locationManager.requestWhenInUseAuthorization()
    }

    private func openTelegram() {
        if let tgUrl = URL(string: settings.tgProxyUrl()), UIApplication.shared.canOpenURL(tgUrl) {
            UIApplication.shared.open(tgUrl)
            return
        }
        if let webUrl = URL(string: settings.proxyUrl()) {
            UIApplication.shared.open(webUrl)
        }
    }

    private func copyProxyUrl() {
        UIPasteboard.general.string = settings.proxyUrl()
    }
}

private struct StatusItem: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }
}

/// Compact stand-in for Android's FloatingToolbar theme/palette picker —
/// same purpose (pick light/dark/system + accent palette + UI language),
/// presented as a simple popover instead of a draggable floating panel.
private struct ThemePaletteMenu: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settings.t("theme.title"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach([("system", settings.t("theme.system"), "circle.lefthalf.filled"),
                     ("light", settings.t("theme.light"), "sun.max"),
                     ("dark", settings.t("theme.dark"), "moon")], id: \.0) { mode, label, icon in
                Button {
                    settings.themeMode = mode
                } label: {
                    HStack {
                        Image(systemName: icon)
                        Text(label)
                        Spacer()
                        if settings.themeMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }

            Divider().padding(.vertical, 4)

            Text(settings.t("palette.title"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                ForEach(AppPalette.allCases) { p in
                    Button {
                        settings.themePalette = p.rawValue
                    } label: {
                        Circle()
                            .fill(p.accent)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: settings.themePalette == p.rawValue ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            Divider().padding(.vertical, 4)

            Text(settings.t("language.title"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(AppLanguage.allCases) { lang in
                Button {
                    settings.language = lang
                } label: {
                    HStack {
                        Image(systemName: lang.symbolName)
                        Text(lang.displayName)
                        Spacer()
                        if settings.language == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(width: 210)
    }
}
