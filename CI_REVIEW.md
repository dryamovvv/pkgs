# 🔍 Глобальный Review CI/CD Pipeline

**Дата:** 2026-06-07  
**Статус:** 🔴 Критические проблемы найдены

---

## 📋 Содержание
1. [Критические проблемы](#критические-проблемы)
2. [Высокий приоритет](#высокий-приоритет)
3. [Среднийприоритет](#средний-приоритет)
4. [Рекомендации](#рекомендации)

---

## 🔴 Критические проблемы

### 1. **Deploy: конфликт пути в `deploy-package.sh`** (КРИТИЧНО)

**Файл:** `ci/deploy-package.sh:34,43`  
**Проблема:**
```bash
STAGING="$STAGING_BASE/$PKGNAME"  # /tmp/pkgs-staging/atuin-18.16.1-1-aarch64.pkg.tar.xz
ssh ... "mkdir -p $STAGING $REPO_PATH"  # ❌ пытается создать dir с названием файла пакета
```

**Последствия:**
- `mkdir: can't create directory '...pkg.tar.xz': File exists` — пакет не деплоится
- Все 10 попыток переразвёртывания падают одинаково
- Deploy падает 100% времени после успешной сборки

**Решение:**
```bash
# Вариант 1: Использовать отдельную директорию для каждого деплоя
STAGING=$(mktemp -d "$STAGING_BASE/deploy-XXXXXX")  # /tmp/pkgs-staging/deploy-abc123

# Вариант 2: Очищать перед созданием
ssh $SSH_OPTS "$REMOTE" "rm -rf $STAGING_BASE/* && mkdir -p $STAGING $REPO_PATH"

# Вариант 3 (рекомендуемый - минимальный): Просто не создавать файл-директорию
STAGING="$STAGING_BASE"  # Использовать только базовую директорию
# И передавать файл напрямую:
scp $SCP_OPTS "$PKGFILE" "$REMOTE:$STAGING/"
```

---

### 2. **Build: падение тестов атuin на DB connection** (КРИТИЧНО)

**Файл:** `ci/build-package.sh:44`  
**Проблема:**
```
ERROR sync::common server error, error=failed to connect to db: 
DbSettings { db_uri: "***localhost:5432/atuin" }
```

**Последствия:**
- Интеграционный тест `sync` требует PostgreSQL локально
- В контейнере нет BD — тест падает
- Build прерывается, deploy не запускается

**Решение (выбрать один вариант):**

**Вариант А — Пропустить интеграционные тесты в CI:**
```bash
# ci/build-package.sh строка 44
# Вместо:
su builder -c "makepkg -s --noconfirm"

# Использовать:
su builder -c "makepkg -s --noconfirm --skip-test" || \
su builder -c "makepkg -s --noconfirm --notest" || \
su builder -c "makepkg -s --noconfirm"  # Если пакет поддерживает эти флаги
```

**Вариант Б — Добавить PostgreSQL в контейнер:**
```bash
# ci/build-package.sh перед su builder
pacman -Sy --noconfirm postgresql
initdb -D /tmp/postgres
pg_ctl -D /tmp/postgres start &
sleep 2
createuser -d builder
createdb -O builder atuin
# Установить DB_URL
export DATABASE_URL="postgresql://builder:@localhost/atuin"
```

**Вариант В (рекомендуемый) — Явно пропустить конкретный тест:**
```bash
# .github/workflows/build.yml
- name: Build in container
  env:
    CARGO_TEST_THREADS: 1
    # Пропустить sync тест (требует DB):
    SKIP_SYNC_TEST: 1
```

**Вариант Г — Условно пропускать test в PKGBUILD:**
```bash
# Добавить в packages/atuin/PKGBUILD:
check() {
  if [ -z "${CI:-}" ]; then
    cd "$pkgname-$pkgver"
    cargo test --release
  fi
}

# Тогда в workflow:
- name: Build in container
  env:
    CI: 1
```

---

### 3. **Workflow: недостаточные проверки SSH секретов** (КРИТИЧНО)

**Файл:** `.github/workflows/build.yml:136-139`  
**Проблема:**
- Секреты не проверяются перед использованием
- Если SSH_HOST или SSH_USER не установлены → build падает без понятной ошибки
- SSH ключ не валидируется перед использованием

**Решение:**
```yaml
- name: Validate SSH secrets
  run: |
    [ -n "${{ secrets.SSH_HOST }}" ] || { echo "ERROR: SSH_HOST not set"; exit 1; }
    [ -n "${{ secrets.SSH_PORT }}" ] || { echo "ERROR: SSH_PORT not set"; exit 1; }
    [ -n "${{ secrets.SSH_USER }}" ] || { echo "ERROR: SSH_USER not set"; exit 1; }
    [ -n "${{ secrets.SSH_PRIVATE_KEY }}" ] || { echo "ERROR: SSH_PRIVATE_KEY not set"; exit 1; }
    echo "✓ All SSH secrets are configured"
```

---

## 🟠 Высокий приоритет

### 4. **Permissions: недостаточные разрешения для Report Job**

**Файл:** `.github/workflows/build.yml:158-160`  
**Проблема:**
```yaml
permissions:
  issues: write
  actions: write
```

- Для работы `report-failure.sh` может потребоваться `contents: read` (для checkout)
- Нет явного `pull-requests` permission для PR-комментариев (если будут)

**Решение:**
```yaml
permissions:
  contents: read      # Нужно для checkout
  issues: write       # Для создания issues
  actions: read       # Для чтения логов runs
```

---

### 5. **Cache invalidation: слишком частый пересчёт хешей**

**Файл:** `.github/workflows/build.yml:71,79,89`  
**Проблема:**
- `pacman-cache` — пересчитывается при любом PKGBUILD всех пакетов (`packages/*/PKGBUILD`)
- При добавлении нового пакета кэш инвалидируется для **всех** сборок
- Не масштабируется с ростом количества пакетов

**Примеры плохих сценариев:**
```
1. Добавляю package-Z
2. Все пакеты (A-Y) теряют pacman-cache ❌
3. Каждая сборка переустанавливает все зависимости
```

**Решение:**
```yaml
# Вариант А - Использовать префикс-ключи правильно:
- name: Cache pacman packages
  uses: actions/cache@v5
  with:
    path: /tmp/pacman-cache
    # БЫЛО: key: pacman-cache-v2-${{ hashFiles('packages/*/PKGBUILD') }}
    # СТАЛО: Не включать все PKGBUILD
    key: pacman-cache-v2-${{ github.sha }}
    restore-keys: |
      pacman-cache-v2-
```

Или более безопасно:
```yaml
    key: pacman-cache-v2-shared
    restore-keys: |
      pacman-cache-v2-shared
```

---

### 6. **Timeout 90 минут может быть недостаточным**

**Файл:** `.github/workflows/build.yml:94`  
**Проблема:**
- Некоторые пакеты (Rust проекты, Qt) могут компилироваться > 90 мин
- Нет раздельных timeouts для разных пакетов
- No graceful degradation

**Решение:**
```yaml
- name: Build in container
  timeout-minutes: 120  # Увеличить до 2 часов
  run: |
    # Добавить timeout warning на 85 мин
    ( sleep 5100; echo "WARNING: Approaching 90-minute timeout" >&2 ) &
```

Или использовать matrix per-package timeout:
```yaml
strategy:
  matrix:
    include:
      - pkg: atuin
        timeout: 90
      - pkg: rust-project
        timeout: 120
      - pkg: simple-binary
        timeout: 45
```

---

## 🟡 Средний приоритет

### 7. **Docker cleanup не полный**

**Файл:** `.github/workflows/build.yml:97,152`  
**Проблема:**
```bash
docker rm -f builder 2>/dev/null || true  # ❌ Только контейнер
# Не удаляются: volumes, networks, images из предыдущих попыток
```

**Решение:**
```bash
# build step
docker system prune -a -f --volumes
docker rm -f builder 2>/dev/null || true

# Stop container step
docker rm -f builder 2>/dev/null || true
# Опционально:
docker volume prune -f 2>/dev/null || true
```

---

### 8. **Cargo permissions fix только на `always()`**

**Файл:** `.github/workflows/build.yml:107-110`  
**Проблема:**
```yaml
if: always()  # ✓ Хорошо
# Но используется sudo — может потребовать пароля
sudo chown -R $(id -u):$(id -g) ...
```

**Решение:**
```yaml
- name: Fix cargo cache permissions
  if: always()
  run: |
    docker exec -u root builder bash -c \
      "chown -R 1000:1000 /home/builder/.cargo"
```

---

### 9. **Отсутствует validation на успешность artifact upload**

**Файл:** `.github/workflows/build.yml:142-147`  
**Проблема:**
```yaml
- name: Upload artifact
  uses: actions/upload-artifact@v7
  with:
    if-no-files-found: error  # ✓ Есть
    # Но нет проверки доступного места на диске
    # Может упасть с "No space left on device"
```

**Решение:**
```yaml
- name: Check disk space before artifact upload
  run: |
    AVAILABLE=$(df /home/runner -B 1 | tail -1 | awk '{print $4}')
    NEEDED=$(du -sb packages-built | awk '{print $1}')
    if [ $AVAILABLE -lt $NEEDED ]; then
      echo "ERROR: Not enough disk space"
      df -h
      exit 1
    fi
    
- name: Upload artifact
  uses: actions/upload-artifact@v7
  with:
    name: ${{ matrix.pkg }}
    path: packages-built/${{ matrix.pkg }}/*.pkg.tar.*
    if-no-files-found: error
    retention-days: 30  # Добавить retention
```

---

### 10. **Report-failure: слабая обработка ошибок**

**Файл:** `.github/workflows/build.yml:164-174`  
**Проблема:**
- Скрипт `ci/report-failure.sh` не существует (не найден в repo)
- Нет обработки ошибок если скрипт упадёт
- Матрица может быть некорректной JSON при ошибке

**Решение:**
```yaml
- name: Create or update failure issue
  if: failure()
  continue-on-error: true  # Не срывать сам workflow если этот step упадёт
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    if [ ! -f ci/report-failure.sh ]; then
      echo "WARNING: report-failure.sh not found"
      exit 0
    fi
    chmod +x ci/report-failure.sh
    ci/report-failure.sh \
      "${{ github.repository }}" \
      "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
      "${{ github.sha }}" \
      "${{ github.run_id }}" \
      '${{ needs.detect.outputs.matrix }}'
```

---

### 11. **Concurrency policy может привести к потерянным деплоям**

**Файл:** `.github/workflows/build.yml:21-23`  
**Проблема:**
```yaml
concurrency:
  group: deploy-${{ github.ref }}  # Группирует по ветке
  cancel-in-progress: false       # ✓ Хорошо не отменять
# НО: Если push'ится быстро 2-3 раза — они будут ждать друг друга
# при успешности каждого потребляя ресурсы
```

**Решение:**
```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false
  
# Добавить guard чтобы не запускались одновременно:
jobs:
  build:
    runs-on: ubuntu-24.04-arm
    if: |
      github.event_name != 'push' ||
      (
        github.ref == 'refs/heads/main' &&
        startsWith(github.event.head_commit.message, '[deploy]')
      )
```

---

### 12. **Deploy: SSH connection может быть заражена MITM**

**Файл:** `ci/deploy-package.sh:19`  
**Проблема:**
```bash
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no ..."  # ❌ ОПАСНО!
```

**Последствия:**
- Восприимчив к man-in-the-middle атакам
- При кэшировании keys в Actions — потенциальный вектор атаки

**Решение:**
```bash
# Вариант А - Использовать host keys:
ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>/dev/null
SSH_OPTS="-i $SSH_KEY -p $SSH_PORT"

# Вариант Б - Проверить fingerprint:
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p $SSH_PORT"
```

Добавить в workflow перед deploy:
```yaml
- name: Add SSH host key to known_hosts
  run: |
    mkdir -p ~/.ssh
    ssh-keyscan -p ${{ secrets.SSH_PORT }} ${{ secrets.SSH_HOST }} >> ~/.ssh/known_hosts 2>/dev/null || true
```

---

### 13. **Deploy: log-секреты не скрыты достаточно**

**Файл:** `ci/deploy-package.sh:8`  
**Проблема:**
```bash
REPO_PATH="${REPO_PATH:-/tmp/mnt/e73e95d7-6854-49b0-8a0a-b0a8923ad782/aarch64}"
```

- UUID видно в логах и git истории
- Если REPO_PATH изменится — нужно перепушить весь workflow

**Решение:**
```bash
# Переместить в secrets
REPO_PATH="${REPO_PATH:-}"
if [ -z "$REPO_PATH" ]; then
  echo "ERROR: REPO_PATH must be set via SSH_REPO_PATH secret"
  exit 1
fi
```

Добавить в workflow:
```yaml
env:
  REPO_PATH: ${{ secrets.SSH_REPO_PATH }}
```

---

## 📊 Рекомендации

### Priority Matrix

| Проблема | Severity | Effort | Priority |
|----------|----------|--------|----------|
| #1 Deploy path conflict | CRITICAL | 🟢 Low | 🔴 P0 |
| #2 DB connection test | CRITICAL | 🟢 Low | 🔴 P0 |
| #3 SSH secret validation | CRITICAL | 🟢 Low | 🔴 P0 |
| #4 Permissions | HIGH | 🟢 Low | 🟠 P1 |
| #5 Cache invalidation | HIGH | 🟡 Med | 🟠 P1 |
| #6 Timeout | HIGH | 🟢 Low | 🟠 P1 |
| #7 Docker cleanup | MEDIUM | 🟢 Low | 🟡 P2 |
| #8 Cargo perms | MEDIUM | 🟢 Low | 🟡 P2 |
| #9 Artifact disk check | MEDIUM | 🟡 Med | 🟡 P2 |
| #10 Report failure | MEDIUM | 🟢 Low | 🟡 P2 |
| #11 Concurrency | MEDIUM | 🟢 Low | 🟡 P2 |
| #12 SSH MITM risk | HIGH | 🟢 Low | 🟠 P1 |
| #13 UUID in logs | MEDIUM | 🟢 Low | 🟡 P2 |

---

### Quick Fix Checklist (для немедленного исправления)

- [ ] **Немедленно:** Исправить deploy path conflict (#1)
- [ ] **Немедленно:** Пропустить/исправить тест DB (#2)
- [ ] **Немедленно:** Валидировать SSH секреты (#3)
- [ ] **Сегодня:** Исправить SSH StrictHostKeyChecking (#12)
- [ ] **Сегодня:** Проверить Permissions (#4)
- [ ] **На неделю:** Переработать cache strategy (#5)
- [ ] **На неделю:** Добавить checks для artifact space (#9)

---

### Architecture Improvements

1. **Разделить CI на этапы:**
   - Stage 1: Detect (fast)
   - Stage 2: Build (parallel, per-package timeout)
   - Stage 3: Deploy (serialized, with backoff)
   - Stage 4: Report (non-blocking)

2. **Улучшить retry механизм:**
   - Экспоненциальная backoff (3s, 6s, 12s, 24s...)
   - Разные стратегии для разных типов ошибок (network vs compilation)

3. **Добавить observability:**
   - Логирование всех шагов в структурированном формате
   - Metrics для build time per package
   - Alerts на регулярно падающие пакеты

---

## 📝 Итоговый Score

| Категория | Score | Notes |
|-----------|-------|-------|
| Reliability | 2/10 | Deploy всегда падает из-за #1, тесты из-за #2 |
| Security | 3/10 | SSH без host key checking (#12), UUID в логах (#13) |
| Maintainability | 5/10 | Хороший структурный дизайн, но нет обработки ошибок |
| Performance | 6/10 | Cache хорошо, но инвалидируется часто (#5) |
| **OVERALL** | **4/10** | 🔴 Требует срочного исправления |

---

**Генерировано:** Copilot Review CI  
**Рекомендация:** Начните с #1, #2, #3 — они blocking issues
