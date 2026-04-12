# ssh-monitor

Bash-скрипт мониторинга SSH/SUDO с уведомлениями в Telegram, опциональным резервным webhook, авто-блокировкой IP (IPv4 через `iptables`, IPv6 через `ip6tables` при наличии) и ежедневным отчётом.

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
- `LOG_FILE`, `LAST_HEARTBEAT_FILE`, `LAST_REPORT_FILE`, `LAST_SSH_CHECK_FILE`, `LAST_SUDO_CHECK_FILE`, `LAST_SECURITY_EVENTS_FILE`, `BAN_LIST_FILE`
- `DAILY_REPORT_HOUR` (0..23), `DAILY_REPORT_TOP_IPS`
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
- `LAST_SSH_CHECK_FILE` — файл с меткой времени последней проверки SSH-событий.
- `LAST_SUDO_CHECK_FILE` — файл с меткой времени последней проверки sudo-событий.
- `LAST_SECURITY_EVENTS_FILE` — метка последней проверки «тяжёлых» событий безопасности в журнале.
- `BAN_LIST_FILE` — файл состояния банов (IP, время окончания бана и метаданные).
- `DAILY_REPORT_HOUR` — локальный час (0..23), после наступления которого в текущих сутках отправляется не более одного ежедневного отчёта.
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

Пример для `logrotate` лежит в репозитории: `contrib/logrotate.d/ssh-monitor`. Скопируйте файл в `/etc/logrotate.d/` и при необходимости поправьте пути под ваши `LOG_FILE` / `WATCHDOG_LOG_FILE`.

## Статистика без systemd (`journalctl`)

Для корректного подсчёта событий за последние 24 часа по файлам `/var/log/auth.log*` рекомендуется наличие **Python 3** на сервере. При его отсутствии счётчики в ежедневном отчёте для «классического» syslog могут быть занижены (используется безопасный fallback).

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
