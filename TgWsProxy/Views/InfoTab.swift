import SwiftUI

struct InfoTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var logManager: LogManager
    @State private var showHelp = false

    /// Where "Support development" and bug reports go.
    static let repoURL = "https://github.com/Fostron/tg-ws-proxy-ios"

    private var accent: Color { AppPalette(from: settings.themePalette).accent }

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassGroup(spacing: 16) {
                    VStack(spacing: 16) {
                        heroCard

                        actionSection
                        projectSection

                        Spacer(minLength: 20)
                    }
                }
                .padding()
            }
            .appBackground()
            .navigationTitle(settings.t("info.title"))
            .sheet(isPresented: $showHelp) {
                HelpSheet()
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label(settings.t("info.badge.ios_port"), systemImage: "apple.logo")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.3))
                    .clipShape(Capsule())

                Label(settings.t("info.badge.flowseal_base"), systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.2))
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                Text("Telegram WS Proxy")
                    .font(.title)
                    .fontWeight(.black)

                Text(settings.t("info.app_desc"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            supportButton
        }
        .padding(20)
        .glassCard(cornerRadius: 24, tint: accent)
    }

    private var supportButton: some View {
        let label = HStack {
            Image(systemName: "heart.fill")
            Text(settings.t("info.support"))
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)

        if #available(iOS 26.0, *) {
            return AnyView(
                Button(action: { openUrl(InfoTab.repoURL) }) { label }
                    .buttonStyle(.glassProminent)
                    .tint(accent)
            )
        } else {
            return AnyView(
                Button(action: { openUrl(InfoTab.repoURL) }) { label }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            )
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: settings.t("info.actions"), icon: "bolt.fill", count: 3, accent: accent)

            ActionTile(
                title: settings.t("info.help.title"),
                subtitle: settings.t("info.help.subtitle"),
                icon: "questionmark.circle.fill",
                accent: accent,
                action: { showHelp = true }
            )

            ActionTile(
                title: settings.t("info.issues.title"),
                subtitle: settings.t("info.issues.subtitle"),
                icon: "ant.fill",
                accent: accent,
                action: { openUrl(InfoTab.repoURL + "/issues/new") }
            )

            ActionTile(
                title: settings.t("info.report.title"),
                subtitle: settings.t("info.report.subtitle"),
                icon: "doc.on.clipboard.fill",
                accent: accent,
                action: copyReport
            )
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: settings.t("info.about"), icon: "chevron.left.forwardslash.chevron.right", count: 3, accent: accent)

            LinkRow(
                title: settings.t("info.link.original.title"),
                subtitle: settings.t("info.link.original.subtitle"),
                icon: "arrow.triangle.branch",
                accent: accent,
                url: "https://github.com/Flowseal/tg-ws-proxy"
            )

            LinkRow(
                title: settings.t("info.link.android.title"),
                subtitle: settings.t("info.link.android.subtitle"),
                icon: "smartphone",
                accent: accent,
                url: "https://github.com/amurcanov/tg-ws-proxy-android"
            )

            LinkRow(
                title: settings.t("info.link.mtproto.title"),
                subtitle: settings.t("info.link.mtproto.subtitle"),
                icon: "doc.text",
                accent: accent,
                url: "https://core.telegram.org/mtproto/mtproto-transports"
            )
        }
    }

    private func copyReport() {
        var report = "App: TG WS Proxy iOS\n"
        report += "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")\n"
        report += "Settings: port=\(settings.port), pool=\(settings.poolSize), route=\(settings.routeMode), cf=\(settings.cfproxyEnabled), "
            + "worker=\(settings.effectiveCfWorkerEnabled), ownDomain=\(!settings.effectiveCustomCfDomain.isEmpty), "
            + "fakeTls=\(settings.effectiveFakeTlsEnabled), nginx=\(settings.effectiveProxyProtocol), "
            + "dc=\(settings.buildDcIps()), experimental=\(settings.experimentalOn), "
            + "build=\(SettingsStore.experimentalBuild ? "test" : "public")\n"
        report += "Stats: \(proxyManager.stats.description)\n"
        let errors = logManager.logs.filter { $0.level == .error }.suffix(5)
        if errors.isEmpty {
            report += "Errors: none\n"
        } else {
            report += "Errors:\n" + errors.map { "- \($0.message)" }.joined(separator: "\n") + "\n"
        }
        UIPasteboard.general.string = report
    }

    private func openUrl(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    let count: Int
    let accent: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(accent)
                .frame(width: 24)
            Text(title)
                .font(.headline)
                .foregroundColor(accent)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .padding(.top, 8)
    }
}

private struct ActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

private struct LinkRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let url: String

    var body: some View {
        Button(action: {
            if let urlObj = URL(string: url) {
                UIApplication.shared.open(urlObj)
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

struct HelpSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var configCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection(titleKey: "help.section.route.title", textKey: "help.section.route.text")
                    Divider()
                    helpSection(titleKey: "help.section.cf_cdn.title", textKey: "help.section.cf_cdn.text")
                    Divider()
                    helpSection(titleKey: "help.section.ws_pool.title", textKey: "help.section.ws_pool.text")
                    Divider()
                    helpSection(titleKey: "help.section.secret.title", textKey: "help.section.secret.text")
                    Divider()
                    helpSection(titleKey: "help.section.dc.title", textKey: "help.section.dc.text")
                    Divider()
                    helpSection(titleKey: "help.section.worker.title", textKey: "help.section.worker.text")
                    Divider()
                    helpSection(titleKey: "help.section.island.title", textKey: "help.section.island.text")
                    Divider()
                    // Only the test build has these features at all.
                    if SettingsStore.experimentalBuild {
                        helpSection(titleKey: "help.section.experimental.title", textKey: "help.section.experimental.text")
                        Divider()
                        helpSection(titleKey: "help.section.faketls.title", textKey: "help.section.faketls.text")
                        nginxConfigBlock
                        Divider()
                        helpSection(titleKey: "help.section.doh.title", textKey: "help.section.doh.text")
                        Divider()
                    }
                    helpSection(titleKey: "help.section.slow.title", textKey: "help.section.slow.text")
                }
                .padding()
            }
            .appBackground()
            .navigationTitle(settings.t("info.help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(settings.t("help.close")) { dismiss() }
                }
            }
        }
    }

    /// nginx stream config filled in from the current settings where they're
    /// already set, placeholders otherwise.
    private var nginxConfig: String {
        let domain = settings.fakeTlsDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let sni = domain.isEmpty ? "proxy.example.com" : domain
        let bind = settings.effectiveBindIp()
        let phoneIp = (bind == "0.0.0.0" || bind.hasPrefix("127.")) ? "192.168.1.50" : bind
        let port = Int(settings.port) ?? 1443
        return """
        # nginx.conf, на верхнем уровне (рядом с http {}).
        # Нужен модуль stream (Debian/Ubuntu: libnginx-mod-stream).
        stream {
            map $ssl_preread_server_name $tg_upstream {
                hostnames;
                \(sni)  tgwsproxy;
                default  website;
            }

            upstream tgwsproxy {
                server \(phoneIp):\(port);  # IP iPhone и порт из приложения
            }

            upstream website {
                # обычный HTTPS-сайт; он должен слушать
                # с proxy_protocol: listen 8443 ssl proxy_protocol;
                server 127.0.0.1:8443;
            }

            server {
                listen 443;
                ssl_preread on;
                proxy_protocol on;
                proxy_pass $tg_upstream;
            }
        }
        """
    }

    private var nginxConfigBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(nginxConfig)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                UIPasteboard.general.string = nginxConfig
                configCopied = true
            } label: {
                Label(settings.t(configCopied ? "help.section.nginx.copied" : "help.section.nginx.copy"),
                      systemImage: configCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
            }
        }
    }

    private func helpSection(titleKey: String, textKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t(titleKey))
                .font(.headline)
                .foregroundColor(.blue)
            Text(settings.t(textKey))
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}
