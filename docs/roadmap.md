# Roadmap

## v0.1 (current)

- [x] Rebrand from `mac-operator` to Symaira conventions; builds, 106 tests pass.
- [x] MCP tools: snapshot, query_ui, list_apps, list_windows, click, type_text,
      press_keys, scroll, drag, launch_app, focus_window, menu_action, wait_for,
      permissions_status.
- [x] Safety guards: destructive-control refusal, secure-field block, ephemeral
      element cache.

## v0.2 — robustness

- [x] Multi-display selection (currently main display only).
- [x] Window-scoped capture.
- [x] OCR fallback for apps with weak Accessibility metadata.
- [x] Stronger, configurable action-policy checks (allow/deny lists).
- [x] Richer UI targeting (roles, predicates).

## v0.3 — ecosystem alignment

- [ ] `doctor` JSON shape + exit codes aligned with the family (consider a thin
      Swift mirror of corekit exit codes).
- [ ] Pair with `symaira-tune`: shared macOS-agent guidance / optional combined
      MCP preset (operate + tune) for "control the Mac" agents.
- [ ] Surface in `symaira-scope` discovery (registered MCP server).

## Infra

- [ ] Notarized DMG + Homebrew cask in `../homebrew-tap` (mirror symaira-terminal).
- [ ] CI on macOS runner (build + test); SwiftLint gate.
- [x] Tighten to Swift 6 strict concurrency (AppKit/ScreenCaptureKit MainActor
      isolation; currently Swift 5 language mode).
- [ ] Update checker (GitHub releases), ecosystem convention.
