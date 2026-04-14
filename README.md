# ssh-monitor

Bash-скрипт мониторинга **SSH**, **SUDO** и событий **`systemd-logind`** (локальные/графические сессии и др.) с уведомлениями в **Telegram** и по **электронной почте (SMTP)**, опциональным резервным webhook, авто-блокировкой IP (IPv4 через `iptables`, IPv6 через `ip6tables` при наличии) и ежедневным отчётом.

## Конфигурация

Скрипт читает параметры из `/etc/ssh-monitor.conf` в формате `KEY="value"`.

1. Скопируйте пример:
 - `sudo cp ./ssh-monitor.conf.example /etc/ssh-monitor.conf`
2. Ограничьте доступ:
 - `sudo chmod 600 /etc/ssh-monitor.conf`
3. Заполните минимум — **хотя бы один канал доставки оповещений** (иначе скрипт сразу завершится с ошибкой; см. абзац **«Обязательное условие»** ниже и раздел **«Каналы оповещений и пустой NOTIFY_CHAIN»**):
 - для **Telegram**: `TELEGRAM_BOT_TOKEN` и `TELEGRAM_CHAT_ID`;
 - или настройте **почту (SMTP)** по переменным ниже при `NOTIFY_ORDER=""` (автовыбор каналов).

**Обязательное условие:** после загрузки конфигурации в цепочке **`NOTIFY_CHAIN`** должен быть **минимум один** канал (`telegram` или `email`). Если каналов **нет** (пустой `NOTIFY_ORDER` и ни Telegram, ни SMTP не удовлетворяют критериям «настроен», либо в `NOTIFY_ORDER` остались только неизвестные имена), скрипт **не входит** в основной цикл и завершается с кодом **1**, в stderr: **`Не настроен ни один канал отправки оповещений`**. Это же правило действует для **`--check-config`** и **`--dry-run`**. Резервный **`BACKUP_WEBHOOK_URL`** в эту проверку **не входит** — он используется только если **ни один** канал из **`NOTIFY_CHAIN`** не смог доставить сообщение.

Поддерживаемые параметры:

- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- `NOTIFY_ORDER` — список каналов (`telegram`, `email` и сокращения **tg**, **mail**); при каждом оповещении скрипт **пытается отправить во все перечисленные** каналы по порядку (не «первый успешный — и стоп»). Пусто = в цепочку попадают только настроенные каналы (порядок по умолчанию см. в `ssh-monitor.conf.example`). Если итоговая цепочка пуста — скрипт не стартует (см. раздел **«Каналы оповещений и пустой NOTIFY_CHAIN»**).
- `MAIL_SMTP_HOST`, `MAIL_SMTP_PORT`, `MAIL_SMTP_USER`, `MAIL_SMTP_PASSWORD`, `MAIL_FROM`, `MAIL_TO`, `MAIL_SMTP_STARTTLS`, `MAIL_SMTP_SSL` — отправка почты через **python3** (см. таблицу каналов ниже)
- `BACKUP_WEBHOOK_URL` — резервная доставка JSON `{"text":"..."}` (например Slack Incoming Webhook), если **все** каналы из **`NOTIFY_CHAIN`** не смогли доставить сообщение; **не заменяет** обязательность хотя бы одного основного канала (см. шаг 3)
- `LOG_FILE`, `LAST_HEARTBEAT_FILE`, `LAST_REPORT_FILE`, `LAST_SSH_CHECK_FILE`, `LAST_SUDO_CHECK_FILE`, `LAST_SECURITY_EVENTS_FILE`, `LAST_LOGIND_CHECK_FILE`, `BAN_LIST_FILE`
- `ENABLE_LOGIND_MONITOR`, `LOGIND_NOTIFY_NEW`, `LOGIND_NOTIFY_REMOVED`, `LOGIND_NOTIFY_FAILED`, `LOGIND_SKIP_REMOTE` — см. раздел «Мониторинг systemd-logind» ниже
- `DAILY_REPORT_HOUR` (0..23), `DAILY_REPORT_TZ` (опционально), `NOTIFY_TZ` (опционально), `SSH_ACCEPT_NOTIFY_DEDUP_SEC`, `DAILY_REPORT_TOP_IPS`
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
- `NOTIFY_ORDER` — CSV имён каналов (`telegram`, `email` или `tg`, `mail`). Для **каждого** оповещения выполняется попытка доставки **во все** перечисленные каналы (при ошибке одного остальные всё равно пробуются; неудачи пишутся в **`LOG_FILE`**). Пустая строка: автоматически собирается цепочка только из реально настроенных каналов (по умолчанию порядок telegram → email; критерии «настроен» — **таблица** в разделе **«Каналы оповещений и пустой NOTIFY_CHAIN»**). Если после сборки цепочки **нет ни одного** канала, скрипт **сразу завершается** с ошибкой: **«Не настроен ни один канал отправки оповещений»** (в том числе режим `--check-config` и `--dry-run`).
- `MAIL_SMTP_HOST`, `MAIL_SMTP_PORT`, `MAIL_SMTP_USER`, `MAIL_SMTP_PASSWORD`, `MAIL_FROM`, `MAIL_TO`, `MAIL_SMTP_STARTTLS`, `MAIL_SMTP_SSL` — параметры SMTP для канала `email` (отправка через **python3**; см. таблицу «настроен»).
- `BACKUP_WEBHOOK_URL` — URL для резервной отправки (тело JSON `{"text":"..."}`); только fallback при сбое основных каналов, **не засчитывается** как «настроенный канал» (см. шаг 3).
- `LOG_FILE` — путь к основному лог-файлу скрипта.
- `LAST_HEARTBEAT_FILE` — файл с timestamp последнего heartbeat-сообщения.
- `LAST_REPORT_FILE` — дата последнего ежедневного отчёта в формате `YYYY-MM-DD` (старый формат Unix-времени при первом запуске будет автоматически интерпретирован).
- `LAST_SSH_CHECK_FILE` — файл с меткой времени последней проверки SSH-событий.
- `LAST_SUDO_CHECK_FILE` — файл с меткой времени последней проверки sudo-событий.
- `LAST_SECURITY_EVENTS_FILE` — метка последней проверки «тяжёлых» событий безопасности в журнале.
- `LAST_LOGIND_CHECK_FILE` — метка последней обработки журнала `systemd-logind` (unix-время); при первом запуске подтягивается около 30 минут истории.
- `BAN_LIST_FILE` — файл состояния банов (IP, время окончания бана и метаданные).
- `ENABLE_LOGIND_MONITOR` — `1` включает опрос `journalctl -u systemd-logind`, `0` полностью отключает этот блок.
- `LOGIND_NOTIFY_NEW` — `1` отправлять Telegram при появлении новой сессии в logind (строки вида *New session … of user …*).
- `LOGIND_NOTIFY_REMOVED` — `1` отправлять Telegram при завершении сессии (*Removed session …*); по умолчанию `0` (только запись в `LOG_FILE`, чтобы не заспамить канал).
- `LOGIND_NOTIFY_FAILED` — `1` отправлять Telegram по строкам logind, содержащим *failed* (широкий фильтр; при необходимости отключите).
- `LOGIND_SKIP_REMOTE` — `1` (по умолчанию): для новой сессии logind, если доступен `loginctl`, не отправляется второе Telegram, если сессия уже учтена в **`monitor_ssh`**: при **`Type=ssh`** или если **`Service`** указывает на **sshd** (часто **`Type=tty` + `Service=sshd`**); при пустом ответе `loginctl` делаются короткие повторы. Поставьте `0`, если нужны отдельные алерты logind и для SSH-сессий.
- `DAILY_REPORT_HOUR` — час (0..23), после наступления которого в **текущих календарных сутках** (в выбранной ниже зоне) отправляется не более одного ежедневного отчёта.
- `DAILY_REPORT_TZ` — необязательная **IANA**-зона (`Europe/Moscow`, `Asia/Yekaterinburg`, …). Если **пусто**, для отчёта используется та же зона, что и у команды `date` у процесса монитора (как правило, совпадает с `timedatectl` / `/etc/localtime` на сервере). Если сервис запускается с `TZ=UTC` в unit-файле, без `DAILY_REPORT_TZ` отчёт ориентируется на **UTC** — тогда задайте явную зону в конфиге.
- `NOTIFY_TZ` — **IANA**-зона для строк **«🕐 Время»** в Telegram/email (и аналогичных текстах). **Пусто** — используется **`DAILY_REPORT_TZ`**, если она задана, иначе зона процесса. Частая причина «время в теле сообщения UTC, а в заголовке чата локальное»: в **`ssh-monitor.service`** задано **`Environment=TZ=UTC`** — тогда задайте **`NOTIFY_TZ`** (или **`DAILY_REPORT_TZ`**) на вашу локаль, например `Asia/Vladivostok`.
- `SSH_ACCEPT_NOTIFY_DEDUP_SEC` — не чаще одного Telegram по **успешному SSH (`Accepted`)** на одну пару **пользователь + IP** за указанное число **секунд** (по умолчанию **5**). Снимает дубли, когда в journal две строки с **разными портами клиента** за один вход. **`0`** — отключить этот антидубль (останется только дедупликация внутри одного прохода `monitor_ssh` по `user|ip|port`).
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

### Каналы оповещений и пустой NOTIFY_CHAIN

Кратко, что считается **настроенным** каналом (только такие попадают в автоматическую цепочку при **`NOTIFY_ORDER=""`**):

| Канал | Условие «настроен» |
|--------|-------------------|
| `telegram` | заданы **`TELEGRAM_BOT_TOKEN`** и **`TELEGRAM_CHAT_ID`** |
| `email` | непустые **`MAIL_SMTP_HOST`**, **`MAIL_FROM`**, **`MAIL_TO`**, в PATH есть **`python3`** |

Если итоговый **`NOTIFY_CHAIN` пуст**, скрипт завершается с сообщением **`Не настроен ни один канал отправки оповещений`** (см. шаг 3 в разделе «Конфигурация» выше).

### Мониторинг systemd-logind

- Собираются сообщения юнита **`systemd-logind`** через **`journalctl`** (`-o cat`): новые и завершённые сессии, а также строки с подстрокой *failed* (если включено).
- Без **`journalctl`** на хосте этот блок **не работает** (как и часть других функций, завязанных на journal).
- Для разбора «новой сессии» используются типичные англоязычные форматы (`New session … of user …`). При несовпадении формата строка всё равно попадёт в лог с пометкой о неудачном разборе.
- **`loginctl`** нужен для **`LOGIND_SKIP_REMOTE`**: по `Type` и **`Service`** решается, не дублировать ли Telegram с **`monitor_ssh`** (см. описание `LOGIND_SKIP_REMOTE` выше).
- **`monitor_ssh`**: события **sshd** читаются из journal преимущественно как **`journalctl _COMM=sshd`** (запасные варианты — юниты `sshd` / `ssh`), строки **`sort -u`**, для **`Accepted`** в одном проходе — дедуп по **пользователь|IP|порт**; между проходами цикла — пауза **`SSH_ACCEPT_NOTIFY_DEDUP_SEC`** для той же пары **пользователь|IP** (см. переменную в конфиге).

Команда **`ssh-monitor --check-config`** выводит актуальные значения, в том числе параметры logind.

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

## Релизный архив

Версия задаётся в скрипте переменной **`SSH_MONITOR_VERSION`** (текущая стабильная — **1.0.0**). Сборка tarball из текущего git-дерева:

```bash
make dist
```

Появится файл `ssh-monitor-<версия>.tar.gz` (через `git archive`). Готовые архивы для установки без клона репозитория прикладываются к [релизам на GitHub](https://github.com/PTah/ssh-monitor/releases).

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

**Ключевые темы (для поиска):** мониторинг **SSH** и **sshd**, **bash**-скрипт для **Linux**-сервера, уведомления в **Telegram** и по **SMTP** / электронной почте, **systemd-logind**, **sudo**, **journalctl**, **iptables** / **ip6tables**, автоматический **бан IP** и **whitelist**, **systemd** unit, **ежедневный отчёт**, **heartbeat**, **OpenSSH**, безопасность сервера, **Prometheus** textfile, опционально **watchdog** для сервиса.
