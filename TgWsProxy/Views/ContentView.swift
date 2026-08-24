import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedTab = 0

    var body: some View {
        // GeometryReader supplies the width needed to detect a drag that
        // started at the RIGHT edge; the left edge is just x < edgeWidth.
        GeometryReader { geo in
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
            // Edge-only swiping: the gesture must BEGIN within edgeWidth of
            // the left or right border. Accepting it anywhere made ordinary
            // horizontal drags inside content (sliders, text fields, the log
            // list) flip tabs unexpectedly.
            //
            // simultaneousGesture, not gesture: the tabs contain ScrollViews
            // and an exclusive gesture would swallow their vertical scrolling.
            .simultaneousGesture(
                DragGesture(minimumDistance: 25, coordinateSpace: .local)
                    .onEnded { value in
                        let startX = value.startLocation.x
                        let fromLeftEdge = startX <= ContentView.edgeWidth
                        let fromRightEdge = startX >= geo.size.width - ContentView.edgeWidth
                        guard fromLeftEdge || fromRightEdge else { return }

                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 1.8 else { return }

                        withAnimation(.easeInOut(duration: 0.22)) {
                            if dx < 0 {
                                selectedTab = min(selectedTab + 1, ContentView.tabCount - 1)
                            } else {
                                selectedTab = max(selectedTab - 1, 0)
                            }
                        }
                    }
            )
        }
    }

    /// How close to a screen border a drag must start to count as a tab swipe.
    private static let edgeWidth: CGFloat = 40

    private static let tabCount = 4
}
