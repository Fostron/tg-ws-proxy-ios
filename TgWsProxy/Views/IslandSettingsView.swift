import SwiftUI

/// Customisation of the Dynamic Island / Lock Screen activity, with a live
/// preview drawn by the same view the extension uses.
struct IslandSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var proxyManager: ProxyManager
    @Environment(\.dismiss) private var dismiss

    /// The style when the sheet opened; a running activity is restarted on
    /// close only if it changed (the look is fixed per activity).
    @State private var styleOnOpen: IslandStyle?

    private var ru: Bool { settings.language == .ru }
    private var style: IslandStyle { settings.resolvedIslandStyle }

    /// Sample numbers so the preview looks alive with the proxy off.
    private var sample: ProxyActivityAttributes.ContentState {
        ProxyActivityAttributes.ContentState(
            downRate: 1_480_000, upRate: 36_000, totalDown: 48_300_000, totalUp: 3_100_000,
            connections: 7, route: settings.effectiveRouteLabel, via: "CDN"
        )
    }

    private let allSlots: [IslandSlot] = [.download, .upload, .mode, .connections, .traffic, .icon, .none]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                }
                .listRowBackground(Color.clear)

                Section(header: Text(ru ? "Свёрнутый вид" : "Compact")) {
                    slotPicker(ru ? "Слева" : "Left", $settings.islandStyle.leading, allSlots)
                    slotPicker(ru ? "Справа" : "Right", $settings.islandStyle.trailing, allSlots)
                    slotPicker(ru ? "Минимальный" : "Minimal", $settings.islandStyle.minimal,
                               [.icon, .download, .upload, .mode])
                    Toggle(ru ? "«/s» после скорости" : "“/s” after speeds", isOn: $settings.islandStyle.compactUnits)
                }

                Section(header: Text(ru ? "Цвета" : "Colors")) {
                    colorRow(ru ? "Скачивание" : "Download", $settings.islandStyle.downColor)
                    colorRow(ru ? "Выгрузка" : "Upload", $settings.islandStyle.upColor)
                    colorRow(ru ? "Режим и значок" : "Mode and icon", $settings.islandStyle.modeColor)
                }

                Section(header: Text(ru ? "Развёрнутый вид и экран блокировки" : "Expanded and Lock Screen")) {
                    Toggle(ru ? "Режим и маршрут" : "Mode and route", isOn: $settings.islandStyle.showMode)
                    Toggle(ru ? "Трафик за сессию" : "Session traffic", isOn: $settings.islandStyle.showTraffic)
                    Toggle(ru ? "Число соединений" : "Connection count", isOn: $settings.islandStyle.showConnections)
                    Toggle(ru ? "Цвет палитры на экране блокировки" : "Palette-tinted Lock Screen card",
                           isOn: $settings.islandStyle.tintedLockScreen)
                }

                Section {
                    Button(ru ? "Сбросить оформление" : "Reset to defaults") {
                        settings.islandStyle = .default
                    }
                }
            }
            .appBackground()
            .navigationTitle("Dynamic Island")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(ru ? "Готово" : "Done") { dismiss() }
                }
            }
        }
        .onAppear { styleOnOpen = settings.islandStyle }
        .onDisappear {
            guard settings.islandStyle != styleOnOpen, proxyManager.isRunning,
                  settings.showLiveActivity, LiveActivityManager.shared.isActive else { return }
            LiveActivityManager.shared.start(route: settings.effectiveRouteLabel,
                                             language: settings.language.rawValue,
                                             style: settings.resolvedIslandStyle)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(spacing: 14) {
            // Compact: the two slots either side of the camera cutout.
            HStack(spacing: 0) {
                IslandSlotView(slot: style.leading, state: sample, style: style, stale: false)
                    .frame(minWidth: 64, alignment: .leading)
                Spacer(minLength: 96)
                IslandSlotView(slot: style.trailing, state: sample, style: style, stale: false)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 320)
            .frame(height: 38)
            .background(Capsule().fill(Color.black))

            HStack(spacing: 10) {
                IslandSlotView(slot: style.minimal == .none ? .icon : style.minimal,
                               state: sample, style: style, stale: false)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black))
                Text(ru ? "минимальный вид — когда активностей две" : "minimal — when two activities share the island")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Rows

    private func slotPicker(_ title: String, _ selection: Binding<IslandSlot>, _ options: [IslandSlot]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { slot in
                Text(slot.title(russian: ru)).tag(slot)
            }
        }
    }

    private func colorRow(_ title: String, _ selection: Binding<IslandColor>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(IslandColor.allCases) { option in
                        let isSelected = selection.wrappedValue == option
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color(themeHex: style.themeHex))
                                    .frame(width: 28, height: 28)
                                if option == .theme {
                                    Image(systemName: "paintpalette.fill")
                                        .font(.caption2)
                                        .foregroundColor(.black.opacity(0.6))
                                }
                            }
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: isSelected ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.rawValue)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
