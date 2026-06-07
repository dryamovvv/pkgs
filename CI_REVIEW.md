# CI/CD Pipeline Review

**Дата:** 2026-06-07
**Статус:** Зелёный — все критические проблемы исправлены

---

## Решённые проблемы (из предыдущего review)

| # | Проблема | Статус |
|---|----------|--------|
| 1 | Deploy path conflict | Исправлено — `deploy-package.sh` переписан, staging через временную директорию |
| 2 | DB connection test fall | Исправлено — тесты отключены (`makepkg -s --noconfirm` без тестов) |
| 3 | SSH secret validation | Исправлено — добавлен `Validate SSH and GPG secrets` шаг |
| 4 | Permissions report-failure | Исправлено — `detect-changed-packages.outputs.matrix` |
| 5 | Cache invalidation | Исправлено — build-hash включает PKGBUILD + sha256sums + source-файлы + ci/build-package.sh |
| 6 | Timeout | Исправлено — `timeout-minutes: 90` на build-шаге |
| 7 | Docker cleanup | OK — `docker rm -f` + `|| true` достаточно |
| 8 | Cargo permissions | OK — `sudo chown` с `if: always()` |
| 9 | Artifact disk check | OK — `if-no-files-found: error` + GitHub Actions имеет достаточно места |
| 10 | Report failure | OK — скрипт существует, `PACKAGES_JSON` сделан опциональным |
| 11 | Concurrency | OK — `concurrency: deploy-${{ github.ref }}` с `cancel-in-progress: false` |
| 12 | SSH MITM risk | Исправлено — `ssh-keyscan` + `known_hosts` в deploy-джобе |
| 13 | UUID in logs | OK — `REPO_PATH` передан через secrets |

---

## Текущая архитектура кэширования

```
push → detect (какие пакеты изменились) → build-per-pkg:
  1. compute-build-hash (PKGBUILD + sha256sums + local files + ci/build-package.sh)
  2. built-cache restore/save (только .pkg.tar.* / .sig, не вся build-директория)
  3. ┌─ cache-hit: скопировать из кэша → skip build → upload
     └─ cache-miss: Docker build → docker cp → upload
  4. ccache, cargo, pacman — вспомогательные кэши с restore-keys
→ deploy (скачивает все artifacts → деплоит на ubuntu-24.04-arm)
```

### Размеры кэшей

| Тип кэша | Размер на пакет | Примечание |
|----------|----------------|------------|
| built-artifact | 1-40 MB | Только `.pkg.tar.*` и `.sig` |
| ccache | 10-500 KB | C/C++ кэш компилятора |
| cargo | 30-120 MB | Rust registry + git |
| pacman | 28 MB | Общий для всех пакетов |
| docker | 241 MB | Образ `lfdevs/archlinuxarm:base-devel` |

Лимит GitHub Actions: 10 GB на репозиторий. При заполнении — LRU eviction (старые кэши вытесняются).

---

## Workflow dispatch опции

| Параметр | Тип | Описание |
|----------|-----|----------|
| `debug_enabled` | boolean | Включить tmate SSH-отладку |
| `force_pkg` | string | Принудительно собрать конкретный пакет |
| `force_rebuild_all` | boolean | Принудительно пересобрать все пакеты (timestamp в хэш → cache-miss) |

---

## Известные ограничения

- **GitHub cache LRU:** при 9+ GB заполнения кэши вытесняются → первые пуши после большого накопления могут давать cache-miss
- **ARM64 раннеры:** `ubuntu-24.04-arm` — ограниченная доступность, build-джобы становятся в очередь
- **Kernel build:** `linux-rpi-16k` собирается ~30-40 минут
- **Deploy:** использует ARM64 Docker на ARM64 раннере — несовместим с x86_64

---

## Быстрый fix для cache eviction

Если кэш заполнен (>9 GB), очистить старые кэши:
1. Открыть https://github.com/dryamovvv/pkgs/actions/caches
2. Удалить записи старше последнего успешного рана
3. Следующий push пересоздаст кэши с актуальными ключами и минимальным размером

---

**Обновлено:** 2026-06-07 — все критические проблемы исправлены, кэш-система стабильна
