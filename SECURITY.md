# Security Policy

## Reporting a Vulnerability

This repository uses **GitHub Private Vulnerability Reporting (PVR)** for security disclosures.

To report a vulnerability:

1. Go to the repository's **Security** tab
2. Click **Report a vulnerability**
3. Fill in the details (description, impact, steps to reproduce)

If PVR is not available for your account, email `repo@dryam.ru`.

Do **not** open public issues for security vulnerabilities.

### What to include

- Package or component affected
- Description of the vulnerability and its impact
- Steps to reproduce or a proof of concept
- Suggested remediation (optional)

### Response timeline

- Acknowledgment within 48 hours
- Assessment and fix plan within 7 days
- Fix published within 90 days (coordinated disclosure)

## GPG Signing Key

All packages and the repository database are signed with:

```text
Key ID:     BB827D35
Fingerprint: 0F98FE406BB366EB10AFAD8D90B35929BB827D35
Key type:   RSA 4096
UID:        pkgs.dryam.ru Repo Signing Key <repo@dryam.ru>
```

Import the key:

```bash
sudo pacman-key --recv-keys 0F98FE406BB366EB10AFAD8D90B35929BB827D35
sudo pacman-key --lsign-key 0F98FE406BB366EB10AFAD8D90B35929BB827D35
```

## Scope

Covered by this policy:

- Packages in the `packages/` directory
- CI/CD scripts in `ci/`
- Workflow definitions in `.github/workflows/`

Not covered:

- Upstream projects (report to their respective maintainers)
- The Arch Linux ARM base system (report to ALARM)
