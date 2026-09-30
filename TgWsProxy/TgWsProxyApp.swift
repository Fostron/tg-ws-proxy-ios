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
                .task {
                    // A Live Activity from a previous run that iOS killed
                    // would otherwise keep showing its last speeds.
                    if !proxyManager.isRunning {
                        LiveActivityManager.shared.endAll()
                    }
                    // The toggle used to be stored and never read: iOS cannot
                    // launch an app on boot, so "start on boot" was
                    // unachievable. Starting when the app is opened is the
                    // closest thing that actually works, and is what the
                    // label now promises.
                    guard settings.autoStartOnBoot, !proxyManager.isRunning else { return }
                    startProxyAndRedirect(openTelegram: false)
                }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "tgwsproxy" else { return }
        
        if !proxyManager.isRunning {
            startProxyAndRedirect()
        }
    }
    
    private func startProxyAndRedirect(openTelegram: Bool = true) {
        guard settings.isLaunchConfigValid else { return }
        // Same snapshot as the manual start path in ConnectionTab.
        let config = settings.launchConfig()

        DispatchQueue.global(qos: .userInitiated).async {
            let started = proxyManager.start(config)

            if started && openTelegram {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let url = URL(string: "tg://") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}
