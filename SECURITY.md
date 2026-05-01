# Security Policy

## Reporting a vulnerability

**Do not open a public GitHub issue for security-sensitive reports.**

Use GitHub private vulnerability reporting:

> https://github.com/h5nam/mq-dir/security/advisories/new

Include:

- A description of the issue and a proof-of-concept if you have one.
- The version of mq-dir affected (Help → About, or `git rev-parse HEAD` if building from source).
- The macOS version you reproduced on.
- Whether you've published the issue anywhere (please don't, until we coordinate).

If private vulnerability reporting is not available, email the maintainer using
the address on the maintainer's GitHub profile.

Expect an acknowledgement within **3 working days**.

## Disclosure window

We aim to coordinate disclosure within **90 days** of acknowledged report. If we need more time we'll explain why; if the issue is being actively exploited we'll move faster. Either way we'll keep you in the loop.

## Scope

**In scope:**
- Code shipped in this repository (everything under `Sources/`, `Resources/`, `Scripts/`, `.github/workflows/`).
- Build / release tooling (`project.yml`, `Package.swift`, `Casks/mq-dir.rb`).
- Documentation that contains executable instructions (e.g. `xattr` commands in `CONTRIBUTING.md`).

**Out of scope:**
- Third-party dependencies — please report upstream and let us know so we can pin / patch.
- macOS / Apple-platform vulnerabilities — report to Apple Security.
- Social-engineering or phishing not specific to this project.

## Hall of Fame

Reporters who follow coordinated disclosure get acknowledged in `CHANGELOG.md` for the release that contains the fix, unless they ask to remain anonymous. We'd rather thank you publicly than not.
