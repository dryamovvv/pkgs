# Arch Linux aarch64 Package Repository

<!-- Always use the superpowers skill for structured workflows -->
<!-- Use Context7 for documentation lookups -->
<!-- Use Exa for web search queries -->

## Architecture

Монорепозиторий пакетов Arch Linux aarch64, оптимизированный под Raspberry Pi 5 (Cortex-A76). Сборка — на нативных ARM64 GitHub-раннерах (`ubuntu-24.04-arm`), хостинг — удалённый сервер (`dryam.ru`).

Репозиторий: `github:dryamovvv/pkgs`
URL репозитория pacman: `http://pkgs.dryam.ru/aarch64`

## Структура

```
pkgs/
├── packages/              # Каждый пакет — поддиректория с PKGBUILD
│   ├── <pkg-name>/
│   │   └── PKGBUILD
│   └── ...
├── ci/
│   ├── build-package.sh      # Сборка в контейнере (pacman-key, ccache, makepkg)
│   ├── deploy-package.sh     # Деплой через SSH/SCP с flock-блокировкой
│   ├── detect-changes.sh     # Детект изменённых пакетов
│   ├── compute-build-hash.sh # Детерминированный хэш сборки (PKGBUILD + sources + CI)
│   ├── run-compute-hash.sh   # Обёртка с fallback и санитизацией для cache keys
│   └── auto-add-sha256sums.sh # Автообновление sha256sums в PKGBUILD'ах
├── .github/workflows/
│   ├── build.yml             # CI: detect → build matrix + deploy
│   └── auto-add-shasums.yml  # Автоматическое обновление sha256sums (workflow_dispatch)
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
   - Вычисление детерминированного build-hash (`ci/compute-build-hash.sh`):
     PKGBUILD + sha256sums + локальные source-файлы + `ci/build-package.sh`
   - Кэш built-artifact: `build-artifact-{pkg}-{hash}` — пропускает сборку при cache-hit
   - Кэши: Docker image, pacman, ccache (по build-hash), Cargo (по build-hash)
   - Кэш-директории создаются заранее, чтобы избежать warning'ов при cache-hit
   - В built-cache попадают только `.pkg.tar.*` / `.sig` файлы (не вся `src/` / `pkg/`)
   - Сборка `makepkg -s --noconfirm` с RPi5 CFLAGS/CXXFLAGS/LDFLAGS + ccache
3. **deploy** — отдельная job на `ubuntu-24.04-arm`:
   - Скачивает все артефакты, деплоит через Docker-контейнер
   - `ci/deploy-package.sh`: SCP + flock атомарный деплой с retry-loop (30 попыток)

Особенности:

- `detect-changes.sh` обрабатывает первый коммит (HEAD~1 не существует) — собирает все пакеты
- При изменении `ci/` или `.github/workflows/` — пересборка всех пакетов
- Если изменений в `packages/` нет — `detect` выдаёт `[]`, сборка скипается
- `concurrency: deploy-${{ github.ref }}` — сериализует деплой, но не отменяет
- `fail-fast: false` — один упавший пакет не отменяет остальные
- tmate-отладка через `workflow_dispatch` с `debug_enabled: true`
- `force_rebuild_all` (workflow_dispatch) — принудительная пересборка всех пакетов с инвалидацией кэша
- Деплой через SCP + flock на удалённый сервер с детекцией конфликтов

### Build Hash (compute-build-hash.sh)

Детерминированный хэш для инвалидации кэша. Включает:
- Содержимое PKGBUILD
- Source-файлы и их URL'ы (из массива `source=()`)
- Локальные source-файлы (sha256sum)
- SHA256-суммы (из массива `sha256sums=()`)
- Все файлы в директории пакета (sha256sum, алфавитный порядок)
- `ci/build-package.sh` (изменения скрипта сборки инвалидируют кэш)

При `force_rebuild_all` в хэш добавляется timestamp → гарантированный cache-miss.

## deploy-package.sh

Retry-based (30 попыток) деплой внутри arch-контейнера:

1. SCP пакета в staging-директорию на роутере
2. Скачивает текущую базу repo.db с роутера (под flock)
3. `repo-add -R` локально в контейнере (Arch имеет pacman)
4. Генерирует index.html с HTML-эскейпингом
5. SCP обновлённой базы + index.html в staging
6. `flock` + md5sum-detection: атомарный mv в repo-директорию
7. При конфликте (другой job изменил базу) — sleep 3s + retry

## Конфигурация pacman на RPi5

```ini
[custom-repo]
SigLevel = Required TrustedOnly
Server = http://pkgs.dryam.ru/aarch64
```

Импорт ключа подписи:

```bash
sudo pacman-key --recv-keys 0F98FE406BB366EB10AFAD8D90B35929BB827D35
#или из файла:
sudo pacman-key --add keys/pgp/BB827D35.asc
sudo pacman-key --lsign-key 0F98FE406BB366EB10AFAD8D90B35929BB827D35
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

Деплой на удалённый сервер: роутер Keenetic (`dryam.ru:222`), файлы на `/dev/sda1`, веб-сервер lighttpd на порту 80.

### GPG подпись

Все пакеты и repo.db подписываются RSA-4096 ключом (`pkgs.dryam.ru Repo Signing Key <repo@dryam.ru>`, fingerprint `0F98FE406BB366EB10AFAD8D90B35929BB827D35`).

GitHub Secrets/Variables:
- `GPG_PRIVATE_KEY` — ASCII-armored private key (secret)
- `GPG_PASSPHRASE` — passphrase для ключа (secret)
- `GPG_KEY_ID` — fingerprint ключа (secret: `0F98FE406BB366EB10AFAD8D90B35929BB827D35`)

## Пакеты

| Пакет         | Описание                                               | Версия  |
| ------------- | ------------------------------------------------------ | ------- |
| arch-opsd     | systemd service manager                                | latest  |
| atuin         | Shell history with sync                                | latest  |
| bat           | cat(1) clone with wings                                | 0.26.1  |
| delta         | Syntax-highlighting pager for git                      | 0.19.2  |
| dust          | More intuitive version of du                           | 1.2.4   |
| dysk          | ls-like command for disks                              | 3.6.1   |
| erd           | Modern filesystem and disk-usage utility               | 3.1.2   |
| eza           | Modern maintained replacement for ls                   | 0.23.4  |
| fd            | Simple, fast alternative to find                       | 10.4.2  |
| grex          | Command-line tool for generating regex                 | 1.4.6   |
| helix         | Modal terminal-based text editor                       | latest  |
| hyperfine     | Command-line benchmarking tool                         | 1.20.0  |
| just          | Command runner                                         | 1.51.0  |
| just-lsp      | Language server for just                               | 0.4.5   |
| kmscon        | KMS/DRM-based virtual console                          | latest  |
| linux-rpi-16k | Raspberry Pi 5 kernel (16K pages, RPi Foundation fork) | 6.18.34 |
| marksman      | Markdown LSP server                                    | latest  |
| mdv           | Browser-quality Markdown viewer for terminal           | 0.1.1   |
| mozillavpn    | Fast, secure VPN by Mozilla                            | latest  |
| procs         | Modern replacement for ps                              | 0.14.11 |
| ripgrep       | Fast grep replacement (binary: rg)                     | 15.1.0  |
| starship      | Minimal, blazing-fast prompt for any shell             | 1.25.1  |
| taplo         | TOML toolkit                                           | 0.10.0  |
| zellij        | Terminal workspace with batteries included             | 0.44.3  |
| zoxide        | Smarter cd command                                     | 0.9.9   |
