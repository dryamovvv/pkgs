# GitHub Labels

This document defines every label used in this repository and how AI agents must behave when they encounter them.

## Label Groups

### Standard GitHub Labels

These follow GitHub defaults. AI does not act on them unless referenced in a comment.

| Label              | Color     | Purpose                                    |
| ------------------ | --------- | ------------------------------------------ |
| `bug`              | `#d73a4a` | Something isn't working                    |
| `documentation`    | `#0075ca` | Improvements or additions to documentation |
| `enhancement`      | `#a2eeef` | New feature or request                     |
| `good first issue` | `#7057ff` | Good for newcomers                         |
| `help wanted`      | `#008672` | Extra attention is needed                  |
| `question`         | `#d876e3` | Further information is requested           |
| `invalid`          | `#e4e669` | This doesn't seem right                    |
| `duplicate`        | `#cfd3d7` | This issue or pull request already exists  |
| `wontfix`          | `#ffffff` | This will not be worked on                 |

### AI Workflow Labels

These drive the AI CI pipeline.

| Label            | Color     | Purpose                                                               | Trigger                                            |
| ---------------- | --------- | --------------------------------------------------------------------- | -------------------------------------------------- |
| `new-package`    | `#0052CC` | AI researches upstream, builds PKGBUILD with ALL features, creates PR | `opencode-builder` on issue.opened / issue.comment |
| `modify-package` | `#8B4513` | AI detects new version, updates PKGBUILD, rebuilds                    | `opencode-builder` on issue.opened / issue.comment |
| `ci-failure`     | `#B60205` | CI build failed, auto-fix eligible. Created by build failure script.  | `auto-fix-runner` on issue.opened                  |
| `fix-attempt-1`  | `#FBBC04` | First auto-fix attempt                                                | Counter                                            |
| `fix-attempt-2`  | `#FBBC04` | Second auto-fix attempt                                               | Counter                                            |
| `fix-attempt-3`  | `#FBBC04` | Third auto-fix attempt                                                | Counter                                            |
| `unfixable`      | `#000000` | Auto-fix exhausted after 3 attempts, manual fix needed                | —                                                  |

### Priority Labels

| Label     | Color     | Purpose                                                 |
| --------- | --------- | ------------------------------------------------------- |
| `backlog` | `#5319E7` | Issue acknowledged but NOT scheduled for implementation |

## AI Behavior Rules

### Rule 1: Backlock is BLOCKED (no action)

Issues with the `backlog` label are **never** acted upon by AI agents. The AI must skip, ignore, or exit when the only label is `backlog` or when `backlog` is present alongside actionable labels.

**Rationale:** `backlog` means "we want this someday but not now." Without explicit removal of `backlog` and addition of an actionable label (`new-package`, `modify-package`, `enhancement`, `bug`), the issue should remain untouched.

Workflow triggers explicitly exclude `backlog` labels. If an issue arrives with only `backlog`, no CI job fires.

### Rule 2: new-package — build from scratch

1. Research the upstream: `arch-mcp` for Arch Wiki / AUR / official PKGBUILDs, `Context7` for build system docs, web search for features
2. Run upstream build system introspection:
   - CMake: `cmake -LAH` or grep `CMakeLists.txt` for `option()` / `cmake_dependent_option()`
   - Meson: `meson configure` or grep `meson_options.txt`
   - Cargo: list features from `cargo metadata` or `[features]` in `Cargo.toml`
   - Autotools: `./configure --help`
3. Include ALL features in `PKGBUILD` (explain trade-offs to user if conflicts arise). Always ask user about optional features that pull heavy dependencies.
4. Always enable docs (`-Ddocs=enabled`, `--enable-docs`).
5. Always disable tests (`-Dtests=false`, `--disable-tests`, `BUILD_TESTS=OFF`).
6. Apply RPi5 CFLAGS/CXXFLAGS/LDFLAGS from `AGENTS.md`.
7. Create `.nvchecker.toml` for future update tracking.
8. Create `README.md` with package description, features enabled, and usage.
9. Create `AGENTS.md` with package-specific notes for future AI agents.
10. Build with `makepkg -s --noconfirm`. Retry up to 5 times on failure. After 5 failures, stop and report.

### Rule 3: modify-package — update existing

1. Check `.nvchecker.toml` / `pkgver` for the new version.
2. Research upstream for new build options, features, or dependency changes.
3. Update `PKGBUILD` with new version, sums, and any new feature flags.
4. Update `.nvchecker.toml` if the source URL pattern changed.
5. Update `README.md` and `AGENTS.md` if behavior changed.
6. Build and verify. Retry up to 5 times.

### Rule 4: ci-failure / fix-attempt-N — auto-fix

1. Read build logs from the failed run.
2. Identify the root cause (missing dep, syntax error, upstream API change, etc.).
3. Fix `PKGBUILD` or related files.
4. Validate with `bash -n PKGBUILD`.
5. Commit and open a PR.
6. After 3 failed attempts (`fix-attempt-3` → `unfixable`), stop and report to human.

### Rule 5: unfixable — hands off

Do NOT retry. Do NOT touch. The issue needs human intervention.

## Workflow Trigger Map

| Label(s)                         | Event                        | Workflow Job                           |
| -------------------------------- | ---------------------------- | -------------------------------------- |
| `new-package`                    | issue.opened / issue.comment | `opencode-builder`                     |
| `modify-package`                 | issue.opened / issue.comment | `opencode-builder`                     |
| `ci-failure` (+ `fix-attempt-N`) | issue.opened                 | `auto-fix-runner`                      |
| any                              | pull_request.opened / push   | `lint.yml`                             |
| any                              | push to main                 | `build.yml` (detect → matrix → deploy) |
| any                              | AI PR opened                 | `opencode-review`                      |

Issues with only `backlog` or standard GitHub labels (bug, enhancement, etc.) do NOT trigger automation.
