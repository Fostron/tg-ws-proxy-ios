import SwiftUI

@main
struct TgWsProxyApp: App {
    @StateObject private var proxyManager = ProxyManager.shared
    @StateObject private var settings = SettingsStore()
    @StateObject private var logManager = LogManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proxyManager)
                .environmentObject(settings)
                .environmentObject(logManager)
                .preferredColorScheme(AppTheme(from: settings.themeMode).colorScheme)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "tgwsproxy" else { return }
        
        if !proxyManager.isRunning {
            startProxyAndRedirect()
        }
    }
    
    private func startProxyAndRedirect() {
        guard settings.isCfWorkerURLValid, settings.isCustomCfDomainValid,
              settings.isFakeTlsDomainValid, settings.isDohCustomURLValid, settings.isBindIpValid else { return }

        let dcIps = settings.buildDcIps()
        let port = Int(settings.port) ?? 1443
        let bindIp = settings.effectiveBindIp()
        // Same gating as the manual start path in ConnectionTab: advanced
        // networking only applies when Experimental Features is unlocked.
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
            
            if started {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let url = URL(string: "tg://") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}
