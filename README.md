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
- `NOTIFY_ORDER` — явная очередь каналов оповещений (`telegram`, `zabbix`, `email` и сокращения); пусто = в цепочку попадают только настроенные каналы (порядок по умолчанию см. в `ssh-monitor.conf.example`)
- `ZABBIX_SERVER`, `ZABBIX_HOST_NAME`, `ZABBIX_ALERT_KEY`, `ZABBIX_SEQ_KEY` — отправка в Zabbix через `zabbix_sender`; подробнее — раздел **«Zabbix (`zabbix_sender`)»** ниже
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
- `NOTIFY_ORDER` — CSV имён каналов (`telegram`, `zabbix`, `email` или `tg`, `zbx`, `mail`). Пустая строка: автоматически собирается цепочка только из реально настроенных каналов (по умолчанию порядок telegram → zabbix → email).
- `ZABBIX_SERVER` — имя или IP сервера Zabbix для `zabbix_sender -z` (пусто = канал Zabbix отключён).
- `ZABBIX_HOST_NAME` — имя **хоста в Zabbix**, как в конфигурации агента/шаблона (`-s` у `zabbix_sender`); должно совпадать с тем, для какого хоста созданы trapper-элементы.
- `ZABBIX_ALERT_KEY` — ключ **первого** trapper-элемента: в него уходит **текст** оповещения (одна строка, переводы строк заменены пробелами).
- `ZABBIX_SEQ_KEY` — ключ **второго** trapper-элемента: в него при каждой отправке пишется **монотонно растущий счётчик** (1, 2, 3, … за время работы процесса скрипта). Значение по умолчанию — `ssh.monitor.seq`. Назначение: чтобы Zabbix и триггеры видели **новое значение** даже при **одинаковом** тексте алерта (иначе повтор с тем же текстом может плохо отражаться на логике «изменилось ли значение»); также по счётчику удобнее отслеживать порядок событий. В шаблоне Zabbix нужны **два** элемента типа **Zabbix trapper** с ключами, совпадающими с `ZABBIX_ALERT_KEY` и `ZABBIX_SEQ_KEY` (второй — обычно **числовой**).
- `BACKUP_WEBHOOK_URL` — URL для резервной отправки (тело JSON `{"text":"..."}`).
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
- `LOGIND_SKIP_REMOTE` — `1` (по умолчанию): для новой сессии, если доступен `loginctl`, запрашивается тип сессии; при `Type=ssh` **второе** уведомление в Telegram не отправляется (успешный SSH уже покрывает `monitor_ssh`), в лог пишется пояснение. Поставьте `0`, если нужны отдельные алерты logind и для SSH-сессий.
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

### Zabbix (`zabbix_sender`)

Канал активен, если в **`NOTIFY_CHAIN`** есть `zabbix`, заданы **`ZABBIX_SERVER`** и **`ZABBIX_HOST_NAME`**, в PATH есть **`zabbix_sender`**.

При отправке формируется временный файл с **двумя** строками в формате `ключ<TAB>значение`:

1. **`ZABBIX_ALERT_KEY`** (по умолчанию `ssh.monitor.alert`) — текст сообщения.
2. **`ZABBIX_SEQ_KEY`** (по умолчанию `ssh.monitor.seq`) — целое **число-счётчик**, увеличивается на 1 при каждой отправке в Zabbix.

Имеет смысл завести в Zabbix на соответствующем хосте **два trapper-элемента** с этими ключами. Ключ **`ZABBIX_SEQ_KEY`** можно переименовать в конфиге, если в вашем шаблоне приняты другие имена; смысл остаётся тем же: отдельный item под **последовательность**, а не под человекочитаемый текст.

### Мониторинг systemd-logind

- Собираются сообщения юнита **`systemd-logind`** через **`journalctl`** (`-o cat`): новые и завершённые сессии, а также строки с подстрокой *failed* (если включено).
- Без **`journalctl`** на хосте этот блок **не работает** (как и часть других функций, завязанных на journal).
- Для разбора «новой сессии» используются типичные англоязычные форматы (`New session … of user …`). При несовпадении формата строка всё равно попадёт в лог с пометкой о неудачном разборе.
- **`loginctl`** нужен только для **`LOGIND_SKIP_REMOTE`**: определяется `Type` сессии; для удалённого SSH обычно `ssh`, чтобы не дублировать уведомление с блоком мониторинга SSH.

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
