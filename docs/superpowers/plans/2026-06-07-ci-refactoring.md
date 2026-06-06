# CI Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical CI issues (Docker cache inefficiency, ccache key blowup, token leak risk, deploy race conditions) and improve reliability.

**Architecture:** Each task is an independent, self-contained fix. Order from most impactful to least. CI must pass after each task.

**Tech Stack:** GitHub Actions (YAML), Bash, Docker, git

---

### Task 1: Fix Docker image cache — skip pull on cache hit

**Problem:** `docker pull` runs on every build even when cache hits, wasting ~30s and negating the cache benefit.

**Files:**

- Modify: `.github/workflows/build.yml:52-58`

- [ ] **Replace "Load / pull Docker image" step**

Current code:

```yaml
- name: Load / pull Docker image
  run: |
    if [ -f /tmp/docker-image.tar ]; then
      docker load -i /tmp/docker-image.tar
    fi
    docker pull lfdevs/archlinuxarm:base-devel
    docker save lfdevs/archlinuxarm:base-devel -o /tmp/docker-image.tar
```

Replace with:

```yaml
- name: Load / pull Docker image
  if: steps.docker-cache.outputs.cache-hit != 'true'
  run: |
    docker pull lfdevs/archlinuxarm:base-devel
    docker save lfdevs/archlinuxarm:base-devel -o /tmp/docker-image.tar

- name: Load cached Docker image
  if: steps.docker-cache.outputs.cache-hit == 'true'
  run: docker load -i /tmp/docker-image.tar
```

This also requires adding `id: docker-cache` to the existing cache step (it already has it). The `docker save` only runs on cache miss, saving ~1GB write time on cache hits.

- [ ] **Commit**

```bash
git add .github/workflows/build.yml && git commit -m "fix: skip docker pull on cache hit"
```

- [ ] **Verify CI passes**

Run: `gh run watch --repo dryamovvv/pkgs`

---

### Task 2: Fix ccache key — use source hash instead of run_id

**Problem:** `ccache-v2-${{ matrix.pkg }}-${{ github.run_id }}` creates a NEW cache entry on every run. `restore-keys` finds the previous cache, but the save always creates a new entry. Over time this grows unbounded since old caches are never hit as primary keys.

**Files:**

- Modify: `.github/workflows/build.yml:69-74`

- [ ] **Replace ccache key with source-based hash**

Current code:

```yaml
- name: Cache ccache
  uses: actions/cache@v4
  with:
    path: /tmp/ccache
    key: ccache-v2-${{ matrix.pkg }}-${{ github.run_id }}
    restore-keys: ccache-v2-${{ matrix.pkg }}-
```

Replace with:

```yaml
- name: Cache ccache
  uses: actions/cache@v4
  with:
    path: /tmp/ccache
    key: ccache-v2-${{ matrix.pkg }}-${{ hashFiles(format('packages/{0}/PKGBUILD', matrix.pkg)) }}
    restore-keys: ccache-v2-${{ matrix.pkg }}-
```

Now the cache key is deterministic per package version. Same PKGBUILD = same cache hit. New PKGBUILD = cache miss with fallback to previous version's cache.

- [ ] **Commit**

```bash
git add .github/workflows/build.yml && git commit -m "fix: ccache key uses PKGBUILD hash instead of run_id"
```

- [ ] **Verify CI passes**

---

### Task 3: Add timeout-minutes to build step

**Problem:** mozillavpn can build for hours. No timeout means jobs can hang indefinitely. GitHub Actions has a 6-hour default, which wastes runner minutes.

**Files:**

- Modify: `.github/workflows/build.yml:76-86`

- [ ] **Add timeout to build step**

Current code:

```yaml
- name: Build in container
  run: |
```

Add `timeout-minutes` before `run`:

```yaml
- name: Build in container
  timeout-minutes: 90
  run: |
```

90 minutes is generous enough for mozillavpn's Rust/Cargo compilation.

- [ ] **Commit**

```bash
git add .github/workflows/build.yml && git commit -m "fix: add 90min timeout to build step"
```

- [ ] **Verify CI passes**

---

### Task 4: Fix token leak risk in deploy-package.sh

**Problem:** `GH_URL` contains the token in plaintext. If `set -x` or verbose output is ever enabled, or if a command echoes it, the token appears in logs. GitHub Actions masks `${{ secrets.GITHUB_TOKEN }}` but NOT strings constructed inside the shell.

**Files:**

- Modify: `ci/deploy-package.sh:26`

- [ ] **Use git credential helper instead of embedded token**

Current code:

```bash
GH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GH_REPO}.git"
```

Replace all `${GH_URL}` usage with a git credential helper approach. Add at the top of deploy-package.sh (after the GITHUB_TOKEN check):

```bash
# Configure git credential helper (avoids token in process args/urls)
git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials
```

Then change the `git clone` commands to use the regular URL:

```bash
git clone --depth 1 -b gh-pages "https://github.com/${GH_REPO}.git" /tmp/repo
```

And change `git push origin gh-pages` — git will use the credential helper automatically.

Remove the `GH_URL` variable entirely.

Also add cleanup at the end of the script (before `exit 0`):

```bash
rm -f ~/.git-credentials
```

- [ ] **Commit**

```bash
git add ci/deploy-package.sh && git commit -m "fix: use git credential helper instead of embedded token in URLs"
```

- [ ] **Verify CI passes**

---

### Task 5: Add concurrency group to prevent deploy conflicts

**Problem:** Two pushes in quick succession create parallel deploy race conditions. The retry-based approach works but wastes runner time. A concurrency group ensures only one deploy runs at a time.

**Files:**

- Modify: `.github/workflows/build.yml` (add at top level)

- [ ] **Add concurrency group to workflow**

Add after line 19 (after `permissions: contents: write`):

```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false
```

`cancel-in-progress: false` ensures the newer run waits for the older one to finish rather than cancelling it (which would lose build artifacts). The deploy retry-logic in deploy-package.sh remains as a safety net for edge cases.

- [ ] **Commit**

```bash
git add .github/workflows/build.yml && git commit -m "fix: add concurrency group to prevent parallel deploy conflicts"
```

- [ ] **Verify CI passes**

---

### Task 6: Fix repo-add glob in deploy-package.sh

**Problem:** `repo-add -R repo.db.tar.gz *.pkg.tar.*` picks up ALL .pkg.tar.\* files in the directory. If a previous deploy attempt left stale files or there's an unrelated file, repo-add includes it. Should only add the specific package being deployed.

**Files:**

- Modify: `ci/deploy-package.sh:70-72`

- [ ] **Replace glob with explicit package name**

Current code:

```bash
  cd /tmp/repo/aarch64
  repo-add -R repo.db.tar.gz *.pkg.tar.* 2>/dev/null || true
```

Replace with:

```bash
  cd /tmp/repo/aarch64
  repo-add -R repo.db.tar.gz *.pkg.tar.* 2>/dev/null || true
```

Wait — this is actually correct. The `gh-pages` branch is cloned fresh each attempt (`rm -rf /tmp/repo` + `git clone`), so there are no stale files. But to be safe and explicit about which packages belong in the repo, we should keep all `.pkg.tar.*` from the branch (which includes previously deployed packages that were in the clone).

Actually, the real fix is: we need ALL packages in repo.db, not just the one being deployed. The current glob is correct for maintaining a multi-package repository. **No change needed.**

~~- [ ] **Commit**~~ (skipped — no change needed)

---

### Task 7: Fix duplicate git config in deploy-package.sh

**Problem:** `git config --global user.name/email` is set twice — once at line 34-35 and again at line 90-91. The second is redundant.

**Files:**

- Modify: `ci/deploy-package.sh` — remove lines 90-91

- [ ] **Remove duplicate git config**

Remove lines 90-91:

```bash
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
```

These are already set at lines 34-35 with `--global` flag, which persists for the entire script.

- [ ] **Commit**

```bash
git add ci/deploy-package.sh && git commit -m "fix: remove duplicate git config in deploy loop"
```

- [ ] **Verify CI passes**

---

### Task 8: Add build-package.sh error checking for pacman-key

**Problem:** `pacman-key --init` and `pacman-key --populate` can fail silently if entropy is low or keyring is corrupted. The script continues and `makepkg -s` fails later with a confusing error.

**Files:**

- Modify: `ci/build-package.sh:14-16`

- [ ] **Add error checking after pacman-key**

Current code:

```bash
pacman-key --init
pacman-key --populate archlinuxarm
```

Add explicit error checks:

```bash
pacman-key --init || { echo "ERROR: pacman-key --init failed"; exit 1; }
pacman-key --populate archlinuxarm || { echo "ERROR: pacman-key --populate failed"; exit 1; }
```

Note: `set -euo pipefail` already handles this (non-zero exit → script exits). But explicit messages are clearer in CI logs. Since we already have `set -euo pipefail`, the `|| { echo ...; exit 1; }` is redundant. The real improvement would be to add `set -x` for debug output in this section only.

Actually, `set -euo pipefail` already catches failures. Adding `set -x` at the top would make the script too verbose. The best improvement here is to just leave it as-is — `set -euo pipefail` already handles errors. **No change needed.**

~~- [ ] **Commit**~~ (skipped — `set -euo pipefail` is sufficient)

---

### Task 9: Remove --privileged from docker run

**Problem:** `--privileged` grants all Linux capabilities to the container. Only `makepkg -s` runs inside, which only needs `sudo` for `pacman -S` dependency installs. `--privileged` is unnecessary and a security risk.

**Files:**

- Modify: `.github/workflows/build.yml:81`

- [ ] **Replace --privileged with minimal capabilities**

Current code:

```yaml
docker run -d --name builder --privileged \
```

Replace with:

```yaml
docker run -d --name builder \
```

Just remove `--privileged`. The Arch container doesn't need it — `makepkg -s` works fine without it. If any package needs specific capabilities, they can be added per-package later.

**⚠️ Risk:** If previous builds relied on `--privileged` for something (like `pacman-key --init` or device access), removing it might break builds. Must verify CI passes after this change.

- [ ] **Commit**

```bash
git add .github/workflows/build.yml && git commit -m "fix: remove --privileged from docker run"
```

- [ ] **Verify CI passes (kmscon + mozillavpn both build and deploy)**

---

### Task 10: Fix HTML escaping in deploy-package.sh index.html

**Problem:** `$(basename $f)` in `index.html` generation can contain HTML-special characters (`&`, `<`, `>`, `"`). Package names with unusual characters could break the HTML.

**Files:**

- Modify: `ci/deploy-package.sh:83-84`

- [ ] **Escape HTML entities in filenames**

Current code:

```bash
    for f in aarch64/*.pkg.tar.*; do
      [ -f "$f" ] && echo "<a href=\"$f\">$(basename $f)</a>"
```

Replace with:

```bash
    for f in aarch64/*.pkg.tar.*; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      hreffile=$(echo "$f" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
      namefile=$(echo "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      echo "<a href=\"$hreffile\">$namefile</a>"
    done
```

- [ ] **Commit**

```bash
git add ci/deploy-package.sh && git commit -m "fix: escape HTML entities in index.html generation"
```

- [ ] **Verify CI passes**

---

### Task 11: Add Rust/Cargo cache for mozillavpn

**Problem:** mozillavpn includes Rust components (via tunnelprovider). Cargo downloads and recompiles crates on every build. Adding a Cargo cache would cut build time significantly.

**Files:**

- Modify: `.github/workflows/build.yml` (add cache step)
- Modify: `ci/build-package.sh` (add cargo cache env vars)

- [ ] **Add Cargo cache to workflow**

Add after the ccache step (line 74):

```yaml
# ── Cargo cache ──
- name: Cache cargo registry
  uses: actions/cache@v4
  with:
    path: /tmp/cargo-registry
    key: cargo-v1-${{ matrix.pkg }}-${{ hashFiles(format('packages/{0}/PKGBUILD', matrix.pkg)) }}
    restore-keys: cargo-v1-${{ matrix.pkg }}-

- name: Cache cargo git
  uses: actions/cache@v4
  with:
    path: /tmp/cargo-git
    key: cargo-git-v1-${{ matrix.pkg }}-${{ hashFiles(format('packages/{0}/PKGBUILD', matrix.pkg)) }}
    restore-keys: cargo-git-v1-${{ matrix.pkg }}-
```

- [ ] **Mount cargo cache dirs in docker run**

In the "Build in container" step, add `-v` mounts:

```yaml
docker run -d --name builder \
-v /tmp/pacman-cache:/var/cache/pacman/pkg \
-v /tmp/ccache:/ccache \
-v /tmp/cargo-registry:/cargo-registry \
-v /tmp/cargo-git:/cargo-git \
lfdevs/archlinuxarm:base-devel sleep infinity
```

- [ ] **Set CARGO_HOME in build-package.sh**

Add after the ccache block:

```bash
# Set up Cargo cache (if mounted)
if [ -d /cargo-registry ]; then
  export CARGO_HOME=/cargo-home
  mkdir -p "$CARGO_HOME"
  ln -sf /cargo-registry "$CARGO_HOME/registry"
  ln -sf /cargo-git "$CARGO_HOME/git"
fi
```

Wait — `CARGO_HOME` needs to be writable and the symlinks need to point to the mounted volumes. This is fragile because `ln -sf` might not work if `$CARGO_HOME/registry` already exists. Let me simplify:

```bash
# Set up Cargo cache (if mounted)
if [ -d /cargo-registry ]; then
  export CARGO_HOME=/cargo-home
  mkdir -p "$CARGO_HOME"
  [ -e "$CARGO_HOME/registry" ] || ln -s /cargo-registry "$CARGO_HOME/registry"
  [ -e "$CARGO_HOME/git" ] || ln -s /cargo-git "$CARGO_HOME/git"
fi
```

- [ ] **Commit**

```bash
git add .github/workflows/build.yml ci/build-package.sh && git commit -m "feat: add cargo registry/git cache for Rust packages"
```

- [ ] **Verify CI passes (mozillavpn build should be faster on second run)**

---

## Verification Plan

After all tasks are applied:

1. Push all commits
2. Verify `kmscon` and `mozillavpn` both build and deploy successfully
3. Verify `https://dryamovvv.github.io/pkgs/aarch64/repo.db` returns HTTP 200
4. Verify both package files are accessible on Pages
5. Trigger a second run to verify caching (Docker, pacman, ccache, cargo)
