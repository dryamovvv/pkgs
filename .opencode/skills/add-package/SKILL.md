---
name: add-package
description: Use when adding a new package to the Arch Linux aarch64 repository. Triggers: "add package", "new package", "add XYZ to repo", "create PKGBUILD", "собери пакет", "добавь пакет", "новый пакет".
---

# Add Package to Arch Linux aarch64 Repository

Интерактивный workflow добавления нового пакета в монорепозиторий `github:dryamovvv/pkgs`.

## Шаги

### 1. Изучить пакет

Найти upstream пакет — GitHub, GitLab, официальный сайт. Определить:

- Последнюю стабильную версию (тег/релиз)
- Систему сборки (meson, cmake, autotools, Makefile)
- Доступные опции сборки (`meson_options.txt`, `CMakeLists.txt`, `configure --help`, README)
- Зависимости (build-time и runtime)

### 2. Перечислить опции пользователю

Для КАЖДОЙ опциональной фичи пакета:

- Объяснить, что фича даёт (одно предложение)
- Перечислить дополнительные зависимости, которые она тянет
- Спросить: включить или нет

Использовать `question` tool для интерактивного выбора. Не принимать решения за пользователя.

**Важно:**

- Документация (man pages, HTML docs) — **всегда `enabled`**, не спрашивать. Если нужны доп. makedepends (`libxslt`, `docbook-xsl`, `doxygen` и т.д.) — добавить в `makedepends=()`.
- Тесты — **всегда `disabled`** (экономия времени сборки в CI), не спрашивать.
- Экзотические/платформозависимые фичи (например, video_drm3d для kmscon) — отключать с объяснением, не спрашивать.

### 3. Создать PKGBUILD

Формат:

```bash
# Maintainer: dryamovvv <dryamovvv@users.noreply.github.com>
# Contributor: dryamovvv (Arch Linux package)
# Optimized for Raspberry Pi 5 (Cortex-A76)
pkgname=<name>
pkgver=<version>
pkgrel=1
pkgdesc="<one-liner> optimized for Raspberry Pi 5 (Cortex-A76)"
arch=('aarch64')
url="<upstream>"
license=('<license>')
depends=(
  '<dep1>'
  ...
)
makedepends=(
  '<build-dep1>'
  ...
)
provides=("<name>")
conflicts=("<name>")
source=("<url>::<tarball>" ...)
sha256sums=('<sha256>' ...)

build() {
  cd "$srcdir/$pkgname-$pkgver"
  CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe" \
  CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe" \
  <build-commands>
}

check() {
  cd "$srcdir/$pkgname-$pkgver"
  <test-command> || true
}

package() {
  cd "$srcdir/$pkgname-$pkgver"
  DESTDIR="$pkgdir" <install-command>
}
```

Правила:

- `sha256sums`: скачать source, вычислить `sha256sum`, вставить реальные хеши. Для локальных файлов (конфиги) — `'SKIP'`.
- `check()` всегда с `|| true` — тесты не должны блокировать сборку.
- `depends` — runtime-зависимости, `makedepends` — только для сборки.
- `buildtype=release` для meson, `--with-release` или аналоги для других.

### RPi5 Cortex-A76 оптимизация для всех компиляторов

**Обязательно** для любого кода на любом языке (C, C++, Rust через `RUSTFLAGS`, Go через `GOFLAGS`, ассемблер и т.д.):

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x10000"
```

| Флаг                           | Значение                                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `-mcpu=cortex-a76+crypto`      | ARMv8.2-A + AES/SHA/PMULL; включает crc, lse, rdma, fp16, dotprod, rcpc                                       |
| `-O2`                          | Стандартная оптимизация (включает `-fomit-frame-pointer` на AArch64)                                          |
| `-pipe`                        | Передача через пайпы вместо временных файлов                                                                  |
| `-Wl,-z,max-page-size=0x10000` | Выравнивание ELF-сегментов на 64K — гарантирует совместимость со всеми размерами страниц ARM64 (4K, 16K, 64K) |

- **Rust:** `RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"`
- **Go:** `GOFLAGS="-ldflags=-extldflags=-Wl,-z,max-page-size=0x10000"` + `GOARCH=arm64 GOARM64=v8.2`
- `-mtune` не нужен (GCC выводит из `-mcpu`)

### 4. Создать директорию и закоммитить

```bash
mkdir packages/<pkg-name>
# создать packages/<pkg-name>/PKGBUILD
# добавить локальные файлы если нужны (конфиги, патчи)
git add packages/<pkg-name>
git commit -m "feat: add <pkg-name> <version>"
git push
```

### 5. Проверить CI до полного успеха

**Не останавливаться, пока пакет не собран и не задеплоен.** После `git push`:

1. Запустить наблюдение: `gh run watch` (следит в реальном времени)
2. Если сборка упала — прочитать логи: `gh run view <run-id> --log --job=<job-id>`
3. Исправить ошибку в PKGBUILD/патчах, закоммитить `fix: ...`, запушить
4. Повторить с шага 1
5. Остановиться только когда все три job-а (`detect`, `build`, `deploy`) — **success**

**Чек-лист успешной сборки:**

- [ ] `detect` — success
- [ ] `build (<pkg-name>)` — success
- [ ] `deploy` — success
- [ ] `https://dryamovvv.github.io/pkgs/aarch64/repo.db` — HTTP 200
- [ ] Пакет появился в выводе `gh run view --log --job=<deploy-job-id>` в списке `./aarch64/`

## Пример

Пользователь: "добавь yazi"
Ответ: изучить yazi → найти опции сборки → спросить про каждую → создать PKGBUILD → закоммитить → проверить CI.
