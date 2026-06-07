# Arch Linux aarch64 Package Repository

<!-- Always use the superpowers skill for structured workflows -->
<!-- Use Context7 for documentation lookups -->
<!-- Use Exa for web search queries -->

## Architecture

Монорепозиторий пакетов Arch Linux aarch64, оптимизированный под Raspberry Pi 5 (Cortex-A76). Сборка — на нативных ARM64 GitHub-раннерах (`ubuntu-24.04-arm`), хостинг — GitHub Pages (gh-pages branch).

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
│   ├── build-package.sh   # Сборка в контейнере (pacman-key, ccache, makepkg)
│   ├── deploy-package.sh   # Деплой в gh-pages с retry-based push
│   └── detect-changes.sh  # Детект изменённых пакетов
├── .github/workflows/
│   └── build.yml          # CI: detect → build matrix + deploy
├── .opencode/skills/
│   └── add-package/SKILL.md  # Интерактивный навык добавления пакетов
├── .gitignore
├── AGENTS.md
└── README.md
```

## RPi5 оптимизация

CPU Cortex-A76, ARMv8.2-A. В makepkg.conf (внутри контейнера):

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
```

| Флаг                          | Значение                                                                |
| ----------------------------- | ----------------------------------------------------------------------- |
| `-mcpu=cortex-a76+crypto`     | ARMv8.2-A + AES/SHA/PMULL; включает crc, lse, rdma, fp16, dotprod, rcpc |
| `-O2`                         | Стандартная оптимизация (включает `-fomit-frame-pointer` на AArch64)    |
| `-pipe`                       | Передача через пайпы вместо временных файлов                            |
| `-Wl,-z,max-page-size=0x4000` | Выравнивание ELF-сегментов на 16K — размер страницы RPi5                |

Доп. компиляторы:

- **Rust:** `RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"`
- **Go:** `GOFLAGS="-ldflags=-extldflags=-Wl,-z,max-page-size=0x4000" GOARCH=arm64 GOARM64=v8.2`

## Workflow (build.yml)

1. **detect** — `git diff --name-only HEAD~1 -- packages/`, формирует matrix пакетов (на ubuntu-latest)
2. **build** — matrix job на `ubuntu-24.04-arm`:
   - Docker `lfdevs/archlinuxarm:base-devel` + `docker cp` (артефакты видны на хосте)
   - Кэши: Docker image, pacman, ccache (по PKGBUILD hash), Cargo (по PKGBUILD hash)
   - Сборка `makepkg -s --noconfirm` с RPi5 CFLAGS/CXXFLAGS/LDFLAGS + ccache
   - Деплой: `deploy-package.sh` внутри контейнера → git push в gh-pages с retry-loop

Особенности:

- `detect-changes.sh` обрабатывает первый коммит (HEAD~1 не существует) — собирает все пакеты
- При изменении `ci/` или `.github/workflows/` — пересборка всех пакетов
- Если изменений в `packages/` нет — `detect` выдаёт `[]`, сборка скипается
- `concurrency: deploy-${{ github.ref }}` — сериализует деплой, но не отменяет
- `fail-fast: false` — один упавший пакет не отменяет остальные
- tmate-отладка через `workflow_dispatch` с `debug_enabled: true`
- Деплой через git push в gh-pages (не actions/deploy-pages)

## deploy-package.sh

Retry-based (10 попыток) деплой внутри arch-контейнера:

1. Настраивает git credential helper (GITHUB_TOKEN не светится в process args)
2. Клонирует gh-pages (или создаёт orphan branch если не существует)
3. Копирует пакет, `repo-add -R` для обновления базы
4. Генерирует index.html с HTML-эскейпингом
5. `git push origin gh-pages` — при конфликте (другой job задеплоил) sleep 3s + retry

## Конфигурация pacman на RPi5

```ini
[custom-repo]
SigLevel = Optional TrustedOnly
Server = https://dryamovvv.github.io/pkgs/aarch64
```

## Добавление пакета

При добавлении нового пакета:

1. **Изучить возможности пакета** — изучить документацию, `meson_options.txt`, `CMakeLists.txt`, `configure --help`. Использовать Context7 для поиска опций сборки.
2. **Интерактивно спросить пользователя** о каждой опциональной фиче — объяснить, что фича даёт, какие зависимости тянет, и спросить включать или нет. Не принимать решения за пользователя.
3. **Документация всегда включается** — man-страницы и документация (`-Ddocs=enabled`, `--enable-docs`) собираются по умолчанию. Доп. makedepends (`libxslt`, `docbook-xsl`, `doxygen`) добавляются автоматически.
4. **Тесты всегда отключаются** — `-Dtests=false`, `--disable-tests`, `BUILD_TESTS=OFF` для экономии времени CI.
5. **Создать PKGBUILD** с учётом выбранных опций, реальными SHA256 и RPi5 CFLAGS/CXXFLAGS/LDFLAGS.
6. **Наблюдать CI до полного успеха** — `gh run watch`, читать логи при ошибках, фиксить и пушить, пока detect + build + deploy все success.

## CI настройки

GitHub Pages: Source = **Deploy from a branch** → `gh-pages`. Не "GitHub Actions".

## Пакеты

| Пакет      | Описание                                     | Версия  |
| ---------- | -------------------------------------------- | ------- |
| arch-opsd  | systemd service manager                      | latest  |
| atuin      | Shell history with sync                      | latest  |
| bat        | cat(1) clone with wings                      | 0.26.1  |
| delta      | Syntax-highlighting pager for git            | 0.19.2  |
| dust       | More intuitive version of du                 | 1.2.4   |
| dysk       | ls-like command for disks                    | 3.6.1   |
| erd        | Modern filesystem and disk-usage utility     | 3.1.2   |
| eza        | Modern maintained replacement for ls         | 0.23.4  |
| fd         | Simple, fast alternative to find             | 10.4.2  |
| grex       | Command-line tool for generating regex       | 1.4.6   |
| helix      | Modal terminal-based text editor             | latest  |
| hyperfine  | Command-line benchmarking tool               | 1.20.0  |
| just       | Command runner                               | 1.51.0  |
| just-lsp   | Language server for just                     | 0.4.5   |
| kmscon     | KMS/DRM-based virtual console                | latest  |
| marksman   | Markdown LSP server                          | latest  |
| mdv        | Browser-quality Markdown viewer for terminal | 0.1.1   |
| mozillavpn | Fast, secure VPN by Mozilla                  | latest  |
| procs      | Modern replacement for ps                    | 0.14.11 |
| ripgrep    | Fast grep replacement (binary: rg)           | 15.1.0  |
| starship   | Minimal, blazing-fast prompt for any shell   | 1.25.1  |
| taplo      | TOML toolkit                                 | 0.10.0  |
| zellij     | Terminal workspace with batteries included   | 0.44.3  |
| zoxide     | Smarter cd command                           | 0.9.9   |
