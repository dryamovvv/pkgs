---
name: add-package
description: Use when adding a new package to the Arch Linux aarch64 repository. Triggers: "add package", "new package", "add XYZ to repo", "create PKGBUILD", "собери пакет", "добавь пакет", "новый пакет".
---

# Add Package to Arch Linux aarch64 Repository

Interactive workflow for adding a new package to the `github:dryamovvv/pkgs` monorepo.
Target: Raspberry Pi 5 (Cortex-A76, ARMv8.2-A, aarch64).

## Steps

### 1. Research the package

Find upstream — GitHub, GitLab, official site. Determine:

- Latest stable version (tag/release)
- Build system (meson, cmake, autotools, cargo, Makefile)
- Available build options (`meson_options.txt`, `CMakeLists.txt`, `configure --help`, README)
- Dependencies (build-time and runtime)
- Whether the release tarball includes submodules — if not, use git-based source

**Then look up build configuration on Context7** for maximum coverage:

1. Resolve the library ID: `context7_resolve-library-id` with the package name and "build configuration options dependencies"
2. Query docs: `context7_query-docs` with the resolved ID and a query like "meson options CMake build configuration optional features dependencies"
3. Use findings to:
   - Discover **all** optional features the package supports (not just what README mentions)
   - Find exact **CMake/meson option names and types** (boolean vs feature, ON/OFF vs enabled/disabled)
   - Identify **dependency names** as they appear in the build system
   - Catch **version-specific** differences (e.g., options renamed between releases)
4. Combine Context7 findings with GitHub source inspection to build the complete feature list for Step 2

This ensures the user can configure every available option, not just the obvious ones.

### 2. Present options to the user

For EACH optional feature of the package:

- Explain what the feature does (one sentence)
- List additional dependencies it pulls in
- Ask: enable or disable

Use the `question` tool for interactive selection. Never decide for the user.

**Hard rules (do not ask):**

- **Documentation** (man pages, HTML docs) — **always `enabled`**. Add required makedepends (`libxslt`, `docbook-xsl`, `doxygen`, etc.).
- **Tests** — **always `disabled`** (CI time saving).
- **Debug symbols** — **always stripped** (`options=('!debug')` in PKGBUILD). Saves ~30-50% package size.
- **Platform-specific/exotic features** (e.g., `video_drm3d` for kmscon) — disable with explanation, do not ask.

### 3. Create PKGBUILD

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
license=('<spdx-id>')
options=('!debug')
depends=(
  '<runtime-dep1>'
  ...
)
makedepends=(
  '<build-dep1>'
  ...
)
optdepends=(
  '<opt-feature>: <brief description>'
)
provides=("<name>")
conflicts=("<name>")
backup=(
  'etc/<pkg>/<config-file>'
)
source=(
  "<tarball-url>"
  "<local-file>"
  ...
)
sha256sums=(
  '<sha256>'
  'SKIP'
  ...
)

prepare() {
  cd "$srcdir/$pkgname-$pkgver"
  # Apply patches
  patch -Np1 -i "$srcdir/<patch-file>"
  # Extra setup (e.g., pip install, cargo fetch, git submodule init)
}

build() {
  cd "$srcdir/$pkgname-$pkgver"
  export CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
  export CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
  export LDFLAGS="-Wl,-z,max-page-size=0x4000"
  <build-commands>
}

check() {
  cd "$srcdir/$pkgname-$pkgver"
  <test-command> || true
}

package() {
  cd "$srcdir/$pkgname-$pkgver"
  DESTDIR="$pkgdir" <install-command>

  # Install local config files
  install -Dm644 "$srcdir/<config>" "$pkgdir/etc/<pkg>/<config>"

  # Install systemd services, polkit rules, etc.
  install -Dm644 "$srcdir/<service>" "$pkgdir/usr/lib/systemd/system/<service>"
}
```

**PKGBUILD rules:**

- `sha256sums`: download source, compute `sha256sum`, insert real hashes. Local files → `'SKIP'`.
- `check()` always with `|| true` — tests must not block the build.
- `depends` — runtime deps. `makedepends` — build-only deps.
- `backup=()` — list config files under `/etc/` that should not be overwritten on upgrade.
- `options=('!debug')` — strip debug symbols (saves space; add `'debug'` if the user explicitly wants them).
- `buildtype=release` for meson. `-DCMAKE_BUILD_TYPE=Release` for cmake.

### Git-based sources (when tarball lacks submodules)

Some projects (e.g., MozillaVPN) require git submodules not included in release tarballs.
Use `git+https://` source and clone in `prepare()`:

```bash
source=("git+https://github.com/<org>/<repo>#tag=v$pkgver")
sha256sums=('SKIP')

prepare() {
  cd "$srcdir"
  cp -r "$pkgname" "$pkgname-$pkgver"
  cd "$pkgname-$pkgver"
  git submodule update --init --recursive
  # ... extra setup
}
```

### `.install` file (post-install hooks)

Create `packages/<pkg>/<pkg>.install` when the package needs post-install actions:

```bash
post_install() {
  setcap cap_net_admin+eip usr/bin/<binary>
  systemd-sysusers
}

post_upgrade() {
  post_install
}

pre_remove() {
  # cleanup before removal
}
```

### RPi5 Cortex-A76 optimization (all compilers)

**Mandatory** for ALL code in ALL languages:

````
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"

``

| Флаг                           | Значение                                                                                             |
| ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `-mcpu=cortex-a76+crypto`      | ARMv8.2-A + AES/SHA/PMULL; includes crc, lse, rdma, fp16, dotprod, rcpc                              |
| `-O2`                          | Standard optimization (enables `-fomit-frame-pointer` on AArch64)                                    |
| `-pipe`                        | Pipes instead of temporary files                                                                    |
| `-Wl,-z,max-page-size=0x4000`  | 16K ELF segment alignment — ARM64 page size on RPi5                                                  |

- **Rust:** `RUSTFLAGS="-C target-cpu=cortex-a76 -C opt-level=2"`
- **Go:** `GOFLAGS="-ldflags=-extldflags=-Wl,-z,max-page-size=0x4000" GOARCH=arm64 GOARM64=v8.2`
- `-mtune` is redundant (GCC derives it from `-mcpu`)

### Common pitfalls

| Pitfall                                            | Fix                                                                                                                           |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Meson boolean option given feature value           | Use `-Doption=true` / `-Doption=false`, not `enabled`/`disabled` (check if type is `boolean` or `feature` in `meson.options`) |
| Meson feature option given boolean                 | Use `-Doption=enabled` / `-Doption=disabled` / `-Doption=auto`                                                                |
| CMake `-DBUILD_SHARED_LIBS=ON` type mismatch       | Check CMakeLists.txt for `option()` vs `set()` — `option()` expects `ON`/`OFF`, `set()` may expect other types                |
| Unknown meson option                               | Meson errors on unknown options since 0.60.0 — verify option exists in `meson_options.txt` or `meson.options`                 |
| Missing `cd "$srcdir/$pkgname-$pkgver"` in build() | Some source archives extract to different names — verify with `ls "$srcdir"`                                                  |
| Package built as `.xz` but expected `.zst`         | CI glob uses `*.pkg.tar.*` to match both                                                                                      |
| Git source: `$pkgname` dir name mismatch           | Git clones into `$pkgname` (bare name), not `$pkgname-$pkgver` — use `cp -r` in `prepare()`                                   |

### 4. Create per-package documentation

Generate `packages/<pkg-name>/AGENTS.md` (for the agent — build specifics, chosen features, flag rationale):

```markdown
# <pkg-name>

| Attribute | Value |
|-----------|-------|
| Version | `<version>` |
| Build system | `<build-system>` |
| Features | `<enabled-features>` |

## RPi5 flags

```
CFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
CXXFLAGS="-mcpu=cortex-a76+crypto -O2 -pipe"
LDFLAGS="-Wl,-z,max-page-size=0x4000"
<language-specific-flags>
```

## Notes

<gotchas, quirks, why certain opts were chosen>
```

Generate `packages/<pkg-name>/README.md` (for humans — package summary, build instructions):

```markdown
# <pkg-name>

<pkgdesc>

## Building

```bash
makepkg -s
```

## Dependencies

<runtime-deps-summary>

## Features

| Feature | Enabled | Description |
|---------|---------|-------------|
| <name>  | yes/no  | <what it does> |
```

### 5. Create directory and commit

```bash
mkdir packages/<pkg-name>
# create packages/<pkg-name>/PKGBUILD
# create packages/<pkg-name>/AGENTS.md
# create packages/<pkg-name>/README.md
# add local files if needed (configs, patches, .install)
git add packages/<pkg-name>
git commit -m "feat: add <pkg-name> <version>"
git push
```

### 6. Update root AGENTS.md and README.md

Add the new package to the package registry in both root `AGENTS.md` and `README.md` at the `## Packages` section. Always keep the list sorted alphabetically.

Format: `| <pkg-name> | <one-line description> | <version> |`

### 7. Monitor CI until full success

**Do not stop until the package is built and deployed.** After `git push`:

1. Watch progress: `gh run watch`
2. If build fails — read logs: `gh run view <run-id> --log --job=<job-id>`
3. Fix the error in PKGBUILD/patches, commit `fix: ...`, push
5. Go back to step 1
5. Stop only when all three jobs (`detect`, `build`, `deploy`) are **success**

**Success checklist:**

- [ ] `detect` — success
- [ ] `build (<pkg-name>)` — success
- [ ] `deploy` — success
- [ ] `https://dryamovvv.github.io/pkgs/aarch64/repo.db` — HTTP 200
- [ ] Package appears in deploy log under `./aarch64/`
- [ ] `https://dryamovvv.github.io/pkgs/aarch64/<pkg>-<ver>-aarch64.pkg.tar.*` — HTTP 200

## Example

User: "add yazi"

Response: research yazi → find its build options → ask user about each → create PKGBUILD + per-package AGENTS.md/README.md → update root AGENTS.md and README.md → commit → push → monitor CI until deployed.
````
