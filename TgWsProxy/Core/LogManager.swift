import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let level: LogLevel
    var timestamp: Date
    var count: Int = 1
    var isEssential: Bool = false
}

class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logs: [LogEntry] = []

    private let essentialMarkers = [
        "pool", "key:", "started", "address:", "error", "failed", "blocked",
        "Пул", "Ключ:", "запущен", "Адрес:", "ошибка", "провалены", "заблокирован"
    ]

    private init() {}

    func addLog(_ message: String, level: LogLevel = .info) {
        // Previously this ran a `[↑↓].*` regex that deleted everything from
        // the first arrow onward — which silently truncated the periodic
        // traffic summary ("акт:11 | cf:62 | ↑1.2MB ↓3.4MB" became
        // "акт:11 | cf:62 |"). Keep the line intact.
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let isEssential = essentialMarkers.contains { cleaned.localizedCaseInsensitiveContains($0) }

        let entry = LogEntry(
            message: cleaned,
            level: level,
            timestamp: Date(),
            isEssential: isEssential
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Look back a short window instead of only at the very last
            // entry. Lines of different levels interleave in the raw array
            // (an INFO connect, a WARN, another identical INFO), so strict
            // last-only matching almost never merged anything — the filtered
            // view then showed rows that looked identical and adjacent while
            // each still read "1".
            let window = 12
            let start = max(0, self.logs.count - window)
            if let idx = (start..<self.logs.count).last(where: {
                self.logs[$0].message == entry.message && self.logs[$0].level == entry.level
            }) {
                self.logs[idx].count += 1
                self.logs[idx].timestamp = entry.timestamp
            } else {
                self.logs.append(entry)
                // Matches the Go core's ring buffer (500) so the journal
                // isn't trimmed far earlier than the source it reads from.
                if self.logs.count > 500 {
                    self.logs.removeFirst(self.logs.count - 500)
                }
            }
        }
    }

    func clearLogs() {
        DispatchQueue.main.async {
            self.logs = []
        }
    }
}
