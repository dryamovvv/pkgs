# Рефакторинг и исправление уязвимостей репозитория

> **Для агентов:** ТРЕБУЕМЫЙ СУБ-НАВЫК: Используйте `subagent-driven-development` или `executing-plans` для реализации этого плана шаг за шагом. Шаги используют синтаксис чекбоксов (`- [ ]`) для отслеживания прогресса.

**Цель:** Провести безопасный рефакторинг с целью устранения критической уязвимости деплоя цифровых подписей, ускорения компиляции пакетов в CI/CD через многопоточность, повышения надежности кэш-хэширования и изоляции сборочного окружения Python.

**Архитектура:** Изменения вносятся локально в сборочные скрипты `ci/deploy-package.sh`, `ci/build-package.sh`, `ci/compute-build-hash.sh` и сборочный шаблон `packages/mozillavpn/PKGBUILD`. Все изменения проверяются синтаксически и логически локальными тестами.

**Стек технологий:** Bash, Pacman/Makepkg, Python Virtualenv, Git, Docker, GnuPG.

---

### Задача 1: Исправление деплоя цифровых подписей пакетов (`.sig`)

**Файлы:**

- Изменить: `/home/dryam/Repositories/pkgs/ci/deploy-package.sh`

- [x] **Шаг 1.1: Изменить сбор пакетов в `ci/deploy-package.sh`**

Копировать `.sig` файлы вместе с самими пакетами, но пропускать их добавление в массив `NEW_PKGS` (так как утилита `repo-add` не принимает `.sig` файлы в качестве аргументов).

Код для изменения в `/home/dryam/Repositories/pkgs/ci/deploy-package.sh` (строки 46-59):

```bash
# ── Gather new packages ──
echo "=== Gathering new packages ==="
NEW_PKGS=()
for pkgdir in /workspace/packages/*/; do
	[ -d "$pkgdir" ] || continue
	for f in "$pkgdir"/*.pkg.tar.*; do
		[ -f "$f" ] || continue
		basename="${f##*/}"
		if [[ "$basename" == *.sig ]]; then
			cp "$f" "$WORKDIR/"
			continue
		fi
		cp "$f" "$WORKDIR/"
		NEW_PKGS+=("$WORKDIR/$basename")
	done
done
```text

- [x] **Шаг 1.2: Проверить синтаксис скрипта**

Запустить: `bash -n /home/dryam/Repositories/pkgs/ci/deploy-package.sh`
Ожидаемый результат: код выхода `0` (нет синтаксических ошибок).

- [x] **Шаг 1.3: Создать Git-коммит**

Запустить:

```bash
git add /home/dryam/Repositories/pkgs/ci/deploy-package.sh
git commit -m "fix(ci): fix package signatures deployment bug"
```text

---

### Задача 2: Включение многопоточности сборки (`MAKEFLAGS`)

**Файлы:**

- Изменить: `/home/dryam/Repositories/pkgs/ci/build-package.sh`

- [x] **Шаг 2.1: Добавить настройку `MAKEFLAGS` в `/etc/makepkg.conf`**

Добавить экспорт `MAKEFLAGS="-j$(nproc)"` в генерируемый `/etc/makepkg.conf` для задействования всех ядер процессора на хостах GitHub Actions.

Код для изменения в `/home/dryam/Repositories/pkgs/ci/build-package.sh` (строки 27-35):

```bash
# Set up RPi5-optimized makepkg.conf (Cortex-A76, 16K-page ELF alignment)
cat >>/etc/makepkg.conf <<'EOF'

# Cortex-A76 optimizations for Raspberry Pi 5
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
MAKEFLAGS="-j$(nproc)"
# -fomit-frame-pointer is default on AArch64 at -O2
EOF
```text

- [x] **Шаг 2.2: Проверить синтаксис скрипта**

Запустить: `bash -n /home/dryam/Repositories/pkgs/ci/build-package.sh`
Ожидаемый результат: код выхода `0` (нет синтаксических ошибок).

- [x] **Шаг 2.3: Создать Git-коммит**

Запустить:

```bash
git add /home/dryam/Repositories/pkgs/ci/build-package.sh
git commit -m "perf(ci): enable multithreaded compilation with MAKEFLAGS"
```text

---

### Задача 3: Надежное извлечение списков исходников и сумм в `compute-build-hash.sh`

**Файлы:**

- Изменить: `/home/dryam/Repositories/pkgs/ci/compute-build-hash.sh`

- [x] **Шаг 3.1: Заменить регулярные выражения AWK на безопасный импорт в подоболочке bash**

Использовать нативное и безопасное выполнение `source PKGBUILD` внутри изолированной подоболочки `bash -c`, что гарантирует 100% корректную обработку однострочных, многострочных массивов и комментариев.

Код для изменения в `/home/dryam/Repositories/pkgs/ci/compute-build-hash.sh` (строки 31-33):

```bash
# Extract source and sha256sums blocks via safe, robust evaluation in an isolated bash subshell
bash -c 'source PKGBUILD >/dev/null 2>&1; for s in "${source[@]}"; do printf "%s\n" "$s"; done' >/tmp/ci_sources_$$.txt 2>/dev/null || true
bash -c 'source PKGBUILD >/dev/null 2>&1; for s in "${sha256sums[@]}"; do printf "%s\n" "$s"; done' >/tmp/ci_sums_$$.txt 2>/dev/null || true
```text

- [x] **Шаг 3.2: Проверить синтаксис скрипта**

Запустить: `bash -n /home/dryam/Repositories/pkgs/ci/compute-build-hash.sh`
Ожидаемый результат: код выхода `0` (нет синтаксических ошибок).

- [x] **Шаг 3.3: Проверить работу скрипта вычисления хэша на реальном пакете**

Запустить вычисление хэша для пакета `ripgrep`:

```bash
/home/dryam/Repositories/pkgs/ci/compute-build-hash.sh /home/dryam/Repositories/pkgs/packages/ripgrep
```text

Ожидаемый результат: Успешный вывод SHA256 хэша (строка из 64 символов).

- [x] **Шаг 3.4: Создать Git-коммит**

Запустить:

```bash
git add /home/dryam/Repositories/pkgs/ci/compute-build-hash.sh
git commit -m "refactor(ci): use robust bash evaluation for build hash computation"
```text

---

### Задача 4: Изоляция зависимостей Python в пакете `mozillavpn`

**Файлы:**

- Изменить: `/home/dryam/Repositories/pkgs/packages/mozillavpn/PKGBUILD`

- [x] **Шаг 4.1: Изменить `prepare()` в `mozillavpn/PKGBUILD` для создания venv**

Заменить небезопасный глобальный запуск `pip install --break-system-packages` на локальное изолированное виртуальное окружение `python -m venv` и установить `glean_parser` туда, после чего добавить окружение в `$PATH`.

Код для изменения в `/home/dryam/Repositories/pkgs/packages/mozillavpn/PKGBUILD` (строки 51-63):

```bash
prepare() {
  cd "$srcdir"
  git clone --depth=1 --branch "v$pkgver" "https://github.com/mozilla-mobile/mozilla-vpn-client.git" "$pkgname-$pkgver"
  cd "$pkgname-$pkgver"
  git -c protocol.file.allow=always submodule update --init --depth=1 -j4 2>&1 || \
    git -c protocol.file.allow=always submodule update --init -j4 || true
  rm -rf 3rdparty/wireguard-apple 3rdparty/wireguard-go
  sed -i '/wireguard-apple/d;/wireguard-go/d' .gitmodules 2>/dev/null || true
  cargo fetch --locked --target "$(rustc -vV | sed -n 's/host: //p')"
  cd "$srcdir/$pkgname-$pkgver"
  patch -p1 < "$srcdir/0002-go-nil-check-cgroups.patch"

  # Создание изолированного Python virtualenv для компилятора glean_parser
  python -m venv "$srcdir/python-venv"
  "$srcdir/python-venv/bin/pip" install --upgrade pip
  "$srcdir/python-venv/bin/pip" install glean_parser
  export PATH="$srcdir/python-venv/bin:$PATH"
}
```text

- [x] **Шаг 4.2: Экспортировать виртуальное окружение в `build()` в `mozillavpn/PKGBUILD`**

Убедиться, что `glean_parser` виден при выполнении `cmake --build`:

```bash
build() {
  cd "$srcdir/$pkgname-$pkgver"
  export PATH="$srcdir/python-venv/bin:$PATH"
  export CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
  export CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe -Wno-error=unused-result"
  export LDFLAGS="-Wl,-z,max-page-size=0x4000"
  cmake -B build -S . -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_TESTING=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_CRASHREPORTING=OFF \
    -Wno-dev
  cmake --build build
}
```text

- [x] **Шаг 4.3: Проверить синтаксис `PKGBUILD`**

Запустить: `bash -n /home/dryam/Repositories/pkgs/packages/mozillavpn/PKGBUILD`
Ожидаемый результат: код выхода `0` (нет синтаксических ошибок).

- [x] **Шаг 4.4: Создать Git-коммит**

Запустить:

```bash
git add /home/dryam/Repositories/pkgs/packages/mozillavpn/PKGBUILD
git commit -m "refactor(mozillavpn): isolate glean_parser build tool inside python venv"
```text
