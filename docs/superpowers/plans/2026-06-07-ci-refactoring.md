# CI Refactoring Implementation Plan — STATUS: COMPLETE

> **Для agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical CI issues (Docker cache inefficiency, ccache key blowup, token leak risk, deploy race conditions) and improve reliability. **ALL TASKS COMPLETED as of 2026-06-07.**

**Architecture:** Each task is an independent, self-contained fix. Order from most impactful to least. CI must pass after each task.

**Tech Stack:** GitHub Actions (YAML), Bash, Docker, git

---

### Task 1: Fix Docker image cache — skip pull on cache hit ✅

**Status:** DONE — build.yml splits pull/load into separate steps with `cache-hit` condition.

---

### Task 2: Fix ccache key — use source hash instead of run_id ✅

**Status:** DONE — ccache key now uses `build_hash_sanitized` (which includes PKGBUILD + sources + sha256sums + ci/build-package.sh).

---

### Task 3: Add timeout-minutes to build step ✅

**Status:** DONE — `timeout-minutes: 90` added to build step.

---

### Task 4: Fix token leak risk in deploy-package.sh ✅

**Status:** NOT APPLICABLE — deploy-package.sh was completely rewritten (now uses SCP + flock, no git clone to GitHub).

---

### Task 5: Add concurrency group to prevent deploy conflicts ✅

**Status:** DONE — `concurrency: deploy-${{ github.ref }}` with `cancel-in-progress: false`.

---

### Task 6: Fix repo-add glob in deploy-package.sh ✅

**Status:** NOT APPLICABLE — deploy-package.sh rewritten, repo-add uses explicit package name.

---

### Task 7: Fix duplicate git config in deploy-package.sh ✅

**Status:** NOT APPLICABLE — old deploy-package.sh removed, new version has no duplicates.

---

### Task 8: Add build-package.sh error checking ✅

**Status:** NOT NEEDED — `set -euo pipefail` is sufficient.

---

### Task 9: Remove --privileged from docker run ✅

**Status:** DONE — `--privileged` removed from docker run command.

---

### Task 10: Fix HTML escaping in deploy-package.sh index.html ✅

**Status:** DONE — HTML escaping added in new deploy-package.sh.

---

### Task 11: Add Rust/Cargo cache ✅

**Status:** DONE — cargo registry + git cache added, mounted into Docker container.

---

## Additional Completed Improvements (not in original plan)

- **Deterministic build hash:** `compute-build-hash.sh` generates hash from PKGBUILD + sha256sums + local source files + ci/build-package.sh
- **Build artifact cache:** Skip rebuilds when inputs unchanged. Cache only `.pkg.tar.*` / `.sig` (not full build dir) — reduced from 100-400 MB to 1-40 MB per package
- **Cache directory pre-creation:** Directories created before cache steps to avoid "Path does not exist" warnings on cache hit
- **force_rebuild_all:** workflow_dispatch input for forced full rebuild with cache invalidation
- **awk source parsing fix:** Fixed broken `!/^source=\(|/^\)/` regex in compute-build-hash.sh
- **Deploy job on ARM64:** deploy-packages runs on `ubuntu-24.04-arm` to natively run ARM64 Docker image
- **auto-add-sha256sums workflow:** Automated checksum updates in PKGBUILDs

---

## Verification Plan

1. Push all commits ✅
2. Verify all packages build and deploy ✅ (26/26 success)
3. Verify caching works ✅ (23/25 cache hit after cache warmup)
4. Verify cache size is manageable ✅ (~3 GB total, < 10 GB limit)
