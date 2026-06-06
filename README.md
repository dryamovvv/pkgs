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

| Флаг                          | Значение                                                       |
| ----------------------------- | -------------------------------------------------------------- |
| `-mcpu=cortex-a76+crypto`     | ARMv8.2-A + AES/SHA/PMULL; crc, lse, rdma, fp16, dotprod, rcpc |
| `-O2`                         | Стандартная оптимизация                                        |
| `-pipe`                       | Пайпы вместо временных файлов                                  |
| `-Wl,-z,max-page-size=0x4000` | 16K ELF-сегменты (размер страницы RPi5)                        |

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
```

Доп. компиляторы: Rust (`-C target-cpu=cortex-a76 -C opt-level=2`), Go (`GOARCH=arm64 GOARM64=v8.2`).

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
│   ├── build-package.sh   # Сборка в контейнере (ccache, makepkg)
│   ├── deploy-package.sh   # Деплой в gh-pages с retry
│   └── detect-changes.sh  # Детект изменённых пакетов
├── .github/workflows/
│   └── build.yml          # CI/CD: detect → build+deploy matrix
└── README.md
```

## CI

- **Кэши:** Docker image, pacman, ccache (по PKGBUILD hash), Cargo
- **Деплой:** git push в gh-pages с retry при конфликтах
- **Отладка:** tmate SSH через `workflow_dispatch` с `debug_enabled: true`
- **Таймаут:** 90 мин на сборку
