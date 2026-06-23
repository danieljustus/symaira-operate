# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.1]

### Security
- Hardened safety guards around destructive controls and secure text fields,
  including refusal of raw-coordinate clicks/drags that bypass element-based
  checks (#29, #42).
- Refined `ActionPolicy` allow/deny-list handling for menu and element actions
  (#14, #29).

### Added
- Multi-display support: choose a display by ID or index for screenshots and
  UI queries (#14).
- Window-scoped screen capture and `focus_window` / `list_windows` enrichment
  (#14).
- OCR fallback via Vision framework for applications with weak Accessibility
  metadata, with configurable confidence threshold (#14).
- Configurable action policy (allow/deny lists) for richer UI targeting (#14).
- UI query predicates by role, title, label, and frame (#14).
- Async `wait_for` polling with `Task.sleep` to reduce AX IPC load (#30).
- `version` MCP tool and CLI command that report the current build and check
  GitHub releases for updates (#14).

### Fixed
- Prevent snapshot PNG accumulation in the temporary directory (#14).
- Eliminate force-casts in `AXHelpers` in favor of safe CF type checks (#29).
- Dependency bumps for GitHub Actions workflows (#1, #27, #28).

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
