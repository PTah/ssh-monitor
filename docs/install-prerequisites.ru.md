# Системные зависимости и установка окружения

Этот документ описывает, **какой софт** на сервере нужен для работы **ssh-monitor**, и **как его поставить** типовыми пакетами. Саму установку скрипта, конфигов и **systemd** смотрите в корневом [README.md](../README.md).

## 1. Что должно быть на хосте

### Обязательно

| Назначение | Что используется | Примечание |
|------------|------------------|------------|
| Интерпретатор | **Bash** (версия с `declare -A`) | Обычно уже есть (`/bin/bash`). |
| Запуск брандмауэра | **iptables**; для IPv6 — **ip6tables** (если баните IPv6) | Скрипт добавляет правила `DROP` для заблокированных IP. Нужен **root** (скрипт не стартует без root, кроме `--dry-run` / проверок). |
| Telegram | **curl** | Запросы к `api.telegram.org`. |
| Почта (канал `email`) | **Python 3** | SMTP через стандартную библиотеку. |
| Резервный webhook | **Python 3** + **curl** | Сборка JSON и `POST`. |

Без **хотя бы одного** настроенного канала (`telegram` или `email`) скрипт завершится с ошибкой — это не зависимости ОС, а настройка в `/etc/ssh-monitor.conf`.

### Настоятельно рекомендуется (полный функционал)

| Назначение | Что используется |
|------------|------------------|
| Журнал SSH/sudo/брутфорс, logind | **systemd** + **`journalctl`** |
| Дедупликация уведомлений logind для SSH | **`loginctl`** (часть **systemd**) |
| Удобный просмотр логов сервиса | **`journalctl`** |

На минималистичных системах без **journald** часть функций не работает или упрощается; отчёт за сутки по SSH может опираться на **`/var/log/auth.log`** (см. ниже).

### Утилиты из «базовой» системы

Обычно уже установлены: `grep`, `sed`, `awk`, `sort`, `date`, `who`, `mktemp`, `sudo` (если запускаете не напрямую от root), `wc`, `hostname`, `ip` (для подписи сервера в уведомлениях). Для дедупликации sudo в журнале желательны **`sha256sum`** или **`cksum`**.

---

## 2. Пошаговая установка пакетов (Debian / Ubuntu)

Выполняйте от пользователя с `sudo`.

**Шаг 1.** Обновить индексы пакетов:

```bash
sudo apt update
```

**Шаг 2.** Минимум для Telegram и бана по firewall:

```bash
sudo apt install -y iptables curl
```

При необходимости IPv6 (если на сервере используется `ip6tables`):

```bash
sudo apt install -y ip6tables
```

(На многих образах **ip6tables** уже входит в метапакет с iptables.)

**Шаг 3.** Если включите доставку почты (`MAIL_*` в конфиге) или **BACKUP_WEBHOOK_URL** (через Python):

```bash
sudo apt install -y python3
```

**Шаг 4.** Типовой сервер с **systemd** уже содержит `journalctl` и `loginctl`. Если ставите минимальный контейнер без них — для полного мониторинга нужен стек с **systemd** и **journald** (или см. раздел про ограничения без journald).

**Шаг 5.** (Опционально) Сохранение правил **iptables** после перезагрузки — отдельно от ssh-monitor, например:

```bash
sudo apt install -y iptables-persistent netfilter-persistent
```

Скрипт при наличии каталога **`/etc/iptables`** может записывать туда `rules.v4` / `rules.v6` (см. код `save_iptables_rules`). Имеет смысл создать каталог и настроить автозагрузку правил по документации вашего дистрибутива.

---

## 3. Другие дистрибутивы

Принцип тот же: пакеты **bash**, **iptables** (+ **ip6tables**), **curl**, **python3**; для полного функционала — **systemd** с **journald**.

Примеры:

- **RHEL / Alma / Rocky:** `dnf install iptables curl python3 systemd` (имена метапакетов могут отличаться).
- **Alpine:** `apk add bash iptables ip6tables curl python3` — отдельно проверьте наличие **systemd** / **journalctl** (на Alpine часто нет; мониторинг по journal будет недоступен).

---

## 4. Системы без `journalctl` (классический syslog)

- События **SSH** могут читаться из **`/var/log/auth.log`** (если скрипт не находит `journalctl`).
- **Ежедневная статистика** по этим файлам для отчёта **точнее с Python 3** (разбор логов в скрипте). Без Python отчёт может использовать упрощённый fallback.
- Блоки, завязанные на **`journalctl`** (**sudo** по журналу, **systemd-logind**, часть **security/brute**), на таком хосте **не дадут полного результата**.

---

## 5. Конфликты с UFW / другими обёртками firewall

Скрипт вставляет правила **iptables** самостоятельно. Если используете **UFW**, **firewalld** или только **nftables** без совместимости с iptables-nft, возможны конфликты или неожиданный порядок правил. После внедрения проверьте:

```bash
sudo iptables -L INPUT -n -v --line-numbers
```

При необходимости согласуйте порядок с вашей схемой управления firewall.

---

## 6. Опционально: watchdog

Скрипт **`ssh-monitor-watchdog`** проверяет сервис `ssh-monitor.service` и актуальность heartbeat; при сбое выполняет `systemctl restart`.

**Установка:**

1. Скопируйте скрипт:  
   `sudo install -m 750 ./ssh-monitor-watchdog /usr/local/bin/ssh-monitor-watchdog`
2. Установите unit и timer:  
   `sudo cp ./ssh-monitor-watchdog.service.example /etc/systemd/system/ssh-monitor-watchdog.service`  
   `sudo cp ./ssh-monitor-watchdog.timer.example /etc/systemd/system/ssh-monitor-watchdog.timer`
3. Включите timer:

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

Параметры watchdog задаются в **`/etc/ssh-monitor.conf`** (переменные `WATCHDOG_*` в примере конфига).

---

## 7. Краткий чек-лист перед первым запуском

- [ ] Установлены **iptables** (и при необходимости **ip6tables**).
- [ ] Для Telegram установлен **curl**; для почты / webhook — **python3**.
- [ ] Настроен **`/etc/ssh-monitor.conf`** (минимум один канал уведомлений).
- [ ] Понятен порядок правил firewall на хосте (UFW и т.д.).
- [ ] (По желанию) настроено сохранение правил после перезагрузки.

Далее: установка самого **`ssh-monitor`**, unit **systemd** и проверка — в [README.md](../README.md).
