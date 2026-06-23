# Contributing to symaira-operate

Thank you for your interest in improving `symaira-operate`! This document covers how to build, test, and submit changes.

## Development setup

Requirements:

- macOS 15+
- Swift 6 toolchain (Xcode 16 or later, or the matching Command Line Tools)
- [SwiftLint](https://github.com/realm/SwiftLint) for linting

Clone the repository and verify your environment:

```bash
git clone https://github.com/danieljustus/symaira-operate.git
cd symaira-operate
swift build
swift test
swift run -q symoperate doctor
```

## Coding guidelines

- Follow the existing Swift style; run `swiftlint lint --strict` before pushing.
- Keep AppKit/Accessibility/ScreenCaptureKit code inside `SymOperateCore`.
- Do not weaken the destructive-action guard or bypass `AXSecureTextField` checks.
- Add tests for new behavior when feasible. The project uses XCTest.
- Update relevant docs (`docs/architecture.md`, `docs/roadmap.md`, `README.md`) when the public tool contract changes.

## Submitting changes

1. Fork the repository and create a feature branch from `main`.
2. Make focused, atomic commits.
3. Ensure CI would pass: `swift build`, `swift test`, and `swiftlint lint --strict`.
4. Open a pull request against `main`. The repository uses squash-merge.

## Reporting issues

Please use the issue templates in `.github/ISSUE_TEMPLATE/`. For security-sensitive reports, see [`SECURITY.md`](SECURITY.md).

## Code of conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions?

Open a [discussion](https://github.com/danieljustus/symaira-operate/discussions) or reach out via the [Symaira website](https://symaira.com).
