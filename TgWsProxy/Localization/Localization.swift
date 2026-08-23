import Foundation

/// UI language. Independent of the system locale — this is a runtime user
/// setting (see SettingsStore.language) so it can be switched from the
/// palette popover without relaunching the app.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case ru, en

    init(from raw: String) {
        self = AppLanguage(rawValue: raw) ?? .ru
    }

    var id: String { rawValue }

    /// Shown in its own language — "Русский" reads correctly to an RU
    /// speaker even when the current UI language is English, and vice versa.
    var displayName: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var symbolName: String {
        switch self {
        case .ru: return "r.circle.fill"
        case .en: return "e.circle.fill"
        }
    }

    /// Best-guess language for a fresh install, based on the device's
    /// preferred language list. Falls back to Russian, matching the app's
    /// original single-language UI.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "ru"
        return preferred.hasPrefix("ru") ? .ru : .en
    }
}

/// Tiny in-app localization catalog. Deliberately not a .lproj/String
/// Catalog setup: language here is a live user toggle, not a system-locale
/// setting, so everything needs to re-render on demand from a single
/// @Published property rather than at process launch.
enum L {
    static func t(_ key: String, _ lang: AppLanguage) -> String {
        table[key]?[lang] ?? table[key]?[.ru] ?? key
    }

    private static let table: [String: [AppLanguage: String]] = [
        // MARK: Tabs
        "tab.proxy": [.ru: "Прокси", .en: "Proxy"],
        "tab.settings": [.ru: "Настройки", .en: "Settings"],
        "tab.logs": [.ru: "Журнал", .en: "Logs"],
        "tab.info": [.ru: "Инфо", .en: "Info"],

        // MARK: Connection tab
        "conn.status.connecting": [.ru: "Подключение...", .en: "Connecting..."],
        "conn.status.connected": [.ru: "Подключено", .en: "Connected"],
        "conn.status.disconnected": [.ru: "Отключено", .en: "Disconnected"],
        "conn.apply": [.ru: "Применить в Telegram", .en: "Apply in Telegram"],
        "conn.stat.mode": [.ru: "Режим", .en: "Mode"],
        "conn.stat.pool": [.ru: "Пул", .en: "Pool"],
        "conn.stat.port": [.ru: "Порт", .en: "Port"],
        "conn.stat.ver": [.ru: "Версия", .en: "Ver"],

        // MARK: Theme / palette / language popover
        "theme.title": [.ru: "Тема", .en: "Theme"],
        "theme.system": [.ru: "Системная", .en: "System"],
        "theme.light": [.ru: "Светлая", .en: "Light"],
        "theme.dark": [.ru: "Тёмная", .en: "Dark"],
        "palette.title": [.ru: "Палитра", .en: "Palette"],
        "language.title": [.ru: "Язык", .en: "Language"],

        // MARK: Settings tab — cards
        "settings.title": [.ru: "Настройки", .en: "Settings"],
        "settings.connection": [.ru: "Подключение", .en: "Connection"],
        "settings.port": [.ru: "Порт", .en: "Port"],
        "settings.cf_on": [.ru: "CF включен", .en: "CF enabled"],
        "settings.configure_dc": [.ru: "Настроить DC адреса", .en: "Configure DC addresses"],
        "settings.ws_pool": [.ru: "WS Pool", .en: "WS Pool"],
        "settings.pool_size": [.ru: "Размер пула", .en: "Pool size"],
        "settings.secret_key": [.ru: "Секретный ключ", .en: "Secret key"],
        "settings.cf_cdn": [.ru: "CloudFlare CDN", .en: "CloudFlare CDN"],
        "settings.custom_domain": [.ru: "Свой домен", .en: "Custom domain"],
        "settings.custom_domain_invalid": [.ru: "Только домен, без https:// и пути", .en: "Domain only, no https:// or path"],
        "settings.custom_domain_valid": [.ru: "Заменяет публичный список доменов на свой", .en: "Replaces the public domain list with your own"],
        "settings.cf_worker": [.ru: "Cloudflare Worker", .en: "Cloudflare Worker"],
        "settings.cf_worker_invalid": [.ru: "Укажите полный адрес: https://...", .en: "Enter a full address: https://..."],
        "settings.cf_worker_valid": [.ru: "Автоматический fallback, если CDN и Direct недоступны", .en: "Automatic fallback if CDN and Direct are unavailable"],
        "settings.faketls": [.ru: "FakeTLS", .en: "FakeTLS"],
        "settings.faketls_invalid": [.ru: "Только домен, без https:// и пути", .en: "Domain only, no https:// or path"],
        "settings.faketls_valid": [.ru: "Маскирует хендшейк под TLS к этому домену", .en: "Disguises the handshake as a TLS connection to this domain"],
        "settings.doh": [.ru: "DoH-резолверы", .en: "DoH resolvers"],
        "settings.doh_custom_placeholder": [.ru: "Свой DoH: https://your-doh.example.com/dns-query", .en: "Custom DoH: https://your-doh.example.com/dns-query"],
        "settings.doh_invalid": [.ru: "Укажите полный адрес: https://...", .en: "Enter a full address: https://..."],
        "settings.doh_valid": [.ru: "Обычный UDP:53 используется только если весь DoH недоступен — не гонка, а резерв", .en: "Plain UDP:53 is used only if all DoH options are unavailable — a fallback, not a race"],
        "settings.autostart": [.ru: "Автозапуск", .en: "Auto-start"],
        "settings.experimental.title": [.ru: "Экспериментальные функции", .en: "Experimental Features"],
        "settings.experimental.desc_on": [.ru: "Открыт доступ к Cloudflare Worker, FakeTLS, DoH-резолверам и своему CDN-домену.", .en: "Cloudflare Worker, FakeTLS, DoH resolvers, and a custom CDN domain are unlocked."],
        "settings.experimental.desc_off": [.ru: "Продвинутые сетевые настройки скрыты и не используются, пока переключатель выключен.", .en: "Advanced networking settings are hidden and inactive while this is off."],

        // MARK: IP setup sheet
        "ip_sheet.main_dc": [.ru: "Основные DC", .en: "Main DC"],
        "ip_sheet.media_dc": [.ru: "Media DC", .en: "Media DC"],
        "ip_sheet.dc_addresses": [.ru: "DC адреса", .en: "DC addresses"],
        "ip_sheet.experimental_mode": [.ru: "Экспериментальный режим", .en: "Experimental mode"],
        "ip_sheet.title": [.ru: "Настройка DC", .en: "DC setup"],
        "ip_sheet.done": [.ru: "Готово", .en: "Done"],
        "ip_sheet.ip_placeholder": [.ru: "IP адрес", .en: "IP address"],

        // MARK: Logs tab
        "logs.title": [.ru: "Журнал", .en: "Logs"],
        "logs.disabled_message": [.ru: "Отображение логов отключено", .en: "Log display is disabled"],

        // MARK: Info tab
        "info.title": [.ru: "Информация", .en: "Information"],
        "info.badge.ios_port": [.ru: "iOS Port", .en: "iOS Port"],
        "info.badge.flowseal_base": [.ru: "Flowseal Base", .en: "Flowseal Base"],
        "info.app_desc": [.ru: "MTProto-прокси для Telegram через CloudFlare WebSocket", .en: "MTProto proxy for Telegram over a CloudFlare WebSocket"],
        "info.support": [.ru: "Поддержать разработку", .en: "Support development"],
        "info.actions": [.ru: "Действия", .en: "Actions"],
        "info.help.title": [.ru: "Справка", .en: "Help"],
        "info.help.subtitle": [.ru: "Как настроить и использовать прокси", .en: "How to configure and use the proxy"],
        "info.issues.title": [.ru: "GitHub Issues", .en: "GitHub Issues"],
        "info.issues.subtitle": [.ru: "Сообщить об ошибке", .en: "Report an issue"],
        "info.report.title": [.ru: "Собрать отчёт", .en: "Build a report"],
        "info.report.subtitle": [.ru: "Копирует техническую информацию в буфер", .en: "Copies technical info to the clipboard"],
        "info.about": [.ru: "О проекте", .en: "About the project"],
        "info.link.original.title": [.ru: "Оригинальный tg-ws-proxy", .en: "Original tg-ws-proxy"],
        "info.link.original.subtitle": [.ru: "Flowseal · Windows/macOS/Linux", .en: "Flowseal · Windows/macOS/Linux"],
        "info.link.android.title": [.ru: "Android-форк", .en: "Android fork"],
        "info.link.android.subtitle": [.ru: "Amurcanov · tg-ws-proxy-android", .en: "Amurcanov · tg-ws-proxy-android"],
        "info.link.mtproto.title": [.ru: "MTProto Proxy Reference", .en: "MTProto Proxy Reference"],
        "info.link.mtproto.subtitle": [.ru: "Документация Telegram", .en: "Telegram documentation"],

        // MARK: Help sheet
        "help.close": [.ru: "Закрыть", .en: "Close"],
        "help.section.cf_cdn.title": [.ru: "CloudFlare CDN", .en: "CloudFlare CDN"],
        "help.section.cf_cdn.text": [
            .ru: "Прокси перенаправляет трафик через CloudFlare WebSocket-соединения для обхода блокировок. Включите эту опцию для автоматического выбора маршрута.",
            .en: "The proxy routes traffic through CloudFlare WebSocket connections to work around blocking. Enable this for automatic route selection."
        ],
        "help.section.ws_pool.title": [.ru: "WS Pool", .en: "WS Pool"],
        "help.section.ws_pool.text": [
            .ru: "Пул WebSocket-соединений. Больший размер = больше резервных соединений, но больше потребление памяти. Рекомендуется: 4.",
            .en: "The pool of WebSocket connections. A larger size means more standby connections but more memory use. Recommended: 4."
        ],
        "help.section.secret.title": [.ru: "Секретный ключ", .en: "Secret key"],
        "help.section.secret.text": [
            .ru: "Уникальный ключ для идентификации вашего прокси. Генерируется автоматически. Не меняйте его, если Telegram уже подключен.",
            .en: "A unique key identifying your proxy. Generated automatically. Don't change it while Telegram is already connected."
        ],
        "help.section.dc.title": [.ru: "Прямые DC адреса", .en: "Direct DC addresses"],
        "help.section.dc.text": [
            .ru: "Когда CloudFlare отключен, можно указать IP-адреса дата-центров Telegram напрямую. DC2 и DC4 используются по умолчанию.",
            .en: "When CloudFlare is disabled, you can point directly at Telegram datacenter IPs. DC2 and DC4 are used by default."
        ],
        "help.section.experimental.title": [.ru: "Экспериментальные функции", .en: "Experimental Features"],
        "help.section.experimental.text": [
            .ru: "Значок палитры на главном экране (кисть, сверху справа) открывает переключатель «Экспериментальные функции». Он открывает доступ к Cloudflare Worker, FakeTLS, DoH-резолверам и своему CDN-домену — эти настройки скрыты по умолчанию и предназначены для продвинутых пользователей. Отдельно от него — «Экспериментальный режим» внутри настройки DC адресов, который лишь добавляет поля для DC5/DC203 и media-DC.",
            .en: "The palette icon on the main screen (top-right) opens the “Experimental Features” switch. Turning it on unlocks Cloudflare Worker, FakeTLS, DoH resolvers, and a custom CDN domain — advanced settings hidden by default. Separately, “Experimental mode” inside DC address setup only adds fields for DC5/DC203 and the media DCs."
        ],
        "help.section.worker.title": [.ru: "Cloudflare Worker", .en: "Cloudflare Worker"],
        "help.section.worker.text": [
            .ru: "Резервный маршрут через собственный Cloudflare Worker (*.workers.dev), который используется, если основной CDN- и прямой доступ недоступны. Нужен уже развёрнутый Worker — укажите его полный https-адрес.",
            .en: "A fallback route through your own Cloudflare Worker (*.workers.dev), used when the main CDN and direct routes are unavailable. Requires a Worker you've already deployed — enter its full https address."
        ],
        "help.section.faketls.title": [.ru: "FakeTLS", .en: "FakeTLS"],
        "help.section.faketls.text": [
            .ru: "Маскирует хендшейк прокси под обычное TLS-соединение к выбранному домену (например, www.microsoft.com), чтобы затруднить его распознавание по трафику.",
            .en: "Disguises the proxy's handshake as an ordinary TLS connection to the chosen domain (e.g. www.microsoft.com), making it harder to fingerprint on the wire."
        ],
        "help.section.doh.title": [.ru: "DoH-резолверы", .en: "DoH resolvers"],
        "help.section.doh.text": [
            .ru: "DNS поверх HTTPS для разрешения доменов CDN/Worker без утечки запросов через обычный DNS. Можно включить сразу несколько провайдеров или указать свой.",
            .en: "DNS-over-HTTPS for resolving CDN/Worker domains without leaking queries over plain DNS. You can enable several built-in providers at once or add your own."
        ],
        "help.section.slow.title": [.ru: "Медленное подключение", .en: "Slow connection"],
        "help.section.slow.text": [
            .ru: "Если подключение занимает много времени, попробуйте увеличить размер WS Pool или переключиться между CF и Direct режимом.",
            .en: "If connecting is slow, try increasing the WS Pool size or switching between CF and Direct mode."
        ],
    ]
}
