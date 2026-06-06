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
3. **deploy** — `repo-add` внутри arch-контейнера, генерация index.html, `actions/deploy-pages@v4`

Особенности:

- `detect-changes.sh` обрабатывает первый коммит (HEAD~1 не существует) — собирает все пакеты
- При изменении `ci/` или `.github/workflows/` — пересборка всех пакетов
- Если изменений в `packages/` нет — `detect` выдаёт `[]`, сборка скипается
- В build-контейнере: `pacman-key --init && pacman-key --populate archlinuxarm`, создаётся пользователь `builder`
- Сборка через `docker run -d ... sleep infinity` + `docker cp` внутрь/наружу — решает проблему видимости артефактов

## Конфигурация pacman на RPi5

```ini
[custom-repo]
SigLevel = Optional TrustedOnly
Server = https://dryamovvv.github.io/pkgs/aarch64
```

## Базовые команды

- `repo-add repo.db.tar.gz *.pkg.tar.zst` — создать/обновить базу репозитория
- `makepkg -s --noconfirm` — собрать пакет с установкой зависимостей
- `pacman -Sy` — синхронизировать репозитории на клиенте

## Добавление пакета

```bash
mkdir packages/<pkg-name>
# создать packages/<pkg-name>/PKGBUILD
git add packages/<pkg-name>
git commit -m "feat: add <pkg-name>"
git push
```

## CI настройки

Для деплоя необходимо включить GitHub Pages в режиме **GitHub Actions** (Settings → Pages → Source: GitHub Actions).
