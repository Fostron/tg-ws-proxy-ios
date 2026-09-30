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
        "backdrop.title": [.ru: "Фон", .en: "Background"],
        "backdrop.plain": [.ru: "Обычный", .en: "Plain"],
        "backdrop.soft": [.ru: "Мягкий", .en: "Soft"],
        "backdrop.vivid": [.ru: "Яркий", .en: "Vivid"],
        "language.title": [.ru: "Язык", .en: "Language"],

        // MARK: Settings tab — cards
        "settings.title": [.ru: "Настройки", .en: "Settings"],
        "settings.connection": [.ru: "Подключение", .en: "Connection"],
        "settings.port": [.ru: "Порт", .en: "Port"],
        "settings.configure_dc": [.ru: "Настроить DC адреса", .en: "Configure DC addresses"],
        "settings.ip.pick": [.ru: "Выбрать адрес", .en: "Pick an address"],
        "settings.ip.local": [.ru: "только этот iPhone", .en: "this iPhone only"],
        "settings.ip.wifi": [.ru: "Wi-Fi, для других устройств", .en: "Wi-Fi, for other devices"],
        "settings.ip.hotspot": [.ru: "режим модема", .en: "Personal Hotspot"],
        "settings.ip.all": [.ru: "все сети", .en: "all networks"],
        "settings.ip.no_wifi": [.ru: "Wi-Fi не подключён", .en: "Wi-Fi not connected"],
        "settings.route": [.ru: "Маршрут", .en: "Route"],
        "settings.route.auto": [.ru: "Авто", .en: "Auto"],
        "settings.route.auto_desc": [
            .ru: "Как в оригинале: Direct для DC с адресом, при сбое — Worker → CDN → TCP. Маршрут, который перестал отвечать, пропускается 10 минут.",
            .en: "As upstream: Direct for DCs with an address, on failure Worker → CDN → TCP. A route that stops answering is skipped for 10 minutes."
        ],
        "settings.route.cdn_desc": [
            .ru: "Каждое подключение сначала идёт через Cloudflare CDN, потом как в «Авто». Имеет смысл, если Direct режется DPI.",
            .en: "Every connection tries Cloudflare CDN first, then continues as Auto. Useful when DPI cuts Direct."
        ],
        "settings.route.worker_desc": [
            .ru: "Каждое подключение сначала идёт через ваш Worker, потом как в «Авто». Тратит дневной лимит Worker (100 000 запросов).",
            .en: "Every connection tries your Worker first, then continues as Auto. Uses up the Worker's daily quota (100,000 requests)."
        ],
        "settings.route.not_configured": [
            .ru: "Этот маршрут не настроен — прокси будет работать как «Авто».",
            .en: "This route isn't configured — the proxy will behave as Auto."
        ],
        "settings.ws_pool": [.ru: "WS Pool", .en: "WS Pool"],
        "settings.pool_size": [.ru: "Размер пула", .en: "Pool size"],
        "settings.secret_key": [.ru: "Секретный ключ", .en: "Secret key"],
        "settings.cf_cdn": [.ru: "CloudFlare CDN", .en: "CloudFlare CDN"],
        "settings.custom_domain": [.ru: "Свой домен", .en: "Custom domain"],
        "settings.custom_domain_invalid": [.ru: "Только домен, без https:// и пути", .en: "Domain only, no https:// or path"],
        "settings.custom_domain_valid": [.ru: "Заменяет публичный список доменов на свой", .en: "Replaces the public domain list with your own"],
        "settings.cf_worker": [.ru: "Cloudflare Worker", .en: "Cloudflare Worker"],
        "settings.cf_worker_invalid": [.ru: "Укажите домен Worker или https://...", .en: "Enter the Worker domain or https://..."],
        "settings.cf_worker_valid": [.ru: "Первый резерв после Direct. Скрипт — tgwsproxy-worker.js из репозитория", .en: "First fallback after Direct. Script: tgwsproxy-worker.js from the repo"],
        "settings.faketls": [.ru: "FakeTLS", .en: "FakeTLS"],
        "settings.faketls_invalid": [.ru: "Только домен, без https:// и пути", .en: "Domain only, no https:// or path"],
        "settings.faketls_valid": [
            .ru: "Нужен только когда к прокси подключаются через сеть с DPI (режим nginx). Домен — тот, что nginx направляет сюда. Ссылка станет ee-секретом",
            .en: "Only useful when clients reach the proxy across a DPI network (nginx mode). Use the domain nginx routes here. The link becomes an ee-secret"
        ],
        "settings.faketls_mask_placeholder": [.ru: "Сайт-маска: host[:port] (необязательно)", .en: "Mask site: host[:port] (optional)"],
        "settings.faketls_mask_invalid": [.ru: "Только host или host:port, без https://", .en: "host or host:port only, no https://"],
        "settings.faketls_mask_hint": [
            .ru: "Куда отдавать чужие подключения (сканеры, зонды). Пусто — просто закрывать. Не указывайте домен FakeTLS — nginx вернёт его сюда же",
            .en: "Where foreign connections (scanners, probes) are forwarded. Empty = just close. Don't use the FakeTLS domain — nginx would route it right back here"
        ],
        "settings.nginx": [.ru: "Работа за nginx", .en: "Behind nginx"],
        "settings.nginx_desc": [
            .ru: "Принимать заголовок PROXY protocol от nginx (proxy_protocol on;). Подключения без него будут отклонены. Инструкция — Инфо → Справка → «FakeTLS и nginx»",
            .en: "Accept the PROXY protocol header from nginx (proxy_protocol on;). Connections without it are rejected. Guide: Info → Help → “FakeTLS and nginx”"
        ],
        "settings.link_host": [.ru: "Внешний адрес", .en: "External host"],
        "settings.link_port": [.ru: "Внешний порт", .en: "External port"],
        "settings.link_invalid": [.ru: "Адрес — домен или IP без https://, порт 1–65535", .en: "Host: domain or IP without https://; port 1–65535"],
        "settings.link_hint": [
            .ru: "Попадают в ссылку на главном экране — её и раздавайте. Пусто — адрес и порт этого устройства",
            .en: "Used in the link on the main tab — share that one. Empty = this device's address and port"
        ],
        "settings.nginx_loopback_warning": [
            .ru: "Прокси слушает 127.0.0.1 — nginx на другом устройстве его не увидит. Укажите в «Подключении» 0.0.0.0 или IP телефона",
            .en: "The proxy listens on 127.0.0.1 — nginx on another machine can't reach it. Set 0.0.0.0 or the phone's IP under Connection"
        ],
        "settings.doh": [.ru: "DoH-резолверы", .en: "DoH resolvers"],
        "settings.doh_custom_placeholder": [.ru: "Свой DoH: https://your-doh.example.com/dns-query", .en: "Custom DoH: https://your-doh.example.com/dns-query"],
        "settings.doh_invalid": [.ru: "Укажите полный адрес: https://...", .en: "Enter a full address: https://..."],
        "settings.doh_valid": [.ru: "Обычный UDP:53 используется только если весь DoH недоступен — не гонка, а резерв", .en: "Plain UDP:53 is used only if all DoH options are unavailable — a fallback, not a race"],
        "settings.autostart": [.ru: "Запускать при открытии", .en: "Start on launch"],
        "settings.live_activity": [.ru: "Скорость в Dynamic Island", .en: "Speed in Dynamic Island"],
        "settings.live_activity_customize": [.ru: "Настроить Dynamic Island", .en: "Customize Dynamic Island"],
        "settings.live_activity_desc": [
            .ru: "Скачивание и выгрузка в реальном времени в Dynamic Island и на экране блокировки. Нужен iOS 16.2+; на iPhone без Dynamic Island — только экран блокировки.",
            .en: "Live download and upload speed in the Dynamic Island and on the Lock Screen. Requires iOS 16.2+; iPhones without the Dynamic Island get the Lock Screen only."
        ],
        "settings.experimental.title": [.ru: "Экспериментальные функции", .en: "Experimental Features"],
        "settings.experimental.desc_on": [.ru: "Тестовая сборка: FakeTLS и режим nginx, TLS-отпечаток, подмена SNI, фрагментация и DoH. Могут ломать соединение.", .en: "Test build: FakeTLS and nginx mode, TLS fingerprint, SNI spoofing, fragmentation and DoH. These can break connections."],
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
        "help.section.route.title": [.ru: "Маршрут", .en: "Route"],
        "help.section.route.text": [
            .ru: "«Авто» работает как оригинальный tg-ws-proxy: DC с заданным адресом (по умолчанию DC2 и DC4) идут напрямую через WebSocket web.telegram.org, остальные и все неудачные попытки — по цепочке Worker → CDN → TCP. Если маршрут принял данные и не вернул ни байта (так выглядит DPI или неверный Worker), он пропускается 10 минут, а Telegram сразу переподключается следующим. «CDN» и «Worker» ставят соответствующий маршрут первым для каждого подключения.",
            .en: "“Auto” behaves like the original tg-ws-proxy: DCs with an address (DC2 and DC4 by default) go directly over the web.telegram.org WebSocket, everything else and every failed attempt goes down Worker → CDN → TCP. If a route takes data but never sends a byte back (what DPI or a wrong Worker looks like), it is skipped for 10 minutes and Telegram's reconnect uses the next one. “CDN” and “Worker” put that route first for every connection."
        ],
        "help.section.cf_cdn.title": [.ru: "CloudFlare CDN", .en: "CloudFlare CDN"],
        "help.section.cf_cdn.text": [
            .ru: "Резервный маршрут через WebSocket на доменах за Cloudflare (kws1…kws5, kws203). По умолчанию — общий список доменов, который упирается в лимиты Cloudflare; свой домен стабильнее: SSL/TLS → Flexible, шесть A-записей kws1…kws5 и kws203 на IP DC (как в гайде Flowseal), все с оранжевым облаком. Если провайдер режет Cloudflare, этот маршрут работать не будет — на iPhone обойти это без VPN нельзя.",
            .en: "A fallback route over WebSocket on Cloudflare-proxied domains (kws1…kws5, kws203). By default it uses a shared domain list that hits Cloudflare's limits; your own domain is more stable: SSL/TLS → Flexible, six A records kws1…kws5 and kws203 pointing at the DC IPs (as in Flowseal's guide), all proxied. If your ISP throttles Cloudflare this route can't work — an iPhone app can't get around that without a VPN."
        ],
        "help.section.ws_pool.title": [.ru: "WS Pool", .en: "WS Pool"],
        "help.section.ws_pool.text": [
            .ru: "Сколько заранее открытых WebSocket-соединений держать для каждого Direct-DC. Ускоряет первое подключение и загрузку медиа. Рекомендуется: 4.",
            .en: "How many pre-opened WebSocket connections to keep per Direct DC. Speeds up the first connection and media loading. Recommended: 4."
        ],
        "help.section.secret.title": [.ru: "Секретный ключ", .en: "Secret key"],
        "help.section.secret.text": [
            .ru: "Уникальный ключ для идентификации вашего прокси. Генерируется автоматически. Не меняйте его, если Telegram уже подключен.",
            .en: "A unique key identifying your proxy. Generated automatically. Don't change it while Telegram is already connected."
        ],
        "help.section.dc.title": [.ru: "Прямые DC адреса", .en: "Direct DC addresses"],
        "help.section.dc.text": [
            .ru: "Адреса для прямого WebSocket-подключения (Direct). По умолчанию DC2 и DC4 → 149.154.167.220 — это шлюз web.telegram.org, как в оригинале. Остальные DC идут резервными маршрутами. Очистите поля, чтобы не использовать Direct вообще.",
            .en: "Addresses for direct WebSocket connections (Direct). By default DC2 and DC4 → 149.154.167.220, the web.telegram.org gateway, as upstream. Other DCs use the fallback routes. Clear the fields to skip Direct entirely."
        ],
        "help.section.experimental.title": [.ru: "Экспериментальные функции", .en: "Experimental Features"],
        "help.section.experimental.text": [
            .ru: "Есть только в тестовой сборке. Переключатель во вкладке «Настройки» открывает FakeTLS и режим nginx, TLS-отпечаток, подмену SNI, фрагментацию и настройку DoH. Пока он выключен, эти настройки не применяются, а DoH работает со всеми резолверами. Отдельно от него — «Экспериментальный режим» внутри настройки DC адресов, который лишь добавляет поля для DC5/DC203 и media-DC.",
            .en: "Test build only. The switch on the Settings tab unlocks FakeTLS and nginx mode, TLS fingerprint, SNI spoofing, fragmentation and DoH tuning. While it's off none of these apply and DoH uses every resolver. Separately, “Experimental mode” inside DC address setup only adds fields for DC5/DC203 and the media DCs."
        ],
        "help.section.island.title": [.ru: "Dynamic Island", .en: "Dynamic Island"],
        "help.section.island.text": [
            .ru: "Пока прокси включён, в Dynamic Island и на экране блокировки видно скорость скачивания и выгрузки, режим и маршрут, через который сейчас идёт трафик (например, «Auto→CDN»). «Настройки → Настроить Dynamic Island»: что показывать слева и справа, минимальный вид, цвета и что выводить в развёрнутом виде — с живым превью. Нужен iOS 16.2+. Если цифры сменились на «—», iOS усыпил приложение — откройте его.",
            .en: "While the proxy runs, the Dynamic Island and the Lock Screen show download and upload speed, the mode and the route traffic currently goes through (e.g. “Auto→CDN”). “Settings → Customize Dynamic Island”: what goes left and right, the minimal view, colors and what the expanded view shows — with a live preview. Requires iOS 16.2+. If the numbers turn into “—”, iOS suspended the app — open it."
        ],
        "help.section.worker.title": [.ru: "Cloudflare Worker", .en: "Cloudflare Worker"],
        "help.section.worker.text": [
            .ru: "Бесплатный резервный маршрут без своего домена. Cloudflare → Workers & Pages → Create → Hello World → Edit code: вставьте tgwsproxy-worker.js из репозитория (подойдёт и скрипт из гайда Flowseal) → Deploy. Укажите домен вида name.user.workers.dev, можно несколько через запятую. Приложение передаёт Worker'у настоящий адрес DC, Worker открывает к нему TCP. Если в журнале «Worker принял … и не вернул ни байта» — скрипт старый или Cloudflare режется провайдером (проверьте, открывается ли адрес Worker в Safari).",
            .en: "A free fallback route with no domain of your own. Cloudflare → Workers & Pages → Create → Hello World → Edit code: paste tgwsproxy-worker.js from the repo (the script from Flowseal's guide works too) → Deploy. Enter the name.user.workers.dev domain; several can be comma-separated. The app hands the Worker the DC's real address and the Worker opens TCP to it. If the log says “Worker took … and never sent a byte back”, the script is outdated or your ISP throttles Cloudflare (check whether the Worker address opens in Safari)."
        ],
        "help.section.faketls.title": [.ru: "FakeTLS и nginx", .en: "FakeTLS and nginx"],
        "help.section.faketls.text": [
            .ru: "Между Telegram и прокси на этом же iPhone DPI нет, поэтому FakeTLS нужен только в режиме сервера: другие люди подключаются к вашему домену через nginx, а nginx передаёт подключения на телефон.\n\n1. Домен: A-запись proxy.example.com → внешний IP машины с nginx, БЕЗ проксирования Cloudflare (серое облако).\n2. nginx должен видеть iPhone: та же сеть (домашний сервер/роутер с пробросом 443) или туннель (WireGuard, Tailscale). Закрепите IP телефона в роутере.\n3. Приложение → Подключение: IP 0.0.0.0, порт 1443.\n4. Экспериментальные функции → FakeTLS: домен proxy.example.com. Сайт-маска — по желанию, любой настоящий HTTPS-сервер, кроме самого proxy.example.com.\n5. «Работа за nginx»: включить, внешний адрес proxy.example.com, порт 443.\n6. nginx: конфиг ниже, затем nginx -t && nginx -s reload.\n7. Раздавайте ссылку с главного экрана — она уже ведёт на proxy.example.com:443 с ee-секретом.\n\nОграничения: iOS усыпляет приложение в фоне, так что прокси работает, пока приложение активно. Часы у клиентов должны идти точно (±2 минуты), иначе рукопожатие FakeTLS отвергается.",
            .en: "There is no DPI between Telegram and a proxy on the same iPhone, so FakeTLS only matters in server mode: other people connect to your domain through nginx, and nginx hands the connections to the phone.\n\n1. Domain: an A record proxy.example.com → the public IP of the nginx machine, NOT proxied by Cloudflare (grey cloud).\n2. nginx must reach the iPhone: same network (home server/router forwarding 443) or a tunnel (WireGuard, Tailscale). Reserve the phone's IP in the router.\n3. App → Connection: IP 0.0.0.0, port 1443.\n4. Experimental Features → FakeTLS: domain proxy.example.com. Mask site is optional: any real HTTPS server except proxy.example.com itself.\n5. “Behind nginx”: on, external host proxy.example.com, port 443.\n6. nginx: config below, then nginx -t && nginx -s reload.\n7. Share the link from the main tab — it already points at proxy.example.com:443 with an ee-secret.\n\nLimits: iOS suspends the app in the background, so the proxy works while the app is active. Clients' clocks must be accurate (±2 minutes) or the FakeTLS handshake is rejected."
        ],
        "help.section.nginx.copy": [.ru: "Скопировать конфиг", .en: "Copy config"],
        "help.section.nginx.copied": [.ru: "Скопировано", .en: "Copied"],
        "help.section.doh.title": [.ru: "DoH-резолверы", .en: "DoH resolvers"],
        "help.section.doh.text": [
            .ru: "DNS поверх HTTPS для разрешения доменов CDN/Worker без утечки запросов через обычный DNS. Можно включить сразу несколько провайдеров или указать свой.",
            .en: "DNS-over-HTTPS for resolving CDN/Worker domains without leaking queries over plain DNS. You can enable several built-in providers at once or add your own."
        ],
        "help.section.slow.title": [.ru: "Медленное подключение", .en: "Slow connection"],
        "help.section.slow.text": [
            .ru: "Включите фильтр DEBUG в журнале: там видно, какой маршрут пробуется и чем закончилась каждая сессия (↑/↓ байты). Если Direct постоянно «не отвечает», выберите маршрут «CDN» или «Worker». Если не отвечает всё, что идёт через Cloudflare, — провайдер режет Cloudflare.",
            .en: "Turn on the DEBUG filter in the log: it shows which route is tried and how each session ended (↑/↓ bytes). If Direct keeps “not answering”, pick the “CDN” or “Worker” route. If everything through Cloudflare fails, your ISP is throttling Cloudflare."
        ],
    ]
}
