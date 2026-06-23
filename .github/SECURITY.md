# Security Policy

## Supported Versions

Only the latest released version of `symaira-operate` receives security updates. Because the project is still pre-1.0, earlier patch versions are not maintained separately.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in `symaira-operate`, please report it privately so we can address it responsibly.

- **Preferred:** Use [GitHub Private Vulnerability Reporting](https://github.com/danieljustus/symaira-operate/security/advisories/new) on this repository.
- **Alternative:** Email Daniel Justus at `security@symaira.com` with details.

Please include:
- A description of the vulnerability and its impact
- Steps to reproduce, or a minimal proof of concept
- Affected versions
- Suggested mitigation or fix, if any

We aim to acknowledge reports within 48 hours and release a fix within 14 days for critical issues.

## What counts as a security issue

- Vulnerabilities that could allow an unauthorized process or remote party to drive the GUI without user consent
- Bypasses of the destructive-action guard or permission checks
- Leaks of screenshot, accessibility tree, or input data outside the local MCP session
- Supply-chain issues in the release build, signing, or notarization pipeline

## What does not count

- Social-engineering attacks that require the user to explicitly grant permissions to a malicious host
- Physical-access scenarios where an attacker already controls the unlocked Mac
- Issues in third-party dependencies (please report those to the upstream project)

## Security-related design notes

`symaira-operate` is intentionally local and supervised:

- It speaks stdio JSON-RPC only — no network listener.
- The Accessibility and Screen Recording permissions belong to the host process that launches `symoperate`, not to `symoperate` itself.
- Element-based actions refuse destructive controls and `AXSecureTextField`.

See [AGENTS.md](AGENTS.md) and [docs/architecture.md](docs/architecture.md) for the current trust model and safety guards.
