# symaira-operate

> Let an AI agent see and drive your Mac — locally, over MCP.

[![CI](https://github.com/danieljustus/symaira-operate/actions/workflows/ci.yml/badge.svg)](https://github.com/danieljustus/symaira-operate/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/danieljustus/symaira-operate?sort=semver)](https://github.com/danieljustus/symaira-operate/releases/latest)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)

`symoperate` is a native macOS desktop-automation **MCP server**. It exposes
screenshots, the Accessibility tree, mouse/keyboard input, and app/window control
over stdio, so an agent (Claude Desktop, OpenCode, Cursor, …) can operate the
GUI: open an app, find a button, click it, type, save. It is a supervised, local
tool — not a remote-control daemon.

Part of the [Symaira](../ECOSYSTEM.md) family, and the agent-native sibling of
[`symaira-tune`](../symaira-tune) (hardware tuning): **operate = GUI actions,
tune = thermals/brightness/power.**

> **Status: v0.2.3.** Working native implementation (rebranded from the author's
> `mac-operator` prototype), 111 tests passing.

## Why symoperate?

- **Local and supervised.** No remote listener, no daemon. The agent sends one
  action at a time over stdio and gets fresh state back.
- **MCP-native.** Works with any MCP host — Claude Desktop, OpenCode, Cursor, …
  — without host-specific plugins.
- **Element-first.** Prefer stable accessibility `element_id`s over brittle
  screen coordinates; re-snapshot after each UI change.
- **Safety-guarded.** Refuses destructive controls and secure text fields; never
  automate passwords or permission dialogs without explicit confirmation.
- **Native macOS.** Built with AppKit, Accessibility, and ScreenCaptureKit for
  reliable performance on macOS 15+.

## Install

**Homebrew (recommended):**

```bash
brew install danieljustus/tap/symoperate
```

**Direct download:** grab the latest `symoperate.dmg` from the
[Releases page](https://github.com/danieljustus/symaira-operate/releases/latest),
open it, and move `symoperate` to `/usr/local/bin/` (or any directory on your
`PATH`).

Then grant permissions and verify the install:

```bash
symoperate permissions grant accessibility
symoperate permissions grant screen
symoperate doctor
```

## Requirements

- macOS 15+
- `Accessibility` and `Screen Recording` permissions for the host process

## Build

```bash
swift build            # binary at .build/debug/symoperate
swift test             # run the test suite
swift run -q symoperate doctor
```

## CLI

```text
symoperate serve                          Run the MCP server over stdio
symoperate doctor                         Permission status + environment probes (JSON)
symoperate permissions status             Current macOS permissions
symoperate permissions grant accessibility
symoperate permissions grant screen
```

## MCP tools

`snapshot`, `query_ui`, `list_apps`, `list_windows`, `click`, `type_text`,
`press_keys`, `scroll`, `drag`, `launch_app`, `focus_window`, `menu_action`,
`wait_for`, `permissions_status`.

Register with an MCP host:

```json
{ "mcpServers": { "symoperate": { "command": "/abs/path/symoperate", "args": ["serve"] } } }
```

### Recommended agent loop

1. `query_ui` (or `snapshot`) → 2. decide → 3. prefer `element_id` over raw
coordinates → 4. one action → 5. re-snapshot before the next step.

## Safety

Supervised, local, stdio-only. Destructive controls (Delete/Trash/Uninstall/
Allow/Authorize/Unlock/Quit/…) and secure text fields are refused for
element-based actions. Don't automate passwords, payments, or permission dialogs
without explicit user confirmation. See [AGENTS.md](AGENTS.md) and `NOTICE`.

## Documentation

- [docs/architecture.md](docs/architecture.md) — components & tool contract
- [docs/roadmap.md](docs/roadmap.md) — built vs planned

## License

MIT © 2026 Daniel Justus.
