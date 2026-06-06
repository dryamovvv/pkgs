# Arch Linux aarch64 Package Repository

## Architecture

Монорепозиторий пакетов Arch Linux aarch64, оптимизированный под Raspberry Pi 5 (Cortex-A76). Сборка — на нативных ARM64 GitHub-раннерах (`ubuntu-24.04-arm`), хостинг — GitHub Pages.

Репозиторий: `github:dryamovvv/pkgs`
URL репозитория pacman: `https://dryamovvv.github.io/pkgs/aarch64`

## Структура

```
pkgs/
├── packages/              # Каждый пакет — поддиректория с PKGBUILD
│   ├── <pkg-name>/
│   │   └── PKGBUILD
│   └── ...
├── ci/
│   ├── build-package.sh   # Обёртка сборки одного пакета
│   └── detect-changes.sh  # Детект изменённых пакетов относительно previous commit
├── .github/workflows/
│   └── build.yml          # Сборка + repo-add + деплой на gh-pages
├── .gitignore
├── AGENTS.md
└── README.md
```

## RPi5 оптимизация

CPU Cortex-A76, ARMv8.2-A. В makepkg.conf:

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
```

`-mcpu=cortex-a76` включает: armv8.2-a, crc, lse, rdma, fp16, dotprod, rcpc, fp+simd, fp+simd.
`+crypto` добавляет: AES, SHA1/SHA2, PMULL.
`-mtune` избыточен (GCC выводит из `-mcpu`).
`-fomit-frame-pointer` не нужен на AArch64 при `-O2`.

## Workflow (build.yml)

1. **detect** — `git diff --name-only HEAD~1 -- packages/`, формирует matrix пакетов (на ubuntu-latest)
2. **build** — matrix job: `runs-on: ubuntu-24.04-arm`, Docker `lfdevs/archlinuxarm:base-devel` + `docker cp`, сборка `makepkg -s --noconfirm` с RPi5 CFLAGS
3. **deploy** — `runs-on: ubuntu-24.04-arm`, Docker `lfdevs/archlinuxarm:base-devel`, `repo-add` внутри arch-контейнера, генерация index.html, `actions/deploy-pages@v4`

Особенности:

- `detect-changes.sh` обрабатывает первый коммит (HEAD~1 не существует) — собирает все пакеты
- При изменении `ci/` или `.github/workflows/` — пересборка всех пакетов
- Если изменений в `packages/` нет — `detect` выдаёт `[]`, сборка скипается
- В build-контейнере: `pacman-key --init && pacman-key --populate archlinuxarm`, создаётся пользователь `builder`
- Сборка через `docker run -d ... sleep infinity` + `docker cp` внутрь/наружу — решает проблему видимости артефактов (volume-монтирование нестабильно на GitHub Actions ARM64)
- Артефакты сборки загружаются как `.pkg.tar.*` (может быть `.xz` или `.zst`)

## Конфигурация pacman на RPi5

```ini
[custom-repo]
SigLevel = Optional TrustedOnly
Server = https://dryamovvv.github.io/pkgs/aarch64
```

## Добавление пакета

При добавлении нового пакета:

1. **Изучить возможности пакета** — изучить его документацию, `meson_options.txt`, `CMakeLists.txt`, `configure --help` и т.д. на предмет опциональных фич.
2. **Интерактивно спросить пользователя** о каждой опциональной фиче — объяснить, что фича даёт, какие зависимости тянет, и спросить включать или нет. Не принимать решения за пользователя.
3. **Документация всегда включается** — man-страницы и прочая документация (`-Ddocs=enabled`, `--enable-docs`, etc.) собираются по умолчанию. Если нужны дополнительные makedepends (например, `libxslt`, `docbook-xsl`, `doxygen`), они добавляются в `makedepends=()`.
4. **Создать PKGBUILD** с учётом выбранных опций.
5. **Использовать реальные SHA256** для всех upstream-исходников. Для локальных файлов — `'SKIP'`.

```bash
mkdir packages/<pkg-name>
# создать packages/<pkg-name>/PKGBUILD
git add packages/<pkg-name>
git commit -m "feat: add <pkg-name>"
git push
```

## CI настройки

Для деплоя необходимо включить GitHub Pages в режиме **GitHub Actions** (Settings → Pages → Source: GitHub Actions).
