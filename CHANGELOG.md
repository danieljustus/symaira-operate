# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0]

Initial Symaira release: the author's `mac-operator` prototype rebranded and
aligned to Symaira conventions. Builds; 29 tests passing.

### Added
- SPM package: `SymOperateCore`, `SymOperateMCP`, `symoperate` (executable).
- CLI: `serve`, `doctor`, `permissions status|grant`.
- MCP stdio server with tools: `snapshot`, `query_ui`, `list_apps`,
  `list_windows`, `click`, `type_text`, `press_keys`, `scroll`, `drag`,
  `launch_app`, `focus_window`, `menu_action`, `wait_for`, `permissions_status`.
- Safety guards: destructive-control refusal, `AXSecureTextField` block,
  ephemeral `element_id` cache.

### Not yet (see docs/roadmap.md)
- Multi-display capture, OCR fallback, stronger action policy, corekit/release
  alignment, Swift 6 strict concurrency.
