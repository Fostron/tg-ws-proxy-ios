<div align="center">

# TG WS Proxy iOS

<img src="https://img.shields.io/badge/iOS-16.1+-000000?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 16.1+">
<img src="https://img.shields.io/badge/Go-core-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go">
<img src="https://img.shields.io/badge/SwiftUI-Liquid_Glass-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI">
<a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Fostron/tg-ws-proxy-ios?style=for-the-badge&label=%D1%80%D0%B5%D0%BB%D0%B8%D0%B7" alt="Релиз"></a>

**Локальный MTProto-прокси для Telegram прямо на iPhone**

</div>

Приложение поднимает прокси на самом телефоне и отправляет трафик Telegram через WebSocket — так же, как это делает веб-версия Telegram, — а при блокировках уходит через Cloudflare. Без VPN-профиля и без перехвата системного трафика: Telegram подключается к прокси по ссылке `tg://proxy`, остальные приложения не затрагиваются.

iOS-версия [tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) от Flowseal.

---

## Возможности

- **Четыре маршрута с автопереключением.** Direct (WebSocket к Telegram), Cloudflare Worker, Cloudflare CDN и обычный TCP — в режиме «Авто» в том же порядке, что и в оригинале. Если маршрут перестал отвечать, приложение на время его пропускает, и Telegram сразу подключается следующим. CDN или Worker можно поставить первыми.
- **Свой Cloudflare.** Бесплатный Worker или свой домен вместо общих публичных — стабильнее и быстрее.
- **Dynamic Island и экран блокировки.** Скорость скачивания и выгрузки в реальном времени, режим и маршрут, трафик и число соединений. Слоты, цвета и развёрнутый вид настраиваются, с живым превью.
- **Девять палитр и три вида фона.** Telegram, Индиго, Океан, Аврора, Закат, Сакура, Янтарь, Эспрессо, Графит; фон обычный, мягкий или яркий. Светлая и тёмная тема, Liquid Glass на iOS 26.
- **Быстрый выбор адреса.** Одно нажатие — `127.0.0.1` (только этот iPhone) или адрес iPhone в Wi-Fi / режиме модема, чтобы прокси могли пользоваться другие устройства.
- **DNS через HTTPS.** Адреса Cloudflare разрешаются через Cloudflare, Google, Quad9 и AdGuard; обычный DNS — только если весь DoH недоступен.
- **Подробный журнал.** Уровни INFO / ERROR / DEBUG; в DEBUG видно, какой маршрут пробуется и сколько байт прошло в каждой сессии.
- **Русский и английский.**

## Установка

1. Скачайте `TgWsProxy.ipa` со **[страницы релизов](../../releases/latest)**.
2. Установите через **AltStore**, **SideStore**, **Sideloadly** или **TrollStore** — IPA не подписан.
3. Откройте приложение и нажмите кнопку питания.
4. Нажмите **«Применить в Telegram»** и подтвердите добавление прокси.

В IPA есть расширение для Dynamic Island. На бесплатном аккаунте Apple оно занимает ещё один App ID из лимита.

## Как это работает

```text
Telegram → 127.0.0.1:1443 (приложение) ─┬─ Direct: WebSocket к web.telegram.org
                                        ├─ Cloudflare Worker (ваш *.workers.dev)
                                        ├─ Cloudflare CDN (kws1…kws203 на домене)
                                        └─ TCP напрямую к дата-центру
```

1. Прокси работает на ядре на **Go**, встроенном в приложение.
2. Telegram подключается к прокси с секретным ключом, прокси определяет нужный дата-центр.
3. Соединение уходит первым рабочим маршрутом. Маршрут, который принял данные и не ответил, на время пропускается.

## Свой Cloudflare

Публичные домены общие на всех и упираются в лимиты Cloudflare, поэтому свой канал работает стабильнее.

### Cloudflare Worker — бесплатно, домен не нужен

1. Зарегистрируйтесь на [dash.cloudflare.com](https://dash.cloudflare.com) и подтвердите почту.
2. **Compute → Workers & Pages → Create application → Start with Hello World → Deploy.**
3. **Edit code**: замените код на [`tgwsproxy-worker.js`](tgwsproxy-worker.js) из этого репозитория и нажмите **Deploy**.
4. В приложении: **Настройки → Cloudflare Worker**, укажите домен вида `name.user.workers.dev`. Несколько воркеров можно перечислить через запятую.

> [!TIP]
> Проверить Worker можно в разделе **Workers → Logs**: у рабочей сессии в строке `client closed (up=… down=…)` оба числа больше нуля.

### Свой домен

1. Добавьте домен в Cloudflare (подойдёт любой).
2. **SSL/TLS → Overview → Flexible.**
3. **DNS → Records** — шесть A-записей, все с оранжевым облаком (проксирование включено):

   | Имя | IPv4 |
   |---|---|
   | `kws1` | `149.154.175.50` |
   | `kws2` | `149.154.167.51` |
   | `kws3` | `149.154.175.100` |
   | `kws4` | `149.154.167.91` |
   | `kws5` | `149.154.171.5` |
   | `kws203` | `91.105.192.100` |

4. В приложении: **Настройки → CloudFlare CDN → Свой домен**. Несколько доменов — через запятую.

> [!IMPORTANT]
> `cloudflare.com`, `workers.dev` и ваш домен должны открываться из вашей сети. Если провайдер режет Cloudflare, никакие настройки внутри приложения не помогут.

## Ограничения

- iOS усыпляет приложения в фоне. Прокси работает, пока приложение активно; для полноценного фонового режима нужен Network Extension и платный аккаунт разработчика. Если в Dynamic Island вместо цифр «—», откройте приложение.
- Звонки Telegram через прокси не идут: клиент не отправляет через MTProto-прокси UDP. Это ограничение Telegram.

## Сообщить о проблеме

Включите фильтр **DEBUG** в журнале, воспроизведите проблему и нажмите **«Собрать отчёт»** во вкладке «Информация». Отчёт приложите к [issue](../../issues/new).

## Благодарности

- [**Flowseal**](https://github.com/Flowseal/tg-ws-proxy) — оригинальный `tg-ws-proxy`: сетевое ядро и сама идея WebSocket-транспорта.
- [**amurcanov**](https://github.com/amurcanov/tg-ws-proxy-android) — Android-форк, чья дизайн-система легла в основу интерфейса.

## Лицензия

**GPLv3**. Оригинальный `tg-ws-proxy` от Flowseal распространяется под лицензией MIT.
