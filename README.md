# Arch Linux aarch64 Package Repository

Монорепозиторий пакетов Arch Linux, оптимизированных под **Raspberry Pi 5** (Cortex-A76, ARMv8.2-A).

Сборка — на нативных ARM64 GitHub-раннерах (`ubuntu-24.04-arm`), хостинг — GitHub Pages.

## Подключение репозитория на RPi5

```ini
# /etc/pacman.conf — добавьте в конец:
[custom-repo]
SigLevel = Optional TrustedOnly
Server = https://dryamovvv.github.io/pkgs/aarch64
```

```bash
sudo pacman -Sy
```

## Флаги оптимизации

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
```

- `-mcpu=cortex-a76` — включает armv8.2-a, crc, lse, rdma, fp16, dotprod, rcpc, fp+simd
- `+crypto` — AES, SHA1/SHA2, PMULL
- `-mtune` избыточен (GCC выводит из `-mcpu`)

## Добавление пакета

```bash
mkdir -p packages/<pkg-name>
# создайте packages/<pkg-name>/PKGBUILD
git add packages/<pkg-name>
git commit -m "feat: add <pkg-name>"
git push
```

CI автоматически соберёт и задеплоит пакет.

## Структура

```
pkgs/
├── packages/              # PKGBUILD'ы пакетов
│   ├── <pkg-name>/
│   │   └── PKGBUILD
│   └── ...
├── ci/
│   ├── build-package.sh   # Обёртка сборки в контейнере
│   └── detect-changes.sh  # Детект изменённых пакетов
├── .github/workflows/
│   └── build.yml          # CI/CD: сборка + деплой
└── README.md
```

## Требования

- GitHub Pages включён в режиме **GitHub Actions**
- Нативный ARM64-раннер (`ubuntu-24.04-arm`)
