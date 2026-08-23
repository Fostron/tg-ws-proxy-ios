import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionTab()
                .tabItem {
                    Label(settings.t("tab.proxy"), systemImage: "power")
                }
                .tag(0)

            SettingsTab()
                .tabItem {
                    Label(settings.t("tab.settings"), systemImage: "gearshape")
                }
                .tag(1)

            LogsTab()
                .tabItem {
                    Label(settings.t("tab.logs"), systemImage: "terminal")
                }
                .tag(2)

            InfoTab()
                .tabItem {
                    Label(settings.t("tab.info"), systemImage: "info.circle")
                }
                .tag(3)
        }
        .tint(AppPalette(from: settings.themePalette).accent)
    }
}
