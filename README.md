# ssh-monitor

Bash-скрипт мониторинга **SSH**, **SUDO** и событий **`systemd-logind`** (локальные/графические сессии и др.) с уведомлениями в Telegram, опциональным резервным webhook, авто-блокировкой IP (IPv4 через `iptables`, IPv6 через `ip6tables` при наличии) и ежедневным отчётом.

## Конфигурация

Скрипт читает параметры из `/etc/ssh-monitor.conf` в формате `KEY="value"`.

1. Скопируйте пример:
 - `sudo cp ./ssh-monitor.conf.example /etc/ssh-monitor.conf`
2. Ограничьте доступ:
 - `sudo chmod 600 /etc/ssh-monitor.conf`
3. Заполните минимум:
 - `TELEGRAM_BOT_TOKEN`
 - `TELEGRAM_CHAT_ID`

Поддерживаемые параметры:

- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- `BACKUP_WEBHOOK_URL` — резервная доставка JSON `{"text":"..."}` (например Slack Incoming Webhook), если Telegram недоступен или вернул ошибку
- `LOG_FILE`, `LAST_HEARTBEAT_FILE`, `LAST_REPORT_FILE`, `LAST_SSH_CHECK_FILE`, `LAST_SUDO_CHECK_FILE`, `LAST_SECURITY_EVENTS_FILE`, `LAST_LOGIND_CHECK_FILE`, `BAN_LIST_FILE`
- `ENABLE_LOGIND_MONITOR`, `LOGIND_NOTIFY_NEW`, `LOGIND_NOTIFY_REMOVED`, `LOGIND_NOTIFY_FAILED`, `LOGIND_SKIP_REMOTE` — см. раздел «Мониторинг systemd-logind» ниже
- `DAILY_REPORT_HOUR` (0..23), `DAILY_REPORT_TZ` (опционально), `DAILY_REPORT_TOP_IPS`
- `BRUTE_WINDOW_SEC`, `BRUTE_MIN_FAILS`, `BRUTE_NOTIFY_COOLDOWN_SEC`
- `PROMETHEUS_TEXTFILE_DIR` — каталог для `ssh_monitor.prom` (совместимость с node_exporter textfile collector)
- `HEALTHCHECK_STATUS_FILE` — путь к JSON-файлу с меткой последней итерации цикла
- `BAN_TIME`, `MAX_ATTEMPTS`, `BAN_CHECK_INTERVAL`, `MONITOR_INTERVAL`
- `WHITELIST_IPS`, `WHITELIST_SUBNETS` (CSV, например `ip1,ip2`)
- `WATCHDOG_MAX_HEARTBEAT_AGE`, `WATCHDOG_LOG_FILE`, `WATCHDOG_SERVICE_NAME`, `WATCHDOG_NOTIFY_ON_RECOVERY`

Если файл `/etc/ssh-monitor.conf` отсутствует или часть значений пустая, используются значения по умолчанию из скрипта.

### Описание переменных в `/etc/ssh-monitor.conf`

- `TELEGRAM_BOT_TOKEN` — токен Telegram-бота для отправки уведомлений.
- `TELEGRAM_CHAT_ID` — ID чата/пользователя, куда отправляются уведомления.
- `BACKUP_WEBHOOK_URL` — URL для резервной отправки (тело JSON `{"text":"..."}`).
- `LOG_FILE` — путь к основному лог-файлу скрипта.
- `LAST_HEARTBEAT_FILE` — файл с timestamp последнего heartbeat-сообщения.
- `LAST_REPORT_FILE` — дата последнего ежедневного отчёта в формате `YYYY-MM-DD` (старый формат Unix-времени при первом запуске будет автоматически интерпретирован).
- `LAST_SSH_CHECK_FILE` — файл с меткой времени последней проверки SSH-событий (unix-время, одна строка); см. раздел «Файлы-метки» ниже.
- `LAST_SUDO_CHECK_FILE` — метка последней проверки sudo-событий; см. «Файлы-метки».
- `LAST_SECURITY_EVENTS_FILE` — метка последней проверки «тяжёлых» событий безопасности в журнале (логика первого запуска **отличается** от SSH/sudo/logind — см. там же).
- `LAST_LOGIND_CHECK_FILE` — метка последней обработки журнала `systemd-logind`; см. «Файлы-метки».
- `BAN_LIST_FILE` — файл состояния банов (IP, время окончания бана и метаданные).
- `ENABLE_LOGIND_MONITOR` — `1` включает опрос `journalctl -u systemd-logind`, `0` полностью отключает этот блок.
- `LOGIND_NOTIFY_NEW` — `1` отправлять Telegram при появлении новой сессии в logind (строки вида *New session … of user …*).
- `LOGIND_NOTIFY_REMOVED` — `1` отправлять Telegram при завершении сессии (*Removed session …*); по умолчанию `0` (только запись в `LOG_FILE`, чтобы не заспамить канал).
- `LOGIND_NOTIFY_FAILED` — `1` отправлять Telegram по строкам logind, содержащим *failed* (широкий фильтр; при необходимости отключите).
- `LOGIND_SKIP_REMOTE` — `1` (по умолчанию): для новой сессии, если доступен `loginctl`, по свойствам сессии решается, не дублировать ли Telegram с `monitor_ssh`: пропуск при **`Type=ssh`** или если **`Service`** указывает на **sshd** (частый случай **`Type=tty` + `Service=sshd`**). При пустом ответе `loginctl` делается несколько коротких повторов (гонка с появлением строки в journal). Поставьте `0`, если нужны отдельные алерты logind и для SSH-сессий.
- `DAILY_REPORT_HOUR` — час (0..23), после наступления которого в **текущих календарных сутках** (в выбранной ниже зоне) отправляется не более одного ежедневного отчёта.
- `DAILY_REPORT_TZ` — необязательная **IANA**-зона (`Europe/Moscow`, `Asia/Yekaterinburg`, …). Если **пусто**, для отчёта используется та же зона, что и у команды `date` у процесса монитора (как правило, совпадает с `timedatectl` / `/etc/localtime` на сервере). Если сервис запускается с `TZ=UTC` в unit-файле, без `DAILY_REPORT_TZ` отчёт ориентируется на **UTC** — тогда задайте явную зону в конфиге.
- `DAILY_REPORT_TOP_IPS` — сколько IP показывать в топе неудачных попыток за 24 часа.
- `BRUTE_WINDOW_SEC` — окно (секунды) для оценки «массового» брутфорса по `journalctl`.
- `BRUTE_MIN_FAILS` — минимум неудачных попыток за окно для тревоги.
- `BRUTE_NOTIFY_COOLDOWN_SEC` — пауза между повторными уведомлениями по одному и тому же IP.
- `PROMETHEUS_TEXTFILE_DIR` — если задан существующий каталог, на каждой итерации пишется `ssh_monitor.prom` с метрикой `ssh_monitor_last_loop_unixtime`.
- `HEALTHCHECK_STATUS_FILE` — если задан, на каждой итерации обновляется JSON `{ "ts", "hostname", "dry_run" }`.
- `BAN_TIME` — длительность бана IP в секундах.
- `MAX_ATTEMPTS` — число неудачных SSH-попыток до автоматического бана.
- `BAN_CHECK_INTERVAL` — интервал проверки просроченных банов и аудита согласованности бан-листа с firewall (секунды).
- `MONITOR_INTERVAL` — пауза между итерациями основного цикла мониторинга (секунды).
- `WHITELIST_IPS` — белый список IP через запятую (IPv4 и IPv6 — точное совпадение).
- `WHITELIST_SUBNETS` — белый список подсетей **только IPv4** CIDR через запятую (например `10.0.0.0/24`).
- `WATCHDOG_MAX_HEARTBEAT_AGE` — через сколько секунд heartbeat считается устаревшим.
- `WATCHDOG_LOG_FILE` — лог-файл watchdog-скрипта.
- `WATCHDOG_SERVICE_NAME` — имя systemd-сервиса, который контролирует watchdog (по умолчанию `ssh-monitor.service`).
- `WATCHDOG_NOTIFY_ON_RECOVERY` — `1` включает служебные сообщения watchdog при штатном состоянии, `0` отключает.

### Мониторинг systemd-logind

- Собираются сообщения юнита **`systemd-logind`** через **`journalctl`** (`-o cat`): новые и завершённые сессии, а также строки с подстрокой *failed* (если включено).
- Без **`journalctl`** на хосте этот блок **не работает** (как и часть других функций, завязанных на journal).
- Для разбора «новой сессии» используются типичные англоязычные форматы (`New session … of user …`). При несовпадении формата строка всё равно попадёт в лог с пометкой о неудачном разборе.
- **`loginctl`** нужен только для **`LOGIND_SKIP_REMOTE`**: определяется `Type` сессии; для удалённого SSH обычно `ssh`, чтобы не дублировать уведомление с блоком мониторинга SSH.

Команда **`ssh-monitor --check-config`** выводит актуальные значения, в том числе параметры logind.

### Файлы-метки (`LAST_SSH_CHECK_FILE`, `LAST_SUDO_CHECK_FILE`, `LAST_LOGIND_CHECK_FILE`)

Для **SSH**, **sudo** и **logind** используется одна и та же политика:

1. **Файла ещё нет** — при первом же проходе создаётся файл с **текущим** unix-временем, в **`LOG_FILE`** пишется пояснение, **журнал за прошлое не разбирается** (нет лавины уведомлений).
2. **Файл есть, но пустой, не число, ноль или отрицательное значение** — содержимое считается ошибочным, файл **перезаписывается** текущим временем, бэклог **не** обрабатывается (та же защита, что и при первом запуске).
3. **В файле положительное unix-время** — с него строится окно `journalctl --since=@…` (или чтение лог-файлов для sudo при отсутствии journal), обрабатываются только события **после** этой метки.

Таким образом, «унифицирована» одна и та же модель: **либо валидная метка продолжения, либо безопасная инициализация без ретрансляции истории.**

Для **`LAST_SECURITY_EVENTS_FILE`** поведение другое: при отсутствии или невалидном значении окно начинается примерно с **часа назад** от текущего момента (чтобы не терять свежие тревоги и не тянуть весь журнал). Это отдельный блок (`monitor_security_events`).

## Режимы запуска

Обычный запуск (root):

```bash
sudo bash ./ssh-monitor
```

Проверка конфигурации и синтаксиса **без** запуска цикла, **без** изменений `iptables` и без обязательного Telegram:

```bash
sudo bash ./ssh-monitor --check-config
```

Режим **dry-run** (правила firewall не меняются; уведомления выводятся в stderr вместо отправки):

```bash
sudo bash ./ssh-monitor --dry-run
```

## Проверка синтаксиса

```bash
bash -n ./ssh-monitor
```

## Автозапуск через systemd

1. Скопируйте скрипт в постоянное место:
 - `sudo install -m 750 ./ssh-monitor /usr/local/bin/ssh-monitor`
2. Убедитесь, что конфиг есть:
 - `sudo cp ./ssh-monitor.conf.example /etc/ssh-monitor.conf` (если еще не создан)
 - `sudo chmod 600 /etc/ssh-monitor.conf`
3. Создайте unit-файл `/etc/systemd/system/ssh-monitor.service`:

```ini
[Unit]
Description=SSH Monitor with Telegram alerts
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssh-monitor
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
```

4. Включите и запустите сервис:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ssh-monitor
sudo systemctl start ssh-monitor
```

5. Проверка состояния и логов:

```bash
sudo systemctl status ssh-monitor
sudo journalctl -u ssh-monitor -f
```

## Ротация логов

Пример для `logrotate` лежит в репозитории: `contrib/logrotate.d/ssh-monitor`. Скопируйте файл в `/etc/logrotate.d/` и при необходимости поправьте пути под ваши `LOG_FILE` / `WATCHDOG_LOG_FILE` и другие файлы состояния в `/var/log/` (в т.ч. `LAST_*`, если решите их ротировать отдельно).

## Статистика без systemd (`journalctl`)

Для корректного подсчёта событий за последние 24 часа по файлам `/var/log/auth.log*` рекомендуется наличие **Python 3** на сервере. При его отсутствии счётчики в ежедневном отчёте для «классического» syslog могут быть занижены (используется безопасный fallback).

**Мониторинг `systemd-logind`** и другие части, использующие **`journalctl`**, на таких системах **не выполняются** или дают неполные данные — ориентируйтесь на окружение с **systemd** и доступным журналом.

## Watchdog (автоматическое восстановление)

Watchdog проверяет:

- активен ли `ssh-monitor.service`;
- не устарел ли heartbeat (`LAST_HEARTBEAT_FILE`).

Если сервис неактивен или heartbeat старше `WATCHDOG_MAX_HEARTBEAT_AGE`, watchdog выполняет `systemctl restart` и отправляет уведомление (Telegram и при сбое — `BACKUP_WEBHOOK_URL`, если задан).

### Установка watchdog

1. Установите watchdog-скрипт:
 - `sudo install -m 750 ./ssh-monitor-watchdog /usr/local/bin/ssh-monitor-watchdog`
2. Создайте unit и timer из примеров:
 - `sudo cp ./ssh-monitor-watchdog.service.example /etc/systemd/system/ssh-monitor-watchdog.service`
 - `sudo cp ./ssh-monitor-watchdog.timer.example /etc/systemd/system/ssh-monitor-watchdog.timer`
3. Примените и запустите timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ssh-monitor-watchdog.timer
sudo systemctl start ssh-monitor-watchdog.timer
```

4. Проверка:

```bash
sudo systemctl status ssh-monitor-watchdog.timer
sudo systemctl list-timers | grep ssh-monitor-watchdog
sudo journalctl -u ssh-monitor-watchdog.service -f
```
