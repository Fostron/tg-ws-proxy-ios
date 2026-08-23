import SwiftUI

struct LogsTab: View {
    @EnvironmentObject var logManager: LogManager
    @EnvironmentObject var settings: SettingsStore

    private var accent: Color { AppPalette(from: settings.themePalette).accent }

    private var filteredLogs: [LogEntry] {
        if settings.logShowNull {
            return [LogEntry(message: settings.t("logs.disabled_message"), level: .info, timestamp: Date(), isEssential: true)]
        }
        return logManager.logs.filter { entry in
            entry.isEssential ||
            (settings.logShowInfo && entry.level == .info) ||
            (settings.logShowError && (entry.level == .error || entry.level == .warn))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(settings.t("logs.title"))
                    .font(.headline)
                Spacer()
                Button(action: { logManager.clearLogs() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                Button(action: copyLogs) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(accent)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack(spacing: 8) {
                FilterChip(label: "INFO", selected: settings.logShowInfo && !settings.logShowNull, accent: accent) {
                    settings.logShowInfo.toggle()
                    settings.logShowNull = false
                }
                FilterChip(label: "ERROR", selected: settings.logShowError && !settings.logShowNull, accent: accent) {
                    settings.logShowError.toggle()
                    settings.logShowNull = false
                }
                FilterChip(label: "NULL", selected: settings.logShowNull, accent: .gray) {
                    settings.logShowNull.toggle()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { entry in
                            LogLineView(entry: entry, accent: accent)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .glassCard(cornerRadius: 16)
                .padding(.horizontal, 12)
                .onChange(of: filteredLogs.count) { _ in
                    if let last = filteredLogs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func copyLogs() {
        let text = filteredLogs.map { "\($0.message) (x\($0.count))" }.joined(separator: "\n")
        UIPasteboard.general.string = text
    }
}

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        let text = Text(label)
            .font(.caption)
            .fontWeight(selected ? .bold : .medium)
            .foregroundColor(selected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)

        if #available(iOS 26.0, *) {
            Button(action: action) { text }
                .buttonStyle(.plain)
                .glassEffect(
                    selected ? Glass.regular.tint(accent).interactive() : Glass.regular.interactive(),
                    in: Capsule()
                )
        } else {
            Button(action: action) { text }
                .buttonStyle(.borderedProminent)
                .tint(selected ? accent : .gray.opacity(0.2))
        }
    }
}

private struct LogLineView: View {
    let entry: LogEntry
    let accent: Color

    private var color: Color {
        switch entry.level {
        case .error: return AppColors.terminalRed
        case .warn: return AppColors.terminalOrange
        case .info: return AppColors.terminalGreen
        case .debug: return AppColors.terminalBlue
        }
    }

    private var iconName: String {
        switch entry.level {
        case .error: return "xmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .debug: return "ladybug.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(entry.count)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(AppColors.terminalCounter)
                .frame(minWidth: 20)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.terminalCounter.opacity(0.12))
                )

            Image(systemName: iconName)
                .font(.caption2)
                .foregroundColor(color.opacity(0.8))
                .frame(width: 14)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
                .fontWeight(entry.level == .error ? .bold : .regular)
        }
    }
}
