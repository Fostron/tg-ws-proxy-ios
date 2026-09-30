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

    private var modeLabel: String { settings.effectiveRouteLabel }

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
            .appBackground()
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // MARK: - Components

    /// Off: the palette color. On: green with a soft glow.
    private var powerTint: Color {
        proxyManager.isRunning ? AppColors.connected : (isStarting ? AppColors.warning : palette.accent)
    }

    private var powerButton: some View {
        let button = Button(action: toggleProxy) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 56))
                .foregroundColor(powerTint)
                .frame(width: 176, height: 176)
        }
        .scaleEffect(proxyManager.isRunning ? 1.06 : 1.0)
        .shadow(color: proxyManager.isRunning ? AppColors.connected.opacity(0.45) : .clear, radius: 28)
        .animation(.easeInOut(duration: 0.4), value: proxyManager.isRunning)

        if #available(iOS 26.0, *) {
            return AnyView(
                button
                    .buttonStyle(.plain)
                    .glassEffect(
                        Glass.regular.tint(powerTint.opacity(0.22)).interactive(),
                        in: Circle()
                    )
            )
        } else {
            return AnyView(
                button
                    .buttonStyle(.plain)
                    .background(
                        Circle()
                            .fill(powerTint.opacity(proxyManager.isRunning ? 0.16 : 0.12))
                    )
                    .overlay(Circle().strokeBorder(powerTint.opacity(0.35), lineWidth: 1.5))
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
            guard settings.isLaunchConfigValid else {
                isStarting = false
                return
            }

            requestBackgroundPermissions()
            isStarting = true
            let config = settings.launchConfig()

            DispatchQueue.global(qos: .userInitiated).async {
                let started = proxyManager.start(config)
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

            // Each swatch shows the palette's pair of colors, so it's clear
            // what the background will look like before tapping it.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 5),
                      alignment: .leading, spacing: 10) {
                ForEach(AppPalette.allCases) { p in
                    Button {
                        settings.themePalette = p.rawValue
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [p.accent, p.companion],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: settings.themePalette == p.rawValue ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(p.displayName(settings.language))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            Text(AppPalette(from: settings.themePalette).displayName(settings.language))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            Divider().padding(.vertical, 4)

            Text(settings.t("backdrop.title"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            Picker("", selection: $settings.themeBackdrop) {
                ForEach(AppBackdrop.allCases) { b in
                    Text(settings.t("backdrop.\(b.rawValue)")).tag(b.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)

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
        .frame(width: 260)
    }
}
