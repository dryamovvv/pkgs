# Add Package via Issue — Design Spec

**Date:** 2026-06-08
**Status:** Approved

## Goal

Automate adding new packages: user creates an issue → AI researches, builds, creates PR → CI builds → auto-merge → release updated.

## Architecture

```
Issue opened (label: new-package)
  │  opencode: research → enable all features → branch add-package/{name}
  │  → PKGBUILD + AGENTS.md + README.md → comment (list features) → PR
  │
├── PR opened
│   │  opencode: code review → approve or request changes
│   │  build.yml: build + deploy to latest release
│   │  CI success → auto-merge
│   │
├── User comments "disable X"
│   │  opencode: read comment → update PKGBUILD/docs → comment back
│   │  build.yml: rebuild
│   │
└── main updated → build.yml rebuilds → deploy updates latest release
```

## Changes

### Issue Template (`add_new_package.md`)

- Simple fields: package name, upstream URL (optional), preferences (optional)
- AI defaults: enable all features, disable tests, strip debug, include docs
- AI comments on issue listing what it enabled

### opencode.yml

- Detect `new-package` label on issue opened
- Create branch: `add-package/{pkg-name}`
- Use add-package skill instructions in prompt
- After PR creation: comment on issue with PR link + enabled features

### auto-merge-on-ci-success.yml

- Match PRs from `add-package/*` branches (not just `auto-fix/*`)
